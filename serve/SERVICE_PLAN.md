# Model A/B 服务通路方案（Task 2）— DRAFT，待确认后再写代码

状态：**方案草案**。按你的决定，buildable 部分我**先写文档，你确认后再实现**；
固件上传格式、App 读接口**只给草案**，分别等骏杰（固件）/学弟（App）确认，不实现。

本文件涉及的 commit 口径：产品代码（worker/持久层）在 **dog-Collar-App**；评测代码
（eval_collar.py）在 **collar-audio**，评测的是本仓 `serve/` 的推理代码。**产品代码禁止 import collar-audio。**

---

## 1. 目标通路（端到端）

```
项圈 --LTE--> collar-ingest(/ingest/audio)  ← 新增音频端点，只收/存/排队，不装模型
                      │ 写 WAV + meta.json 到落地目录 + 入队
                      ▼
            落地目录 landing/<device_id>/<ts>.wav(+.json)     ← 契约边界
                      │
              [推理 worker]（dog-Collar-App，独立进程，消费队列/扫目录）
                      │  A.detect → bark_events(逐事件, 按 dog/device/日 落库)
                      │  每天收尾 → B.step_day → daily_reports(按 dog/device/日 落库)
                      ▼
            SQLite collar_state.db: 表 bark_events / daily_reports   ← 对 App 的契约
                      │
                 App 读接口（collar-ingest 加只读 GET，或 App 直连 DB）  ← DRAFT 待学弟
```

设计原则（沿用 collar-ingest 现状）：**collar-ingest 只收/存/排队，不引入模型依赖**；
推理是独立 worker，崩了不影响摄入；worker 可单独重启、补算历史。

---

## 2. 现状（已查，作为方案前提）
- **collar-ingest 现在没有数据库**：`app/main.py` 把 sensor/label 帧按天 append 成
  `data/YYYY-MM-DD.jsonl`，信封 `{rx_ts, kind, raw}`，**没有音频、没有 device_id/dog_id**。
  → 音频端点、device→dog 映射、两张结果表**都是新增**。
- **Model B 没有跨天持久化**：`monitor/DogMonitor.history` 是进程内 list，退出即丢。
  → 跨天基线必须新建持久层（本方案第 5 节）。
- device→dog 映射现在也不存在 → 需要一张 `devices(device_id → dog_id)` 小表/配置。

---

## 3. 落地目录契约（**现在就能实现**，不等任何人）
worker 先读一个**落地目录**，与"音频怎么来"解耦。collar-ingest 以后往同一目录写，worker 不改。
```
landing/<device_id>/<start_ts_ms>.wav          # 16k mono int16
landing/<device_id>/<start_ts_ms>.json         # 同名 meta（下方 schema）
```
`meta.json`（**这是落地适配器的输入契约**）：
```json
{ "dog_id": "dogA", "device_id": "collar-0001",
  "start_ts": 1731900000000, "sample_rate": 16000, "codec": "pcm_s16le" }
```
- worker 扫 `*.json`（有 `.json` 才算写完，避免读到半个 wav），处理后把文件移到 `landing/_done/`。
- `start_ts` 是**可信墙钟**（项圈 RTC）→ 这是 Model B 能输出"几点叫"的前提（`time_of_day_known=True`）。
  没有可信 RTC 时 meta 里标 `"rtc_trusted": false`，worker 传 `time_of_day_known=False`。

**可实现清单（等你确认）**：落地目录适配器 `serve/worker/landing.py`（扫目录→(wav, meta)迭代器）。

---

## 4. 推理 worker（**现在就能实现**，dog-Collar-App）
`serve/worker/run_worker.py`：
1. `ModelA().detect(pcm)` → 每事件 `{start_ms,end_ms,class,prob,presence,app_slot,_emb}`；
   事件时间 = `meta.start_ts + start_ms`（绝对墙钟）。
2. 写 `bark_events`（按 dog_id/device_id/事件时间）。`_emb` 存二进制 blob，仅供 B 的 arousal/声纹，不出 App。
3. **每日收尾**（该 dog×device 当天的 landing 都处理完，或定时 cron）：
   取当天 `bark_events` → `ModelB.step_day(events, day, coverage_h)` → 写 `daily_reports`。
4. Model B 的历史从 `daily_reports` 载入（第 5 节），实现跨天持久基线。

约束保持不变：`class_map` 默认空（dog 不进 bark 槽）；arousal 维持 `weak_relative_only`；
`wearer_verification` 默认 `disabled`（近场门未标定前计数会混别的狗/电视）；输出无情绪/诊断词
（`monitor/report.py` 禁词表已强制）；权重 sha256 校验不绕过。

---

## 5. 两张表（**= 对 App 的契约**；现在就能建）
SQLite `collar_state.db`（worker 拥有写权限，App/collar-ingest 只读）。

### `bark_events`
| 列 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | |
| dog_id | TEXT | |
| device_id | TEXT | |
| t_start_ms / t_end_ms | INTEGER | 绝对墙钟（epoch ms） |
| cls | TEXT | Model A 的 7 类之一（dog=泛发声） |
| prob / presence | REAL | |
| app_slot | TEXT NULL | class_map 映射结果，默认 NULL |
| wearer_score | REAL NULL | 近场门启用前为 NULL |
| src_file | TEXT | 溯源用 landing 文件 |
| UNIQUE(dog_id, device_id, t_start_ms, cls) | | **幂等**，重算不产生重复 |

### `daily_reports`（键：dog_id, device_id, date）
| 列 | 类型 | 说明 |
|---|---|---|
| dog_id / device_id | TEXT | |
| date | TEXT (YYYY-MM-DD) | |
| wearer_verification | TEXT | `disabled` / `enabled` |
| counts_by_type | TEXT(JSON) | `{"dog":8,"pant":4}` |
| n_bouts_total | INTEGER | |
| n_bouts_status | TEXT | `no_history`/`learning`/`monitoring` |
| n_bouts_z / n_bouts_direction / n_bouts_alarm | REAL/TEXT/INT | monitoring 时才有 |
| arousal_intensity | REAL NULL | |
| arousal_signal | TEXT | 固定 `weak_relative_only` |
| sentence | TEXT | 观察句（无诊断词） |
| PRIMARY KEY(dog_id, device_id, date) | | 重算覆盖，天然跨天累积 |

> `daily_reports` 既是 App 的数据源，也是 Model B 载入历史的来源——B 启动时按
> (dog,device) 读全部历史天 → 重建 `DogMonitor.history` → 冻结基线一旦锁定不再移动。
> learning→monitoring 由**真实天数**驱动（≥14 有效天 + 节律/音色样本量门槛，见 baseline.py），不是注入模拟。

**可实现清单（等你确认）**：`serve/worker/store.py`（建表 + 幂等 upsert + 按 dog×device 读历史）。

---

## 6. 固件上传格式（**DRAFT — 待骏杰确认，不实现**）
建议 collar-ingest 新增 `POST /ingest/audio`（multipart 或 raw + header），字段草案：
```
Authorization: Bearer <device_token>        # 复用现有 token 机制 + device 映射
X-Device-Id / X-Dog-Id / X-Start-Ts / X-Sample-Rate / X-Codec
body: 音频分片（WAV/opus）
```
collar-ingest 落 `landing/<device_id>/<ts>.wav(+.json)` + 入队，**不解码、不跑模型**。
需要骏杰定：分片时长、编码（PCM vs opus）、是否带 device_token→dog 映射、RTC 是否可信。
→ 定了我再写 collar-ingest 的音频端点；在那之前 worker 用第 3 节落地目录即可跑通。

## 7. App 读接口（**DRAFT — 待学弟确认，不实现**）
两选一，等 App 侧定：
- (a) collar-ingest 加只读 `GET /reports?dog_id=&from=&to=` 和 `GET /events?...`，从 `collar_state.db` 读；
- (b) App 侧直接打开 `collar_state.db`（只读）走 `daily_reports`。
无论哪种，**契约就是第 5 节两张表的列**。字段冻结后再加列升版本，不默改。

---

## 8. 端到端测试（**现在就能实现**）
`serve/worker/test_e2e_3days.py`：构造 1 只狗连续 3 天的 landing 目录（真实事件池按天采样），
跑 worker 3 次，断言：
- 第 1 天 `daily_reports.n_bouts_status == "no_history"`；
- 每天 `bark_events` / `daily_reports` 都能从"App 读取位置"（第 5 节表）查到；
- 重跑同一天**不产生重复**（幂等 UNIQUE/PK）；
- 基线历史跨进程重启后仍在（从 DB 重建，不依赖内存）。

---

## 9. 你问的两处评估

### 9a. bundle `monitor/` 与 collar-audio `monitor/`：加一致性测试 vs 改成 import
**查证结果**：两份 `monitor/*.py` **当前逐字节相同**（`diff -r --exclude=__pycache__` 无差异，仅 .pyc 不同）。
**建议：加一致性测试（改动最小）。** 理由：
- bundle 必须**自包含**（机密计算镜像只带 serve/，运行时不依赖 collar-audio）——所以"产品 import collar-audio 的 monitor"会违反"产品代码禁止 import collar-audio"和自包含部署，**不可取**。
- 方案：在 collar-audio 加 `tests/test_monitor_parity.py`，对每个 `monitor/*.py` 比对两份的 sha256，不一致即失败。
  两边改 monitor 必须同步，CI 守住。**改动 = 一个 ~15 行测试文件**，零产品代码改动。

### 9b. 依赖方向 / `pip install -e serve/` 的坑
**坑**：`dog-Collar-App/serve/` **没有打包文件**（无 `setup.py`/`pyproject.toml`），`pip install -e` 现在**装不了**。
eval_collar 当前用 `sys.path.insert(0, bundle)` 导入 `model_a`（已验证可跑），并记录 App commit hash。
**建议**：给 bundle 补一个最小 `serve/pyproject.toml`（package 名如 `collar_serve`，含 `model_a/model_b/embed/monitor`），
这样 `pip install -e dog-Collar-App/serve` 成立，collar-audio 的 venv 单向依赖 App、方向合规；
在补包之前，`sys.path` 注入是等价可用的过渡。CED 权重不在 git → eval_collar 用 `--ced-dir/--ced-manifest`
指到本地 sha256-pinned 权重（已实现），评测的仍是 bundle 的推理代码。

---

## 10. 待你拍板
1. 第 3–5、8 节（落地适配器 / worker / 两张表 / 跨天基线 / 3 天 e2e）——确认后我按本方案实现。
2. 9a 一致性测试、9b 补 `serve/pyproject.toml`——是否一起做。
3. 第 6、7 节保持 DRAFT，等骏杰/学弟；在那之前通路用落地目录跑通。
