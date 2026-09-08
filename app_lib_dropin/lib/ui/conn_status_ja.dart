import 'package:collar_data/collar_data.dart';

/// collar_data の ConnStatus に日本語ラベルを付ける拡張。
/// UI 側だけの都合なので、data 層 (collar_data パッケージ) には置かない。
extension ConnStatusLabel on ConnStatus {
  String get labelJa {
    switch (this) {
      case ConnStatus.disconnected:
        return '未接続';
      case ConnStatus.connecting:
        return '接続中…';
      case ConnStatus.connected:
        return '接続済み';
      case ConnStatus.reconnecting:
        return '再接続中…';
    }
  }
}
