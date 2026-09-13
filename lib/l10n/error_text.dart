import 'app_strings.dart';

/// 状態クラスが持つ「原因コード」を、表示言語の文章に変える。
///
/// `CollarLink` と `VitalsSession` は `errorMessage` に日本語の文章ではなく
/// `bt_off` のようなコードを入れる。文章をそこで作ってしまうと3言語に
/// できないため、表示の直前にここで選ぶ。
///
/// 追加情報が必要なコードは `code|詳細` の形にしてある。
String? errorText(AppStrings s, String? code) {
  if (code == null || code.isEmpty) return null;

  final int bar = code.indexOf('|');
  final String head = bar < 0 ? code : code.substring(0, bar);
  final String detail = bar < 0 ? '' : code.substring(bar + 1);

  switch (head) {
    case 'bt_off':
      return s.errBtOff;
    case 'bt_denied':
      return s.errBtDenied;
    case 'not_found':
      return s.errNotFound;
    case 'wrong_device':
      return s.errWrongDevice;
    case 'old_firmware':
      return s.errOldFirmware;
    case 'busy':
      return s.errBusy;
    case 'connect_failed':
      return s.errConnectFailed;
    case 'link_lost':
      return s.errLinkLost;
    case 'too_short':
      return '${s.errTooShortPrefix}$detail${s.errTooShortSuffix}';
    case 'save_failed':
      return '${s.errSaveFailed}: $detail';
  }
  // 想定外のコードは隠さずそのまま出す。黙って消えるより気づける。
  return code;
}
