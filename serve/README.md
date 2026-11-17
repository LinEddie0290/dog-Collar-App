# serve/ — Model A (event layer) + Model B (state layer), server-side

音频全部走 LTE 上云、**服务器端 Python 推理**(不导出手机/不需要 TFLite)。
编码器(CED-tiny)与各头都可替换,接口不依赖服务器特有的东西 —— 不堵后续手机路线。
YAMNet(`aidi_sound/`)**保留**,只继续给语义层 L2 供环境事件(门铃/敲门/人声);
狗叫的事件与类型改由 **Model A** 输出,两者并存、互不覆盖。

## 对外指标(全量,确定性复现)
以这些为准 —— 不要用单 session / 前 60 秒的命中率对外。
| 指标 | 复现 | 报告 |
|---|---|---|
| A presence onset F1(检测) | **0.562** | 0.565 |
| A type/probe7 onset F1(类型) | **0.360** | ~0.34 |
| A shuffled 对照 | 0.038 | 0.04 |
| 嵌入 parity(重算 vs 训练缓存) | 8.7e-5 | <2e-3 ✓ |
| B arousal acc(both, CED+LR) | **0.505** | 0.51(shuffled 0.355) |
| B 声纹 EER(ced_lda, n=30) | **0.267** | 0.27 [0.25,0.29] |

## Model A — 事件层
`model_a.py::ModelA.detect(pcm_int16, sr=16000) -> [event]`
```
{ start_ms, end_ms, class, prob, presence, app_slot }
```
- `class` ∈ type7 的 7 类;`presence` = presence 头在该段均值分;两个头各用各自窗(presence 1s / type 2s,hop 0.25s)。
- **A 在类型上到底能分什么(grouped 5-fold OOF 逐类 F1)**:

  | class | P | R | F1 | n |
  |---|---|---|---|---|
  | breathing | 0.72 | 0.53 | 0.61 | 64 |
  | coughing | 0.84 | 0.76 | 0.80 | 49 |
  | **dog**(所有发声) | 0.76 | 0.80 | 0.78 | 3556 |
  | pant | 0.61 | 0.83 | 0.71 | 3926 |
  | sneezing | 0.44 | 0.44 | 0.44 | 124 |
  | snoring | 0.87 | 0.83 | 0.85 | 82 |
  | others | 0.86 | 0.52 | 0.65 | 4208 |
  | macro(7) | | | **0.69** | |

  主混淆:dog↔pant↔others。**`dog` 是泛类,bark/growl/whine/grunt/moan 一律归到 `dog`,A 不区分它们。**
- `app_slot`:`config.yaml::class_map` **默认空**。因为 type 头不分 bark/growl,把 `dog` 填进 bark 槽会把呻吟/低吼误标成"叫"。
  所以 `dog` 事件以 `app_slot=null` + `class="dog"`(泛发声)输出,由 App 决定怎么显示;只有当某类被真正区分出来时才在 class_map 里加映射。

## Model B — 状态层(喂 App "心理"板块)
`model_b.py::ModelB.step_day(a_events, day, coverage_h) -> daily_state`
```
{ date, wearer_verification, counts_by_type,
  n_bouts{total,z,direction,alarm,status}, arousal{daily_intensity,signal,note,z,...}, sentence }
```
- 定位:**相对这只狗自己的基线有没有变化**,偏健康/福利;**不做情绪翻译、不做诊断**(`monitor/report.py` 有禁词表强制)。
- 历史不足 → `learning`,不报变化;基线锁定(≥14 天、节律 ≥100 串/音色 ≥30)后 → `monitoring`,给 z + higher/lower + CUSUM 报警。
- **`wearer_verification` 字段**:当前 `"disabled"` —— 声纹头默认不启用、近场门未标定,所以**计数里会混进别的狗和电视里的狗叫**。启用需 NearFieldCheck 用项圈真实录音标定(见下)。
- **arousal 注意**:唤醒头在 EmotionalCanines 上训练(acc 0.505),用到项圈/dogplay 是**域外**,会退化到 ~1.0 的先验、几乎没有判别力;只当弱的相对信号,当前数据上未验证。输出里带 `signal:"weak_relative_only"` 和 `note`。
- **时段(几点叫)**:仅当事件时间戳是可信墙钟(项圈 RTC)时才输出。数据集录音没有可信时钟 → `time_of_day_known=False`(默认),**不输出时段描述**。

## CED-tiny 权重:本地固定 + 校验,运行时不触网
机密计算环境:**推理运行时不访问外网**,模型必须固定、可校验。
- `embed.py` **只从本地 `config.ced_model_dir`(默认 `serve/models/ced-tiny`)加载**,`local_files_only=True`,
  **无 HF 回退**;`weights_manifest.json` 固定每个加载文件(权重 + configs + trust_remote_code 的 .py)的 **sha256**,
  启动时校验,**对不上就拒绝启动**。
- **唯一触网的地方是 `fetch_weights.py`(仅 BUILD/CI 用)**:下载 pinned 权重并按 manifest 校验。
- **部署方式(选定:打进镜像)**:git-lfs 本机不可用,故**权重不进 git**,在镜像构建阶段拉取并随镜像走;
  运行时镜像已含固定权重、离线、可校验。Dockerfile 片段:
  ```dockerfile
  COPY serve/ /app/serve/
  # 构建期(有网)拉权重进镜像;运行期(机密计算)离线
  RUN HF_ENDPOINT=https://hf-mirror.com python /app/serve/fetch_weights.py --dest /app/serve/models/ced-tiny
  # 运行期可加 ENV TRANSFORMERS_OFFLINE=1 HF_HUB_OFFLINE=1（embed.py 也已强制）
  ```
  (若将来启用 git-lfs,可改为用 LFS 把 `serve/models/ced-tiny` 跟 serve/ 一起提交,manifest 校验逻辑不变。)
- 重新 pin(仅在有意换模型/版本时):`python fetch_weights.py --dest <trusted_dir> --write-manifest`。

## 产物
- `serve/embed.py`(CED 嵌入,与训练逐位一致,可替换成 ONNX/TFLite 导出)/ `model_a.py` / `model_b.py` / `config.yaml`
- `serve/fetch_weights.py`(build 期拉权重)/ `serve/weights_manifest.json`(sha256 pin)
- `checkpoints/`:`model_a_v2_presence.pkl`、`model_a_type7_W2.pkl`、`model_b_arousal.pkl`、`model_b_wearer_voiceprint.pkl`(纯 numpy,不锁 sklearn)+ `model_a_manifest.json` / `model_b_manifest.json`
- `serve/models/ced-tiny`:权重目录,**不进 git**,构建期由 `fetch_weights.py` 填充

## 多天样例说明
README/交付里出现的"多天 learning→monitoring→alarm"是**注入上升的模拟**(用真实事件池按天采样),
只证明机制能走通,**不是能力测量**。能力以上面的全量 onset F1 为准。

## 待办(明确未做)
- **NearFieldCheck 近场能量门需项圈真实录音标定**(主判据);标定好后与声纹头一起启用佩戴者验证。
- CUSUM 人群尾部池上线再接(`monitor/detect.calibrate` 已支持;现为单狗 demo)。
