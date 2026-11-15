import '../data/daily_summary.dart';

/// 1日まとめの文言(text_key → 文)。T23 のデモでは中国語だけ(D2)。
/// 日本語・英語は T16 で app_strings.dart と同じ形に足す。
/// 知らないキーはキーをそのまま返す(落とさない)。
class SummaryTextZh {
  const SummaryTextZh();

  String title(String categoryId) {
    switch (categoryId) {
      case 'exercise':
        return '运动';
      case 'sleep':
        return '睡眠';
      case 'skin':
        return '皮肤';
      case 'physio':
        return '身体状态';
      default:
        return categoryId;
    }
  }

  final String pageTitle = '每天';
  String dayLabel(int dayNo) => '第 $dayNo 天';
  final String prevDay = '前一天';
  final String nextDay = '后一天';
  String alertsToday(int n) => n == 0 ? '今天没有提醒' : '今天有 $n 个提醒';
  String collecting(int? days) => days == null || days <= 0
      ? '数据收集中，马上开始和平时比较'
      : '数据收集中，还要 $days 天开始和平时比较';
  final String noData = '这天的数据不够（项圈戴的时间太短），不做比较';
  final String unreadable = '这天的数据读不出来';
  final String skinOk = '挠和舔没有特别的变化';
  final String notDiagnosis = '这不是诊断。如果担心，请问兽医。';
  final String trendTitle = '最近 14 天';
  final String trendExercise = '运动（分钟）';
  final String trendSleep = '睡眠（分钟）';
  final String demoNote = '演示：模拟的狗的 14 天数据';
  // T34-A：实际的数据（试用版。文言以后再改）
  final String realNote = '实际数据（试用版：这个手机算出来的结果）';
  final String realMode = '实际';
  final String demoMode = '演示';
  final String reload = '重新读取';
  final String noRealData = '还没有实际的数据。连上项圈，按「开始记录」。';
  final String rawTitle = '试用：这天的原始数字';

  String rawLines(Map<String, double> m) {
    const Map<String, String> names = <String, String>{
      'rest_lie': '休息（趴着）',
      'walk_run': '走・跑',
      'other': '其他动作',
      'lick': '舔',
      'scratch': '挠',
      'shake': '甩',
      'long_still': '很久不动',
    };
    final List<String> out = <String>['戴着的时间：${(m['wear_min'] ?? 0).toStringAsFixed(1)} 分钟'];
    for (final MapEntry<String, String> e in names.entries) {
      final double? v = m[e.key];
      if (v != null && v > 0) out.add('${e.value}：${v.toStringAsFixed(1)} 分钟');
    }
    return out.join('\n');
  }

  String daily(TextItem item) {
    switch (item.textKey) {
      case 'exercise.daily':
        final num? m = item.number('active_min');
        return m == null ? '今天的运动：没有数据' : '今天运动了 ${m.round()} 分钟';
      case 'sleep.daily':
        final num? m = item.number('sleep_min');
        if (m == null) {
          return '昨晚的睡眠：没有数据';
        }
        final int h = m ~/ 60;
        final int mm = (m - h * 60).round();
        final String q = _quality(item.text('quality'));
        return '昨晚睡了 $h 小时 $mm 分钟${q.isEmpty ? '' : '，$q'}';
      case 'physio.daily':
        final num? hr = item.number('rest_hr');
        final num? rr = item.number('rest_rr');
        final List<String> parts = <String>[
          if (hr != null) '安静时心率 ${hr.round()} 次/分',
          if (rr != null) '呼吸 ${rr.round()} 次/分',
        ];
        return parts.isEmpty ? '今天没有测到心率和呼吸' : parts.join('，');
      default:
        return item.textKey;
    }
  }

  String alert(TextItem item) {
    final num? ratio = item.number('ratio');
    switch (item.textKey) {
      case 'exercise.alert.less':
        return ratio == null ? '今天运动比平时少很多' : '今天运动比平时少很多（大约是平时的 ${_pct(ratio)}）';
      case 'sleep.alert.less':
        final String q = _quality(item.text('quality'));
        return '昨晚睡得比平时少${q.isEmpty ? '' : '（$q）'}';
      case 'skin.alert.more':
        final num? n = item.number('count');
        final String c = n == null ? '' : '，挠和舔了 ${n.round()} 次';
        return ratio == null ? '今天挠和舔比平时多很多$c' : '今天挠和舔比平时多很多（平时的 $ratio 倍$c）';
      case 'physio.alert.up':
        final String? metric = item.text('metric');
        if (metric == 'sleep_rr_median') {
          final num? v = item.number('value');
          return '睡觉时呼吸比较快${v == null ? '' : '（${v.round()} 次/分）'}';
        }
        final String what = metric == 'rest_rr_median' ? '安静时呼吸' : '安静时心率';
        return ratio == null ? '$what比平时高' : '$what比平时高（平时的 $ratio 倍）';
      default:
        return item.textKey;
    }
  }

  String _quality(String? q) {
    switch (q) {
      case 'good':
        return '睡得好';
      case 'ok':
        return '睡得一般';
      case 'poor':
        return '睡得不太好';
      default:
        return '';
    }
  }

  String _pct(num ratio) => '${(ratio * 100).round()}%';
}
