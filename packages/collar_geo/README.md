# collar_geo — 定位相关的纯逻辑（纯 Dart）

和 `../collar_data` 同样的思路：**零 UI 依赖、不 import 任何 flutter/material、
零外部依赖**。放的是"判断狗狗在不在家""把坐标画到国内地图上要先转换"这类
和硬件、和界面都无关的纯数学/纯逻辑代码，方便独立测试，也方便以后复用到
除了这个 App 以外的地方（比如服务器端也可能需要同样的围栏判断）。

## 为什么单独拆一个包，而不是加进 collar_data

`collar_data` 的职责是"接收并整理项圈传来的数据"，`collar_geo` 的职责是
"对坐标做数学计算"——两者关注点不同，且 `collar_geo` 以后很可能被服务器端
或者别的客户端复用（比如"判断是否在围栏内"这个逻辑，服务器做地理围栏推送
时也要用一份一样的实现）。拆开更清楚，也不用让 `collar_data` 承担和硬件
通信无关的职责。

## 目录

```
lib/
  collar_geo.dart          对外总导出
  src/
    lat_lng.dart            GeoPoint：WGS84 坐标类型
    gcj02.dart               WGS84 <-> GCJ-02 坐标转换（画到高德地图前必做）
    geofence.dart            距离计算、GeofenceTracker（进/离开围栏判断）
    circle_polygon.dart      把圆形围栏近似成多边形顶点，方便画在地图上
bin/
  demo.dart                 自带断言的自测（dart run 直接跑，同 collar_data 的风格）
```

## 现在就跑（不用手机，不用 Flutter）

```bash
cd packages/collar_geo
dart run bin/demo.dart
```

## ⚠️ 必读：为什么有专门的坐标转换文件

项圈硬件的 GPS 芯片输出的是国际标准 **WGS84**。中国大陆的地图（高德/百度/
腾讯）出于测绘法规要求，不能直接显示 WGS84 坐标，必须先加偏转换成
**GCJ-02**。不转换的后果：地图上的狗狗位置会偏移 **200~700 米**，而且不会
报错，只是"看起来有点不准"——非常容易在测试阶段被忽略。

**规则：只在"即将渲染到高德地图"这一步调用 `wgs84ToGcj02`。** 围栏判断、
数据存储、距离计算、UI 之外的业务逻辑一律只用 WGS84。

## 关于 circleToPolygon

地图 SDK（`amap_map`）不同版本对 Circle 覆盖物的支持不完全确定，所以围栏圈
默认用多边形近似（64边形，肉眼看不出棱角）来画，而不是依赖 Circle 类。如果
确认了当前锁定的 `amap_map` 版本支持原生 Circle，可以换成原生实现，
`circleToPolygon` 可以继续留着当 fallback。

## 单位与坐标约定

- 所有距离单位：米
- 所有坐标：`GeoPoint(lat, lng)`，纬度在前、经度在后
- 除 `gcj02.dart` 里两个转换函数外，全包统一使用 WGS84
