/// T35 健康タブ：平時との比べ方の文など（中国語だけ）。
library;

import '../../data/health_series.dart';

/// 「高い／低い」で言う項目（それ以外は「多い／少ない」）。
const Set<String> _highLow = <String>{'rest_hr', 'rr', 'sleep_rr', 'temp', 'limp'};

/// 平時との比べ方の一言。値がない・波形の項目は空。
String diffText(ItemSeries s) {
  if (s.spec.link || s.today == null) return '';
  if (s.spec.bandAbs != null) return absDiffText(s);
  final int? p = s.diffPct;
  if (p == null) return '数据收集中，还不能和平时比';
  if (p.abs() <= bandPct) return '和平时差不多';
  final bool hl = _highLow.contains(s.item.id);
  return p > 0 ? '比平时${hl ? '高' : '多'} $p%' : '比平时${hl ? '低' : '少'} ${-p}%';
}

/// T11：±値の帯の項目（体温）。「平时 +0.4℃」。平時がまだなら「还要 N 天」。
String absDiffText(ItemSeries s) {
  final double? d = s.diffAbs;
  if (d == null) {
    final int need = (s.spec.minUsualDays ?? minUsualDays) - s.usualDaysHave;
    return '平时还在收集（还要 ${need < 1 ? 1 : need} 天）';
  }
  final String v = '${d >= 0 ? '+' : '−'}${d.abs().toStringAsFixed(1)}${s.spec.unit}';
  if (s.inBand ?? true) return '和平时差不多（$v）';
  return d > 0 ? '比平时高（$v）' : '比平时低（$v）';
}

/// 11/05 の形。
String shortDate(String ymd) => '${ymd.substring(5, 7)}/${ymd.substring(8, 10)}';
