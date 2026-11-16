// Q28：测定タブの「测量要点」は首輪向け（胸に当てていた頃の文は残さない）。
import 'package:collar_app/l10n/app_language.dart';
import 'package:collar_app/l10n/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('测量要点：中文は首輪の付け方・落ち着いてから測る（T39 の手順書と同じ言い方）', () {
    final AppStrings zh = AppStrings.forLanguage(AppLanguage.zh);
    expect(zh.tipsTitle, '测量要点');
    expect(<String>[zh.tipSensorPlacement, zh.tipWaitCalm, zh.tipStayStill, zh.tipKeepPhoneClose], <String>[
      '项圈戴好：传感器在喉咙下面，松紧能放进 2 根手指',
      '等狗安静地趴着或坐着再测，不要在走动时测',
      '尽量保持不动 60 秒',
      '手机放在项圈附近',
    ]);
  });

  test('どの言語にも「胸」の文が残っていない', () {
    for (final AppLanguage l in AppLanguage.values) {
      final AppStrings s = AppStrings.forLanguage(l);
      for (final String t in <String>[s.tipSensorPlacement, s.tipWaitCalm]) {
        expect(t, isNot(anyOf(contains('胸'), contains('chest'))), reason: '${l.name}: $t');
      }
    }
  });
}
