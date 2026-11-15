// T36：安全区の判定・模拟の道・位置の管理・記録に GPS が残ること。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collar_app/data/safe_zone.dart';
import 'package:collar_app/data/safety.dart';
import 'package:collar_app/pipeline/imu_input.dart';
import 'package:collar_app/pipeline/pipeline_store.dart';
import 'package:collar_app/state/app_notifier.dart';
import 'package:collar_app/state/collar_link.dart';
import 'package:collar_app/state/location_controller.dart';
import 'package:collar_data/collar_data.dart';
import 'package:collar_geo/collar_geo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const GeoPoint _home = GeoPoint(31.2304, 121.4737);
const SafeZone _zone = SafeZone(center: _home, radiusM: 100);

/// 家から東へ [m] メートルの位置。
LocationFix _at(double m, {int t = 0}) => LocationFix(point: offsetPoint(_home, m, 0), tMs: t);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('出入りの判定（余裕 20 m・外が 2 回続く）', () {
    test('距離の近似：offsetPoint で 200 m 東は 200 m', () {
      expect(_zone.distanceTo(offsetPoint(_home, 200, 0)), closeTo(200, 0.5));
      expect(_zone.distanceTo(offsetPoint(_home, 0, -150)), closeTo(150, 0.5));
    });

    test('中 → 外（2 回続いたら出た）→ 中（戻った）', () {
      final ZoneJudge j = ZoneJudge(zone: _zone);
      expect(j.update(_at(10)), isEmpty);
      expect(j.state, ZoneState.inside);
      // 105 m・115 m は余裕の中（120 m まで）：まだ出ていない
      expect(j.update(_at(105)), isEmpty);
      expect(j.update(_at(115)), isEmpty);
      expect(j.state, ZoneState.inside);
      // 125 m が 1 回だけ：まだ
      expect(j.update(_at(125)), isEmpty);
      // 2 回目：出た
      final List<ZoneEvent> e = j.update(_at(130, t: 5));
      expect(e.map((ZoneEvent x) => x.kind), <ZoneEventKind>[ZoneEventKind.exit]);
      expect(e.single.tMs, 5);
      expect(e.single.distanceM, closeTo(130, 0.5));
      expect(j.state, ZoneState.outside);
      // 90 m は余裕の中（80 m より遠い）：まだ外
      expect(j.update(_at(90)), isEmpty);
      expect(j.state, ZoneState.outside);
      // 70 m：戻った
      expect(j.update(_at(70)).map((ZoneEvent x) => x.kind), <ZoneEventKind>[ZoneEventKind.enter]);
      expect(j.state, ZoneState.inside);
    });

    test('境目のまわりで ±15 m ぶれても、出入りは 0 回', () {
      final ZoneJudge j = ZoneJudge(zone: _zone);
      j.update(_at(50));
      int n = 0;
      for (int i = 0; i < 30; i++) {
        n += j.update(_at(100 + (i.isEven ? 15 : -15))).length;
      }
      expect(n, 0);
      expect(j.state, ZoneState.inside);
    });

    test('最初から外：「出た」は出さずに外にする', () {
      final ZoneJudge j = ZoneJudge(zone: _zone);
      expect(j.update(_at(300)), isEmpty);
      expect(j.update(_at(300)), isEmpty);
      expect(j.state, ZoneState.outside);
    });

    test('外にいるときに BLE が切れたら「可能走失」。中では出ない。つながったら外に戻る', () {
      final ZoneJudge j = ZoneJudge(zone: _zone);
      j.update(_at(10));
      expect(j.setLinked(false, 1), isEmpty); // 家の中で切れた：走失ではない
      expect(j.state, ZoneState.inside);
      expect(j.setLinked(true, 2), isEmpty);

      j.update(_at(200));
      j.update(_at(210, t: 3));
      final List<ZoneEvent> e = j.setLinked(false, 9);
      expect(e.single.kind, ZoneEventKind.lost);
      expect(e.single.tMs, 9);
      expect(e.single.distanceM, closeTo(210, 0.5));
      expect(j.state, ZoneState.lost);
      expect(j.setLinked(false, 10), isEmpty); // 同じ状態をくり返しても出さない
      expect(j.setLinked(true, 11), isEmpty);
      expect(j.state, ZoneState.outside);
    });

    test('切れたまま外に出た（模拟）：出た → 可能走失 の 2 つ', () {
      final ZoneJudge j = ZoneJudge(zone: _zone, linked: false);
      j.update(_at(10));
      j.update(_at(200));
      expect(j.update(_at(200)).map((ZoneEvent x) => x.kind), <ZoneEventKind>[ZoneEventKind.exit, ZoneEventKind.lost]);
    });

    test('家の保存の形：読める・壊れていれば null', () {
      expect(SafeZone.fromJson(jsonDecode(jsonEncode(_zone.toJson())) as Map<String, dynamic>)!.radiusM, 100);
      expect(SafeZone.fromJson(<String, dynamic>{'lat': 1, 'lng': 2}), isNull);
      expect(SafeZone.fromJson(<String, dynamic>{'lat': 1, 'lng': 2, 'radius_m': 0}), isNull);
    });

    test('安全タブの文', () {
      expect(positionLine(state: ZoneState.unknown, distanceM: null, fixMs: null, nowMs: 0, hasZone: false),
          '位置：还没有（GPS 还没定位）');
      expect(positionLine(state: ZoneState.outside, distanceM: 230, fixMs: 0, nowMs: 125000, hasZone: true),
          '位置：在外面，离家 230 m（2 分钟前）');
      expect(positionLine(state: ZoneState.lost, distanceM: 1234, fixMs: 0, nowMs: 1000, hasZone: true),
          '位置：可能走失！最后在离家 1.2 km 的地方（刚才）');
      expect(zoneLine(null), '安全区：还没设（在地图上长按）');
      expect(zoneLine(_zone), '安全区：家（半径 100 m）');
    });
  });

  group('模拟の道', () {
    test('1 周（600 秒）で、出る 1 回・戻る 1 回、いちばん遠くて約 200 m', () {
      final ZoneJudge j = ZoneJudge(zone: const SafeZone(center: _home, radiusM: 100));
      final List<ZoneEventKind> kinds = <ZoneEventKind>[];
      double far = 0;
      for (int s = 0; s < 600; s++) {
        final ({double east, double north}) o = fakeRouteOffset(s.toDouble());
        final LocationFix f = LocationFix(point: offsetPoint(_home, o.east, o.north), tMs: s * 1000);
        far = far > _zone.distanceTo(f.point) ? far : _zone.distanceTo(f.point);
        kinds.addAll(j.update(f).map((ZoneEvent e) => e.kind));
      }
      expect(kinds, <ZoneEventKind>[ZoneEventKind.exit, ZoneEventKind.enter]);
      expect(far, inInclusiveRange(195, 215));
    });

    test('FakeImuInput：模拟の 1 秒に 1 回 GPS。「模拟断开」の間は来ない', () async {
      int now = 1000000;
      final FakeImuInput fake = FakeImuInput(nowMs: () => now, tick: const Duration(hours: 1), home: _home);
      final List<LocationFix> got = <LocationFix>[];
      final StreamSubscription<LocationFix> sub = fake.fixes.listen(got.add);
      await fake.start();
      now += 5000;
      fake.pump();
      await Future<void>.delayed(Duration.zero);
      expect(got.length, 6); // 0〜5 秒
      expect(got.first.tMs, 1000000);
      expect(got[3].tMs - got[2].tMs, 1000);
      expect(got.first.source, 'fake');
      fake.setLinked(false);
      expect(fake.linked, isFalse);
      now += 3000;
      fake.pump();
      await Future<void>.delayed(Duration.zero);
      expect(got.length, 6);
      fake.setLinked(true);
      now += 1000;
      fake.pump();
      await Future<void>.delayed(Duration.zero);
      expect(got.length, 7);
      await fake.stop();
      await sub.cancel();
      fake.dispose();
    });
  });

  test('首輪（BLE）：250 ms のまとめから位置。測位なしは出さず、同じ位置は 1 秒に 1 回', () async {
    final StreamController<RawFrame> frames = StreamController<RawFrame>();
    final List<LocationFix> got = <LocationFix>[];
    final StreamSubscription<LocationFix> sub = fixesFromFrames(frames.stream).listen(got.add);
    void add(int t, Map<String, dynamic> m) => frames.add(RawFrame(t, m));
    add(0, <String, dynamic>{'fix_quality': 0, 'satellites': 0}); // 測位なし
    add(250, <String, dynamic>{'lat': 31.0, 'lng': 121.0, 'fix_quality': 1, 'hdop': 2.0});
    add(500, <String, dynamic>{'lat': 31.0, 'lng': 121.0, 'fix_quality': 1, 'hdop': 2.0}); // 同じ位置・0.25 秒後
    add(1300, <String, dynamic>{'lat': 31.0, 'lng': 121.0, 'fix_quality': 1, 'hdop': 2.0}); // 同じ位置・1 秒以上
    add(1550, <String, dynamic>{'lat': 31.0001, 'lng': 121.0, 'fix_quality': 1, 'hdop': 2.0}); // 動いた
    await frames.close();
    await Future<void>.delayed(Duration.zero);
    expect(got.map((LocationFix f) => f.tMs).toList(), <int>[250, 1300, 1550]);
    expect(got.first.accuracyM, 10); // HDOP 2 × 5 m
    expect(got.first.source, 'collar');
    await sub.cancel();
  });

  group('位置の管理（LocationController）', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('家なし：位置は覚えるが判定しない。家を決めると今の位置から判定、保存して読み直せる', () async {
      final MemoryNotifier n = MemoryNotifier();
      final LocationController lc = LocationController(notifier: n, nowMs: () => 0, tick: null);
      lc.addFix(_at(300));
      expect(lc.latestPosition, isNotNull);
      expect(lc.state, ZoneState.unknown);
      expect(lc.homeFence, isNull);

      await lc.setHome(_home, 150);
      expect(lc.zone!.radiusM, 150);
      expect(lc.distanceM, closeTo(300, 0.5));
      lc.addFix(_at(300));
      expect(lc.state, ZoneState.outside);
      expect(lc.events, isEmpty); // 最初から外は「出た」にしない
      lc.dispose();

      final LocationController again = LocationController(nowMs: () => 0, tick: null);
      await again.loadSaved();
      expect(again.zone!.radiusM, 150);
      expect(again.zone!.center.lat, closeTo(_home.lat, 1e-9));
      again.dispose();
    });

    test('出た → BLE が切れた：可能走失を 1 回通知。戻った：通知。出ただけでは通知しない', () async {
      final MemoryNotifier n = MemoryNotifier();
      int now = 0;
      final LocationController lc = LocationController(notifier: n, nowMs: () => now, tick: null);
      await lc.setHome(_home, 100);
      final StreamController<LocationFix> s = StreamController<LocationFix>();
      lc.attach(s.stream);
      for (final double m in <double>[10, 200, 210]) {
        s.add(_at(m, t: now += 1000));
      }
      await Future<void>.delayed(Duration.zero);
      expect(lc.state, ZoneState.outside);
      expect(lc.lastEvent!.kind, ZoneEventKind.exit);
      expect(n.shown, isEmpty);

      lc.setLinked(false);
      expect(lc.state, ZoneState.lost);
      expect(n.shown.single.title, '可能走失');
      expect(n.shown.single.body, contains('210 m'));

      lc.setLinked(true);
      s.add(_at(20, t: now += 1000));
      await Future<void>.delayed(Duration.zero);
      expect(lc.state, ZoneState.inside);
      expect(n.shown.last.title, '回到了安全区');
      expect(lc.events.map((ZoneEvent e) => e.kind).toList(),
          <ZoneEventKind>[ZoneEventKind.enter, ZoneEventKind.lost, ZoneEventKind.exit]);

      // 安全タブの記録の形（UTC＋8 の日付・時刻、本物の印）
      final List<EmergencyEvent> rows = zoneEmergencyEvents(lc.events, '1970-01-01');
      expect(rows.length, 3);
      expect(rows.every((EmergencyEvent e) => !e.demo && e.kind == EmergencyKind.lost), isTrue);
      expect(rows.first.minuteOfDay, 8 * 60); // 1970-01-01 00:00:04 UTC → 08:00
      expect(rows.map((EmergencyEvent e) => e.id).toSet().length, 3); // key がかぶらない

      lc.detach();
      expect(lc.attached, isFalse);
      expect(lc.latestPosition, isNotNull); // 止めても最後の位置は残す
      await s.close();
      lc.dispose();
    });

    test('古い位置（2 分より前）', () {
      int now = 0;
      final LocationController lc = LocationController(nowMs: () => now, tick: null);
      lc.addFix(_at(0, t: 0));
      now = 119000;
      expect(lc.isOffline, isFalse);
      now = 121000;
      expect(lc.isOffline, isTrue);
      expect(lc.sinceLastFix, const Duration(seconds: 121));
      lc.dispose();
    });
  });

  test('記録ファイル：gps の行が残る', () async {
    final Directory tmp = await Directory.systemTemp.createTemp('gps');
    final PipelineStore store = PipelineStore(baseDir: () async => tmp.path);
    await store.appendGps('s1', LocationFix(point: _home, tMs: 123, accuracyM: 5, source: 'fake'));
    await store.idle();
    final String text = await File('${tmp.path}/pipeline_sessions/s1.jsonl').readAsString();
    final Map<String, dynamic> row = jsonDecode(text.trim()) as Map<String, dynamic>;
    expect(row, <String, dynamic>{'rec': 'gps', 't_ms': 123, 'lat': _home.lat, 'lng': _home.lng, 'acc_m': 5, 'src': 'fake'});
    await tmp.delete(recursive: true);
  });
}
