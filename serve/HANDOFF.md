# HANDOFF — 音频模型(Model A/B)接入 App 进度报告

日期 2026-11-16。范围:把犬声 **Model A(事件层)+ Model B(状态层)** 接进 dog-Collar-App,
**服务器端 Python 推理**(音频走 LTE 上云,不导出手机)。

---

## 1. 结论一句话
A、B 两个模型都在服务器端跑通,报告指标**确定性复现**,真实音频样例已产出,代码作自包含
bundle 提交到 dog-Collar-App 分支 `feature/bark-semantics-pipeline`(待 push)。
剩佩戴者近场门的项圈标定未做(需真实项圈录音)。

## 2. 方向决策(已定)
- **部署形态**:服务器端 Python,不要 TFLite;但编码器/头保持可替换、不堵手机路线。
- **顺序**:先 A(契约跑通)再 B。
- **A = 事件层**:逐事件 `(start_ms,end_ms,class,prob)` + presence;class 用 type 头全集,
  不压成 bark/growl;可配 `class_map` 映射到 App 槽位,映射不到照常输出。
- **B = 状态层**(喂"心理"板块):相对**本狗基线**有无变化,偏健康/福利,**不做情绪翻译、不做诊断**;
  按天出 分类型计数 / 唤醒度 / z + higher-lower;只算佩戴者;历史不足=learning。
- **YAMNet(aidi_sound)保留**,只供 L2 环境事件(门铃/敲门/人声),A 出狗叫,两者并存不覆盖。
- **权重**:机密计算环境,运行时不触网,模型固定可校验。

## 3. 做了什么
- **CED-tiny 嵌入**(embed.py):冻结编码器 [mean,max]→384d,与训练缓存**逐位一致**(parity 8.7e-5)。
- **Model A**(model_a.py):presence 头(1s 窗)检测 bout + type7 头(2s 窗)给 7 类;流式阈值/平滑/合并复用离线逻辑。
- **Model B**(model_b.py):复用已建好的 `monitor/`(aggregate/baseline/CUSUM/禁情绪诊断词 report),
  接 A 事件 + 唤醒头,按天出状态。
- **头重拟合**(从报告的 CED 缓存,纯 numpy 存盘):
  - `model_a_type7_W2.pkl`(7 类 type)、`model_a_v2_presence.pkl`(已有,复用)
  - `model_b_arousal.pkl`(唤醒)、`model_b_wearer_voiceprint.pkl`(声纹,**默认禁用**)
  - 每个头的 manifest:特征维/窗/步/池化/样本数/类别。
- **权重离线化**:embed 只从本地加载 + sha256 校验、对不上拒启动;`fetch_weights.py` 仅 build 期触网;打进镜像。

## 4. 复现指标(确定性,全部吻合报告)
| 指标 | 复现 | 报告 |
|---|---|---|
| A presence onset F1(检测) | **0.562** | 0.565 |
| A type/probe7 onset F1(类型) | **0.360** | ~0.34 |
| A shuffled 对照 | 0.038 | 0.04 |
| 嵌入 parity(重算 vs 训练缓存) | 8.7e-5 | <2e-3 ✓ |
| B arousal acc(both, CED+LR) | **0.505** | 0.51(shuffled 0.355) |
| B 声纹 EER(ced_lda, n=30) | **0.267** | 0.27 [0.25,0.29] |

**type7 逐类 F1(grouped 5-fold OOF)**:breathing 0.61 / coughing 0.80 / **dog 0.78** / pant 0.71 /
sneezing 0.44 / snoring 0.85 / others 0.65,macro **0.69**;主混淆 dog↔pant↔others。
**`dog` 是泛发声类,bark/growl/whine/grunt/moan 不区分。**

## 5. 真实音频样例
**Model A**(dogplay P-01,前 60s,int16 路径):
```
13593-13987ms class=dog  prob0.73 presence0.97 app_slot=null  (GT Grunt)
20343-20987ms class=dog  prob0.63 presence0.99 app_slot=null  (GT Moan)
51343-51987ms class=pant prob0.37 presence0.87 app_slot=null  (GT Growl, dog↔pant 混淆)
57593-59237ms class=dog  prob0.88 presence0.99 app_slot=null  (GT Bark/Grunt/Moan)
```
**Model B**(同 session 一天):
```
{ "date":"2026-11-16", "wearer_verification":"disabled",
  "counts_by_type":{"pant":4,"dog":8},
  "n_bouts":{"total":12,"status":"no_history"},
  "arousal":{"daily_intensity":0.99,"signal":"weak_relative_only","status":"no_history"},
  "sentence":"还在熟悉P-01平时的样子（已记录1天），这段时间只记录、不比较。今天叫了12串。" }
```
多天 learning→monitoring→alarm 的演示是**注入模拟**,只证机制,非能力测量。

## 6. 组会 review 后已修正
1. `class_map` 默认空:`dog` 不再映射到 bark(避免把呻吟/低吼误标成"叫");补了逐类 F1。
2. 对外只用全量 onset F1,不用单 session 命中率。
3. B 三处:arousal=0.99 诊断为**域外退化到先验**(非 bug),标 `weak_relative_only`;
   无可信墙钟**不输出时段**;加 `wearer_verification:"disabled"` 字段并写明计数会混进别的狗/电视。
4. 声纹头复现+存盘(EER 0.267),**默认禁用**。

## 7. 产物与提交
- 代码:`collar-audio/serve/`(embed/model_a/model_b/config/fetch_weights/weights_manifest + `monitor/` + `checkpoints/`)
- 提交到 dog-Collar-App 分支 `feature/bark-semantics-pipeline`:
  - `e28c8a0` serve: Model A + Model B 服务器端
  - `087d3db` serve: CED 权重本地固定 + sha256 校验,运行时不触网
  - (更早 `1906291` aidi_sound = YAMNet 环境事件,保留)
- push:`git push origin feature/bark-semantics-pipeline`(你自己 push)

## 8. 待办 / 下一步
- **NearFieldCheck 近场能量门需项圈真实录音标定**(佩戴者验证主判据);标定好后与声纹头一起启用,
  届时 `wearer_verification` 才能从 `disabled` 打开。
- **arousal 在 collar 域未验证**(训练域是 EmotionalCanines);有项圈/本域标注数据再评。
- CUSUM **人群尾部池**上线再接(`monitor/detect.calibrate` 已支持,现 demo 为单狗)。
- 镜像构建把 `fetch_weights.py` 固化成一步(有网层);运行层离线。
- type 细分(bark vs growl)目前没有可用头,若产品要分,需型标注数据训练新头。

## 9. 怎么跑(自测)
```bash
export TRANSFORMERS_OFFLINE=1 HF_HUB_OFFLINE=1
# 先把权重放到 serve/models/ced-tiny(build 期):
HF_ENDPOINT=https://hf-mirror.com python serve/fetch_weights.py --dest serve/models/ced-tiny
python -c "import sys; sys.path.insert(0,'serve'); from model_a import ModelA; ..."
```
环境:`/NVme2/aidi/collar-audio/.venv-gpu/bin/python3`(TF2.17 / torch2.4.1 / transformers4.44.2 / sklearn1.5.1)。
