# TRANSPORT (upload-format eval) — measure only, model unchanged

30-session dogplay streaming onset F1 per upload format, Δ vs **lossless waveform**.
sessions=30  固定操作点={'th': 0.85, 'r': 0.75, 'm': 3, 'o_on': 0.0934404999999856, 'o_off': -0.2628699999999995}  (log-mel = pre-top_db, server 补 top_db)

| format | presence F1 | Δpres | type7 F1 | Δtype7 | bytes/s | kbps | vs PCM16 |
|---|---|---|---|---|---|---|---|
| lossless_wav | 0.6851 | +0.0 | 0.1529 | +0.0 | 32000 | 256.0 | 1.00x |
| logmel_fp16 | 0.6851 | +0.0 | 0.1587 | +0.0059 | 12800 | 102.4 | 0.40x |
| logmel_int8_frame | 0.6805 | -0.0046 | 0.1646 | +0.0117 | 7200 | 57.6 | 0.23x |
| logmel_int8_seg | 0.6805 | -0.0046 | 0.1597 | +0.0069 | 6408 | 51.3 | 0.20x |
| adpcm_ima | 0.642 | -0.043 | 0.1661 | +0.0133 | 8000 | 64.0 | 0.25x |

注:log-mel float32 无损上传 = 25600 B/s (0.80x PCM16);int8 的 scale 开销已计入。
Δ 以 lossless_wav 为 0 基准。判据沿用决策级(onsetF1 差 <0.01)。
