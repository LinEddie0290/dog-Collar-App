# 集成说明 — 数据层怎么接进 Flutter App

## 现在仓库里有什么

```
packages/collar_data/    ← 数据层(纯 Dart,已完成并测过):连 WiFi/WebSocket、
                            原始帧落盘、滤波降噪、断线重连。零 Flutter 依赖、零外部依赖。
```

Flutter 工程还没建。下一步由 UI 侧同学建。

## 建 Flutter 工程(UI 侧,在 MacBook 上)

在仓库根目录:

```bash
flutter create .          # 在当前目录生成 App(不会动 packages/ 和本文件)
```

然后在生成的 `pubspec.yaml` 里加上对数据层的 path 依赖:

```yaml
dependencies:
  collar_data:
    path: packages/collar_data
```

`flutter pub get` 一下即可。

## 怎么用(UI 侧只碰这几样)

```dart
import 'package:collar_data/collar_data.dart';
import 'package:path_provider/path_provider.dart';  // App 的依赖,数据层不含

final dir = await getApplicationDocumentsDirectory();
final repo = CollarRepository(
  source: FakeCollarDataSource(),      // 开发期:假数据,不用硬件
  archive: RawArchive(dir.path),       // 原始帧落盘目录
);
await repo.start();

// 实时数据画图
repo.cleanStream.listen((SensorSample s) {
  // s.hr / s.resp / s.ax ... 都是 double?(null = 本帧无读数,画断点别当 0)
});

// 连接状态
repo.status.listen((ConnStatus st) { /* 已连接 / 重连中 / 离线 */ });

// 图表初始化用最近若干条
final warmup = repo.recent;
```

真机联调时,只把 `source` 换成:

```dart
source: WebSocketCollarDataSource('ws://<项圈IP>:<端口>'),
```

**下游一行都不用改。**

## 约定

- **只做手机端,别编译 Web 版**(数据层用 `dart:io`,Web 不支持)。
- **`SensorSample` 是两人接口**,数据侧改字段会提前通知。
- 数据层细节见 `packages/collar_data/README.md`;可独立自测:
  `cd packages/collar_data && dart run bin/demo.dart`。
