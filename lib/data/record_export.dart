import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n/app_language.dart';
import '../l10n/app_strings.dart';
import 'measurement_record.dart';

/// 1回の測定を「持ち出せるファイル」にする。
///
/// 2種類作る。役割が違うので、どちらかで足りることはない。
///   * PDF  — 人が読むもの。獣医がそのまま見て印刷できる1枚。
///   * CSV  — 機械が読むもの。あとで解析や表計算、将来のAIに回す元データ。
///
/// **PDF の日本語について。** package:pdf は端末にインストールされた
/// フォントを使えないので、TTF を同梱しないと日本語は豆腐(□)になる。
/// `assets/fonts/NotoSansJP-Regular.ttf` があればそれを使い、無ければ
/// 英字ラベルの PDF を出す。「フォントが無いので書き出せません」で
/// 止めるより、読める形で出したほうがましなので。
class RecordExport {
  const RecordExport._();

  /// 日本語フォントの候補。最初に見つかったものを使う。
  static const List<String> _fontAssets = <String>[
    'assets/fonts/NotoSansJP-Regular.ttf',
    'assets/fonts/NotoSansSC-Regular.ttf',
  ];

  static pw.Font? _cjkFont;
  static bool _fontChecked = false;

  /// 同梱フォントを一度だけ読む。見つからなければ null のまま。
  ///
  /// `on Exception` ではなく全部捕まえる。壊れた TTF を渡すと package:pdf は
  /// `RangeError`（Exception ではなく Error）を投げるので、Exception だけ
  /// 見ていると書き出しごと落ちる。途中で止まったダウンロードが 0 バイトの
  /// ファイルを残す、というのは実際に起きる。
  static Future<pw.Font?> _loadCjkFont() async {
    if (_fontChecked) return _cjkFont;
    _fontChecked = true;
    for (final String path in _fontAssets) {
      try {
        final ByteData data = await rootBundle.load(path);
        // 最小の TTF でも数十 kB はある。それ未満は「置いてあるだけの
        // 空ファイル」か書きかけなので、読まずに捨てる。
        if (data.lengthInBytes < 20 * 1024) continue;
        _cjkFont = pw.Font.ttf(data);
        return _cjkFont;
      } catch (_) {
        // 次の候補へ。どれも読めなければ英字で出す。
        continue;
      }
    }
    return null;
  }

  /// ファイル名の芯。`2026-09-13_1102_78bpm` のような形。
  ///
  /// 日時を先頭に置くと、ファイル名の並びが時間順になる。獣医に何通も
  /// 渡したときに、どれがいつのものか開かずに分かる。
  static String baseName(MeasurementRecord r) {
    final DateTime d = r.startedAt;
    String p(int v) => v.toString().padLeft(2, '0');
    final String hr = r.heartRateBpm == null
        ? 'na'
        : '${r.heartRateBpm!.round()}bpm';
    return '${d.year}-${p(d.month)}-${p(d.day)}_'
        '${p(d.hour)}${p(d.minute)}_$hr';
  }

  // ---------------------------------------------------------------- CSV

  /// 1測定ぶんの CSV。
  ///
  /// 履歴全体の CSV(`MeasurementStore.exportCsv`)とは別物。あちらは1行1測定の
  /// 一覧で、こちらは1測定の全貌 — 拍ごとの間隔まで入れる。獣医に「この測定を
  /// 見てほしい」と渡すのはこちら。
  static String buildCsv(MeasurementRecord r, AppStrings s) {
    final StringBuffer b = StringBuffer();
    // 先頭の注意書きは人向け(表示言語)。列名は機械向けなので英語で固定する。
    // 日本語の列名にすると Excel の文字コードや将来の解析スクリプトで
    // 引っかかるし、列名が言語で変わると同じ列を指せなくなる。
    b.writeln('# ${s.reportTitle}');
    b.writeln('# ${s.reportMeasuredWith}');
    b.writeln('# ${s.notEcgDisclaimer}');
    b.writeln('# ${s.hrvClinicalNote}');
    if (r.caveatCode != null) {
      b.writeln('# ${_caveat(r.caveatCode!, s)}');
    }
    b.writeln();

    b.writeln('field,value');
    void kv(String k, Object? v) => b.writeln('$k,${_csv(v)}');
    kv('measured_at', r.startedAt.toIso8601String());
    kv('duration_s', r.durationSeconds.toStringAsFixed(0));
    kv('heart_rate_bpm', r.heartRateBpm?.toStringAsFixed(1));
    kv('heart_rate_confidence', r.heartRateConfidence.toStringAsFixed(2));
    // 拍を1つずつ数えた心拍。上の heart_rate_bpm は波の周期から出した値で、
    // 数え方が独立しているので、2つ並べておくと受け取った側で検算できる。
    kv('beat_rate_bpm', r.beatRateBpm?.toStringAsFixed(1));
    kv('rate_disagrees', r.rateDisagrees ? 'yes' : 'no');
    kv('respiration_per_min', r.respirationPerMin?.toStringAsFixed(1));
    kv('body_temp_c', r.bodyTempC?.toStringAsFixed(1));
    kv('quality', r.quality);
    kv('beat_count', r.beatCount);
    kv('beat_interval_cv_percent',
        r.beatIntervalCvPercent?.toStringAsFixed(1));
    kv('sdnn_ms', r.sdnnMs?.toStringAsFixed(1));
    kv('rmssd_ms', r.rmssdMs?.toStringAsFixed(1));
    kv('dropped_packets', r.gapCount);
    kv('receive_errors', r.receiveErrors);
    kv('sample_rate_hz', r.imuRateHz);
    kv('posture', r.posture);
    kv('note', r.note);
    b.writeln();

    // 拍ごとの間隔。これがあると受け取った側で計算し直せる。
    b.writeln('beat_index,interval_ms');
    for (int i = 0; i < r.beatIntervalsMs.length; i++) {
      b.writeln('${i + 1},${r.beatIntervalsMs[i].toStringAsFixed(1)}');
    }
    return b.toString();
  }

  // ---------------------------------------------------------------- PDF

  /// 1測定ぶきの PDF を1枚作る。
  static Future<Uint8List> buildPdf(
      MeasurementRecord r, AppStrings strings) async {
    final pw.Font? cjk = await _loadCjkFont();
    // フォントが無いときは英語の文言に落とす。日本語のまま豆腐を並べるより、
    // 読める英語のほうが獣医にとってましなので。
    final AppStrings s =
        cjk == null ? AppStrings.forLanguage(AppLanguage.en) : strings;

    final pw.ThemeData theme = cjk == null
        ? pw.ThemeData.base()
        : pw.ThemeData.withFont(base: cjk, bold: cjk, italic: cjk);

    const PdfColor ink = PdfColor.fromInt(0xFF2B2320);
    const PdfColor sub = PdfColor.fromInt(0xFF8A7C70);
    const PdfColor accent = PdfColor.fromInt(0xFFB85042);
    const PdfColor good = PdfColor.fromInt(0xFF6E9271);
    final PdfColor qColor = switch (r.quality) {
      'good' => good,
      'fair' => const PdfColor.fromInt(0xFFD9A441),
      _ => accent,
    };

    final pw.Document doc = pw.Document(theme: theme);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 44, 40, 40),
        build: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(s.reportTitle,
                style: pw.TextStyle(
                    fontSize: 19, fontWeight: pw.FontWeight.bold, color: ink)),
            pw.SizedBox(height: 3),
            pw.Text(_stamp(r.startedAt),
                style: pw.TextStyle(fontSize: 10.5, color: sub)),
            pw.SizedBox(height: 18),

            // 主役の数値。ここだけ大きくする。
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: <pw.Widget>[
                pw.Text(r.heartRateBpm?.round().toString() ?? '--',
                    style: pw.TextStyle(
                        fontSize: 44,
                        fontWeight: pw.FontWeight.bold,
                        color: ink)),
                pw.SizedBox(width: 5),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 7),
                  child: pw.Text('bpm',
                      style: pw.TextStyle(fontSize: 12, color: sub)),
                ),
                pw.SizedBox(height: 22),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: qColor, width: 0.9),
                    borderRadius: pw.BorderRadius.circular(9),
                  ),
                  child: pw.Text(_qualityLabel(r.quality, s),
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: qColor)),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            _table(r, s, ink, sub),
            pw.SizedBox(height: 16),

            if (r.beatIntervalsMs.length >= 3) ...<pw.Widget>[
              pw.Text(s.beatIntervalsTitle,
                  style: pw.TextStyle(
                      fontSize: 10.5,
                      fontWeight: pw.FontWeight.bold,
                      color: ink)),
              pw.SizedBox(height: 5),
              pw.CustomPaint(
                size: const PdfPoint(515, 96),
                painter: (PdfGraphics g, PdfPoint size) =>
                    _paintIntervals(g, size, r.beatIntervalsMs),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                  '${s.beatCvLabel} '
                  '${r.beatIntervalCvPercent?.toStringAsFixed(1) ?? "--"} %',
                  style: pw.TextStyle(fontSize: 9.5, color: sub)),
              pw.SizedBox(height: 16),
            ],

            pw.SizedBox(height: 22),

            // 注意書き。数値と同じページに、読み飛ばせない大きさで置く。
            pw.Container(
              padding: const pw.EdgeInsets.all(11),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: accent, width: 0.8),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(s.notEcgDisclaimer,
                      style: pw.TextStyle(
                          fontSize: 9.5, lineSpacing: 2, color: accent)),
                  pw.SizedBox(height: 5),
                  pw.Text(s.hrvClinicalNote,
                      style: pw.TextStyle(
                          fontSize: 9.5, lineSpacing: 2, color: sub)),
                  if (r.caveatCode != null) ...<pw.Widget>[
                    pw.SizedBox(height: 5),
                    pw.Text(_caveat(r.caveatCode!, s),
                        style: pw.TextStyle(
                            fontSize: 9.5, lineSpacing: 2, color: accent)),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 7),
            pw.Text(s.reportMeasuredWith,
                style: pw.TextStyle(fontSize: 8.5, color: sub)),
            if (cjk == null) ...<pw.Widget>[
              pw.SizedBox(height: 2),
              pw.Text(strings.reportNoJapaneseFont,
                  style: pw.TextStyle(fontSize: 8, color: sub)),
            ],
          ],
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _table(
      MeasurementRecord r, AppStrings s, PdfColor ink, PdfColor sub) {
    final List<(String, String)> rows = <(String, String)>[
      (s.durationLabel, '${r.durationSeconds.toStringAsFixed(0)} ${s.secondsUnit}'),
      (s.respirationShort,
          '${r.respirationPerMin?.toStringAsFixed(0) ?? "--"} ${s.breathsPerMinUnit}'),
      if (r.bodyTempC != null)
        (s.bodyTempLabel, '${r.bodyTempC!.toStringAsFixed(1)} ${s.celsiusUnit}'),
      (s.beatCountLabel, '${r.beatCount}'),
      (s.beatCvLabel,
          '${r.beatIntervalCvPercent?.toStringAsFixed(1) ?? "--"} %'),
      ('SDNN', '${r.sdnnMs?.toStringAsFixed(0) ?? "--"} ms'),
      ('RMSSD', '${r.rmssdMs?.toStringAsFixed(0) ?? "--"} ms'),
      (s.droppedPackets, '${r.gapCount}'),
      if (r.imuRateHz != null) (s.measuredRate, '${r.imuRateHz} Hz'),
      if (r.posture != null) (s.postureLabel, r.posture!),
    ];

    return pw.Table(
      border: pw.TableBorder.all(
          color: const PdfColor.fromInt(0xFFEFE3D6), width: 0.8),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1.1),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1.1),
        3: pw.FlexColumnWidth(1),
      },
      children: <pw.TableRow>[
        for (int i = 0; i < rows.length; i += 2)
          pw.TableRow(
            children: <pw.Widget>[
              _cell(rows[i].$1, sub, bold: false),
              _cell(rows[i].$2, ink, bold: true),
              _cell(i + 1 < rows.length ? rows[i + 1].$1 : '', sub,
                  bold: false),
              _cell(i + 1 < rows.length ? rows[i + 1].$2 : '', ink, bold: true),
            ],
          ),
      ],
    );
  }

  static pw.Widget _cell(String t, PdfColor c, {required bool bold}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 10,
                color: c,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  /// 拍間隔の折れ線。PDF の座標は左下が原点なので、画面用の描画とは上下が逆。
  static void _paintIntervals(
      PdfGraphics g, PdfPoint size, List<double> values) {
    double lo = values.first, hi = values.first;
    double sum = 0;
    for (final double v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
      sum += v;
    }
    final double mean = sum / values.length;
    // 平均の上下に最低 ±60ms。ばらつきが小さいときに拡大されて
    // 「不安定に見える」のを防ぐ。画面のグラフと同じ決め方。
    if (lo > mean - 60) lo = mean - 60;
    if (hi < mean + 60) hi = mean + 60;
    final double range = (hi - lo).abs() < 1e-6 ? 1.0 : hi - lo;

    double y(double v) => (v - lo) / range * size.y;
    double x(int i) =>
        values.length > 1 ? size.x * i / (values.length - 1) : 0;

    // 平均線
    g
      ..setStrokeColor(const PdfColor.fromInt(0xFFB8AA9C))
      ..setLineWidth(0.6)
      ..moveTo(0, y(mean))
      ..lineTo(size.x, y(mean))
      ..strokePath();

    g
      ..setStrokeColor(const PdfColor.fromInt(0xFFB85042))
      ..setLineWidth(1.2)
      ..moveTo(x(0), y(values[0]));
    for (int i = 1; i < values.length; i++) {
      g.lineTo(x(i), y(values[i]));
    }
    g.strokePath();
  }

  // ------------------------------------------------------------- 書き出し

  /// PDF と CSV を端末の一時領域に書き、そのパスを返す。
  ///
  /// iOS はアプリの外に直接書けないので、ここに置いてから共有シートに渡す。
  /// ファイル名は [baseName] なので、共有先(メール・ファイルアプリ)でも
  /// 日時と心拍がそのまま見える。
  static Future<List<String>> writeFiles(
    MeasurementRecord r,
    AppStrings s, {
    required bool pdf,
    required bool csv,
  }) async {
    // 一時領域ではなく Documents に置く。iOS の Info.plist で
    // UIFileSharingEnabled を立ててあるので、共有シートを使わずに
    // 「ファイル」アプリ → このiPhone内 → アプリ名 からも取り出せる。
    // 一時領域だと OS がいつでも消してしまい、あとで探したときに無い。
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/reports');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final String stem = '${dir.path}/${baseName(r)}';
    final List<String> out = <String>[];
    if (pdf) {
      // PDF の生成で転んでも CSV は渡せるようにしておく。獣医に渡すものが
      // 何も無い、という状態だけは作らない。
      try {
        final File f = File('$stem.pdf');
        await f.writeAsBytes(await buildPdf(r, s));
        out.add(f.path);
      } catch (_) {
        if (!csv) rethrow; // PDF だけを頼まれていたなら黙って消せない
      }
    }
    if (csv) {
      final File f = File('$stem.csv');
      await f.writeAsString(buildCsv(r, s));
      out.add(f.path);
    }
    return out;
  }

  /// 生の加速度をそのまま CSV にする。原因調べ用。
  ///
  /// 心拍の数値が信号と合わないとき、加工後の数値だけでは何も分からない。
  /// 元の信号が無いと、推測でアルゴリズムを触ることになる。そうならない
  /// ように、その場の生データを持ち出せるようにしてある。
  ///
  /// 60 秒 × 104 Hz で約 6200 行。CSV として普通に開ける大きさ。
  static Future<String> writeRawCsv({
    required String stem,
    required List<int> deviceUs,
    required List<double> magnitude,
    double? sampleRateHz,
  }) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/reports');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final StringBuffer b = StringBuffer();
    b.writeln('# raw accelerometer magnitude from the collar (diagnostics)');
    b.writeln('# sample_rate_hz,${sampleRateHz?.toStringAsFixed(2) ?? ""}');
    b.writeln('# samples,${magnitude.length}');
    b.writeln('device_us,magnitude_m_s2');
    final int n = math.min(deviceUs.length, magnitude.length);
    for (int i = 0; i < n; i++) {
      b.writeln('${deviceUs[i]},${magnitude[i].toStringAsFixed(6)}');
    }
    final File f = File('${dir.path}/$stem-raw.csv');
    await f.writeAsString(b.toString());
    return f.path;
  }

  // -------------------------------------------------------------- 小物

  static String _qualityLabel(String q, AppStrings s) => switch (q) {
        'good' => s.qualityGood,
        'fair' => s.qualityFair,
        _ => s.qualityUnusable,
      };

  static String _caveat(String code, AppStrings s) => switch (code) {
        'unusable' => s.caveatUnusable,
        'rate_disagrees' => s.caveatRateDisagrees,
        'fair' => s.caveatFair,
        'gaps' => s.caveatManyGaps,
        _ => '',
      };

  static String _csv(Object? v) {
    if (v == null) return '';
    final String t = v.toString();
    return t.contains(',') || t.contains('"') || t.contains('\n')
        ? '"${t.replaceAll('"', '""')}"'
        : t;
  }

  static String _stamp(DateTime d) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}/${p(d.month)}/${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }
}
