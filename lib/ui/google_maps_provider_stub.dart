import 'package:collar_geo/collar_geo.dart';
import 'package:flutter/widgets.dart';

import 'map_provider.dart';

/// 海外版 Provider の置き場所(未実装)。
///
/// この時点でこのファイルが動くことは想定していない――[MapProvider] という
/// 抽象が本当に差し替え可能であることを示すためのもの。海外市場向けに
/// 本当に必要になったら、`google_maps_flutter` パッケージを使って
/// [AmapMapProvider] と同じ形の実装を書けばよい。座標変換は不要
/// (Google Maps はそのまま WGS84 を使える)。
///
/// MapPage 側やその他のロジックは一切変更不要。
class GoogleMapsProviderStub implements MapProvider {
  const GoogleMapsProviderStub();

  @override
  String get name => 'google-maps';

  @override
  Widget buildMapView({
    required GeoPoint initialCenter,
    GeoPoint? dogPosition,
    bool dogPositionIsStale = false,
    GeofenceConfig? fence,
  }) {
    throw UnimplementedError(
      'GoogleMapsProviderStub は未実装です。AmapMapProvider と同じ形で '
      'google_maps_flutter を使って実装してください。座標はそのまま WGS84 '
      'を使えます(変換不要)。',
    );
  }
}
