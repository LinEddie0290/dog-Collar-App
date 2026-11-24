/// T35 安全タブ：緊急の 4 項目（完成度表 #24〜27）・示例の緊急の記録・今の安全の状態。画面から切り離した計算だけ。
///
/// 緊急の判定はまだない（T34-G）ので、4 項目と記録は示例（D-051 D2・設計メモ T35_安全・我的タブ S2）。
/// 「很久不动」（long_still＝休息 5 分以上＋心拍）は寝ているときも出るので、緊急には使わない（S3）。
/// 赤は使わない（診断ではない・示例なので）。文言は中国語だけ。
library;

import 'health_series.dart' show lastDates;

enum EmergencyKind { fall, heart, lost, impact }

class EmergencySpec {
  const EmergencySpec(this.kind,
      {required this.name, required this.how, required this.what, required this.why, required this.source});

  final EmergencyKind kind;
  final String name;

  /// どう判断するか（1 行）。
  final String how;
  final String what;
  final String why;
  final String source;
}

const List<EmergencySpec> emergencySpecs = <EmergencySpec>[
  EmergencySpec(EmergencyKind.fall,
      name: '倒下・长时间不动',
      how: '活动量突然变成几乎 0，身体的方向突然变（横倒），持续几分钟',
      what: '突然倒下以后一直不动',
      why: '可能是晕倒、中暑或受伤，要马上去看',
      source: 'IMU（加速度和重力的方向）→ 项圈自己判断（T34-G，还在做）'),
  EmergencySpec(EmergencyKind.heart,
      name: '心率异常',
      how: '安静时的心率连续几次比这只狗的平时和安全线高很多（或低很多）',
      what: '安静时心率的大的变化',
      why: '可能是疼痛、发烧或心脏的问题，安全线要请兽医确认',
      source: 'IMU → 自动测量的心率 → 和平时比（T34-G，还在做）'),
  EmergencySpec(EmergencyKind.lost,
      name: '走失・离开安全区',
      how: '项圈和手机断开，并且位置在安全区外面',
      what: '狗离开家（安全区）',
      why: '越早知道越容易找到',
      source: 'GPS ＋ BLE 的连接（T12，还在做）'),
  EmergencySpec(EmergencyKind.impact,
      name: '突然的冲击',
      how: '加速度突然非常大（被撞、摔下来）',
      what: '很大的冲击',
      why: '可能受伤，要看一下狗的样子',
      source: 'IMU（加速度的大小）（还在做）'),
];

EmergencySpec emergencySpec(EmergencyKind k) => emergencySpecs.firstWhere((EmergencySpec s) => s.kind == k);

class EmergencyEvent {
  const EmergencyEvent({required this.date, required this.minuteOfDay, required this.kind, required this.detail,
      required this.outcome, this.demo = true});

  /// その土地の日付（YYYY-MM-DD）。
  final String date;

  /// その日の何分目（0〜1439）。
  final int minuteOfDay;
  final EmergencyKind kind;

  /// 何があったか（1 行）。
  final String detail;

  /// どうなったか（1 行）。
  final String outcome;
  final bool demo;

  String get timeText =>
      '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')}';
}

/// 示例の緊急の記録（[today] までの [days] 日、新しい順）。日付から決まる（同じ日なら同じ）。
/// 1 日・1 項目あたり 1/23 くらい（7 日で 1 件くらい）。
List<EmergencyEvent> demoEmergencyEvents(String today, {int days = 7}) {
  final List<EmergencyEvent> out = <EmergencyEvent>[];
  for (final String d in lastDates(today, days)) {
    for (final EmergencyKind k in EmergencyKind.values) {
      final int h = _hash('$d/emergency/${k.name}');
      if (h % 23 != 0) continue;
      final int minute = (h >> 5) % 1440;
      out.add(EmergencyEvent(
        date: d,
        minuteOfDay: minute,
        kind: k,
        detail: _demoDetail(k, h),
        outcome: _demoOutcome(k, h),
      ));
    }
  }
  out.sort((EmergencyEvent a, EmergencyEvent b) =>
      b.date != a.date ? b.date.compareTo(a.date) : b.minuteOfDay.compareTo(a.minuteOfDay));
  return out;
}

String _demoDetail(EmergencyKind k, int h) => switch (k) {
      EmergencyKind.fall => '突然横倒，${2 + (h >> 11) % 4} 分钟几乎不动',
      EmergencyKind.heart => '安静时心率 ${150 + (h >> 11) % 30} 次/分（平时约 85）',
      EmergencyKind.lost => '离开安全区（家）${100 + (h >> 11) % 400} m',
      EmergencyKind.impact => '很大的冲击（约 ${6 + (h >> 11) % 5} g）',
    };

String _demoOutcome(EmergencyKind k, int h) => switch (k) {
      EmergencyKind.fall => (h >> 15).isEven ? '之后自己站起来了' : '主人确认：在睡觉',
      EmergencyKind.heart => '10 分钟后再测，回到 92 次/分',
      EmergencyKind.lost => '主人确认：在散步',
      EmergencyKind.impact => (h >> 15).isEven ? '之后正常走路' : '主人确认：从沙发上跳下来',
    };

/// FNV-1a（32 bit）。health_series と同じ。
int _hash(String s) {
  int h = 0x811c9dc5;
  for (final int c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

// ───────── 今の安全の状態 ─────────

/// 安全区（今は家だけ。LocationController.defaultHomeFence と同じ）。
const String homeFenceName = '家';
const int homeFenceRadiusM = 150;

/// 首輪の 1 行。[connected] が null なら首輪の様子がわからない（表示しない）。
/// [recording] で [lastReceivedMs] があれば「最后收到数据」。
String collarStatusLine({required bool? connected, required bool recording, int? lastReceivedMs, required int nowMs}) {
  final String c = connected == null ? '' : (connected ? '项圈已连接' : '项圈未连接');
  if (!recording) return c.isEmpty ? '没有在记录' : '$c・没有在记录';
  if (lastReceivedMs == null) return c.isEmpty ? '记录中・还没有收到数据' : '$c・记录中・还没有收到数据';
  final int s = ((nowMs - lastReceivedMs) / 1000).floor();
  final String ago = s < 10 ? '刚刚' : (s < 60 ? '$s 秒前' : '${s ~/ 60} 分钟前');
  return c.isEmpty ? '最后收到数据：$ago' : '$c・最后收到数据：$ago';
}

/// 最後のデータから長くたっている（記録中なのに 60 秒以上来ない）＝注意。
bool dataStale({required bool recording, int? lastReceivedMs, required int nowMs}) =>
    recording && lastReceivedMs != null && nowMs - lastReceivedMs >= 60000;
