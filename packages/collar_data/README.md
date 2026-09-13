# collar_data — 手机 App 的数据层(纯 Dart)

宠物项圈 App 里"接数据 / 缓存 / 滤波降噪"的那一层。**零 UI 依赖、不 import 任何
flutter/material、零外部依赖**——一个自包含目录,可以当独立包,也可以整个文件夹
拖进 Flutter 工程。用一个 bare `dart` SDK 就能跑和测,不用手机、不用等真硬件。

## 数据流

```
项圈 ─WiFi/WebSocket─> [CollarDataSource]
                          │  原始帧 RawFrame(附手机接收时间 rxTs)
                          ▼
                   [RawArchive]  ← 先把原始帧原样写盘(JSONL),再滤波
                          │
                          ▼
                   parse → [SampleFilter] 滤波降噪
                          │
                          ▼
              CollarRepository.cleanStream  ← UI 只订阅这个
```

**顺序是刻意的:原始帧先落盘,再解析、再滤波。** 滤波逻辑就算写错,原始数据也永远
在磁盘上可复原——和服务端"永不丢、永不改写"一个原则。

## 目录

```
lib/
  collar_data.dart                  对外总导出(UI 只 import 这一个)
  src/
    sensor_sample.dart              SensorSample 数据模型(你和 UI 的契约)
    raw_frame.dart                  RawFrame 原始帧 + 手机接收时间
    conn_status.dart                连接状态枚举
    collar_data_source.dart         数据源接口(抽象)
    fake_collar_data_source.dart    ★ 假数据源(优先交付,解学弟阻塞)
    websocket_collar_data_source.dart  真实 WiFi/WebSocket 实现
    raw_archive.dart                原始帧落盘(JSONL,按日分文件)
    filters.dart                    中值 + EMA 滤波
    collar_repository.dart          串起全链路,对 UI 暴露 cleanStream/status/recent
bin/
  demo.dart                         自带断言的自测(dart run 直接跑)
```

## 现在就跑(不用手机)

```bash
cd collar_data
dart run bin/demo.dart
```

它对着**假项圈**跑 6 秒,并断言:原始帧全部落盘、可空 HR 路径被走到、滤波确实降低
了抖动、模拟断线产生了 reconnecting→connected。全绿就说明这层逻辑是通的。

## UI 层(学弟)怎么用 —— 这就是你俩的契约

学弟**只碰 CollarRepository**,不碰 socket、不碰 JSON、不碰文件:

```dart
import 'package:collar_data/collar_data.dart';

// 开发期:用假数据源,今天就能写界面
final repo = CollarRepository(
  source: FakeCollarDataSource(),
  archive: RawArchive(docsDirPath),   // 见下方"落盘目录"
);
await repo.start();

repo.cleanStream.listen((SensorSample s) {
  // s.bodyTempC / s.ax... 都是 double?(可能为 null=本帧无读数)
  // 画图 / 显示
});
repo.status.listen((ConnStatus st) {
  // 显示"已连接 / 重连中 / 离线"
});
final warmup = repo.recent;           // 最近若干条,初始化图表
```

真机联调时,只把 `source` 换成:

```dart
source: WebSocketCollarDataSource('ws://<项圈IP>:81'),
```

**下游一行都不用改**——这就是接口隔离的意义。

## 落盘目录(唯一需要 Flutter 侧传入的东西)

`RawArchive` 只要一个目录路径字符串,所以它本身不 import Flutter。在 App 里由 UI/
启动代码提供真实目录(用 `path_provider`):

```dart
// 只有这一步在 Flutter App 层,数据层本身与 Flutter 无关
import 'package:path_provider/path_provider.dart';
final dir = await getApplicationDocumentsDirectory();
final repo = CollarRepository(
  source: FakeCollarDataSource(),
  archive: RawArchive(dir.path),
);
```

测试 / `dart run` 时传临时目录即可(demo 就是这么做的)。

## 关于可空字段(hr / resp / imu 都是 `double?`)

一帧**不保证带所有字段**:项圈可能交错发不同帧类型(高频 IMU 帧不含心率)、光学心率
经常抓不到读数(项圈松动/运动)、电量只是偶尔上报。如果把"没读到"填成 `0.0`,图表会
画出一个假的掉零、滤波器还会把它当真值。**用 `null` 让"无读数"显式且诚实**:滤波器
跳过它、UI 画成断点,而不是编一个点出来。missing 就是 missing。

## 滤波(先用默认,见到真数据再调)

| 信号 | 处理 | 说明 |
|------|------|------|
| hr / resp | 中值(窗口5)去毛刺 → EMA(α=0.2)平滑 | 生理信号变化慢 |
| IMU ax/ay/az | EMA 低通(α=0.3) | 去高频抖动 |
| battery | 不处理 | 本来就慢 |

参数都在 `SampleFilter(...)` 构造函数里可调。null 输入→null 输出,不臆造、不前向填充,
滤波状态保留,数据恢复后平滑接续。想换卡尔曼之类的,只改 `filters.dart`,别处不动。

## 为什么不用 web_socket_channel

真实 WS 用的是 dart:io 自带的 `WebSocket`——**零外部依赖**,Android/iOS/桌面都能跑,
也让这个包无需联网 `pub get` 就能 `dart run`。以后要支持 Flutter Web 再换
`package:web_socket_channel`,`WebSocketCollarDataSource` 内部一换即可,接口不变。
```

## GPS 字段（`lat` / `lng` / `fixQuality` / `satellites` / `hdop`）

⚠️ **2026-09-12：这一节已按真实固件改写，详见根目录 `PROTOCOL_CHANGE.md`。**

之前这里假设固件发 `lat` / `lng` / `gps_accuracy_m` 三个 JSON 字段，并标注了
"请确认字段名"。确认结果是：**固件根本不发 JSON**。设备是 BLE 专用的
nRF54LM20A，GPS 数据以**原始 NMEA 语句**的形式发过来，由 App 自己解析
（见 `pet_sample.dart` 和 `../collar_geo/lib/src/nmea.dart`）。

所以字段改成了：`lat` / `lng`（WGS84，度）、`fixQuality`（GGA 定位质量，
0 = 未定位）、`satellites`（参与解算的卫星数）、`hdop`（水平精度因子）。
**`gpsAccuracyM` 已删除——固件不提供任何以米为单位的精度值。** HDOP 是无量纲
的倍数，不是距离；`estimatedAccuracyM`（`HDOP × 5m`）只是画圈用的粗略估算，
UI 上必须标明是估算值。

最关键的一点：**收到格式正确的 NMEA 不等于已经定位。** 2026-09-11 的台面
测试收到 1,200 条合法语句，其中 GGA 全部是 fix quality 0、0 颗卫星，RMC 全部
是状态 V——因为在室内。所以 `hasLocation` 除了检查坐标存在，还检查
`fixQuality >= 1`。放宽这里就会出现"没定位但地图上有狗"。

`FakeCollarDataSource` 仍然按 `gpsFixEvery`（默认每 10 帧一次）在原点附近做
小范围随机游走，方便没有硬件时开发地图/围栏功能。注意假数据源走的是 JSON
路径，真机走的是 BLE 二进制路径，两者共用同一套 JSON 键名，所以真机的存档
可以直接喂回假数据路径重放。

坐标转换（WGS84 -> 高德要的 GCJ-02）、围栏进出判断不属于这一层的职责，见
`../collar_geo`。
