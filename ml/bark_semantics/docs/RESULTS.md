# Results — measured detection quality & threshold sweep

Every number here is **measured** on the reduced dev set unless labelled
otherwise. Where something could not be measured, it says so explicitly.

## Environment note
- **Python 3.10.12** was used (the spec asked for 3.11; only 3.10 was available
  on this host). All deps pinned in `requirements.txt` are the exact tested
  versions. TF 2.17.1 / tensorflow_hub 0.16.1, CPU.

## Reduced dev set (per your Step-2 decision)
- **ESC-50** — 2000 clips, **40 "dog"** (positives) + **1960 non-dog**
  (negatives), incl. hard animal negatives (cat, cow, pig, hen, rooster, frog,
  sheep, crow, birds, insects). CC BY-NC 3.0 (dev-only; see DATA_LICENSES.md).
- LibriSpeech / Barkopedia / DogSpeak were **not** pulled — the link made large
  transfers impractical and ESC-50 alone gives a solid dog-vs-not measurement.
  Consequences are called out under **Limitations** and **Amendment 3**.

## Measurement granularity (stated plainly)
ESC-50 clips are 5 s, **single-label**. This is a **clip-level dog-vs-not-dog**
measurement: a clip is a positive detection if `detect` produces **≥1 dog
event**. There are **no per-event timing labels and no vocalization-type
labels** in ESC-50.

## Amendment 5 — model parity (GATE, verified)
`scripts/verify_parity.py` passes:
- Class **order identical** across `yamnet_class_map.csv`, the TF Hub bundled
  map, and the TFLite embedded labels.
- **Value parity** on a real clip (miaow_16k), each build in intended mode:
  top-5 overlap 4/5, best time-aligned frame corr **0.993**, each build's top-1
  within the other's top-3.
- **Finding:** the builds **frame differently** — TF Hub emits a frame every
  0.48 s (overlapping 0.96 s windows); the TFLite "classification" build takes
  one fixed **0.975 s** window per call. Python tuning uses TF Hub framing; a
  TFLite consumer (Flutter) must slide the window itself or thresholds won't map.

## Step 4 — dog-vs-not sweep (measured on ESC-50)

Primary sweep: `gate_combine` × `dog_score_threshold`
(smoothing=3 median, min_event_duration=0.96 s). `dog_only` and
`max_dog_canidae` were **identical at every row**, so they share a column.

| threshold | dog_only / max_dog_canidae |  | | max_all | | |
|--:|--:|--:|--:|--:|--:|--:|
|      | P | R | F1 | P | R | F1 |
| 0.10 | 0.390 | 0.975 | 0.557 | 0.071 | 0.975 | 0.132 |
| 0.20 | 0.557 | 0.975 | 0.709 | 0.082 | 0.975 | 0.152 |
| 0.30 | 0.696 | 0.975 | 0.812 | 0.090 | 0.975 | 0.165 |
| 0.40 | 0.787 | 0.925 | 0.851 | 0.094 | 0.950 | 0.171 |
| 0.50 | 0.841 | 0.925 | **0.881** | 0.098 | 0.950 | 0.178 |
| 0.60 | 0.878 | 0.900 | **0.889** | 0.102 | 0.925 | 0.185 |

Supplementary sweep (`dog_only`) over smoothing × min_event_duration:

| thr | smooth | min_dur | P | R | F1 | fp | fn |
|--:|--:|--:|--:|--:|--:|--:|--:|
| 0.5 | 1 | 0.96 | 0.822 | 0.925 | 0.871 | 8 | 3 |
| 0.5 | 3 | 0.96 | 0.841 | 0.925 | 0.881 | 7 | 3 |
| 0.5 | 5 | 0.96 | 0.919 | 0.850 | 0.883 | 3 | 6 |
| 0.6 | 1 | 0.96 | 0.860 | 0.925 | 0.892 | 6 | 3 |
| 0.6 | 3 | 0.96 | 0.878 | 0.900 | 0.889 | 5 | 4 |
| 0.6 | 3 | 1.44 | 0.969 | 0.775 | 0.861 | 1 | 9 |
| 0.6 | 1 | 1.92 | 1.000 | 0.725 | 0.841 | 0 | 11 |
| 0.6 | 3 | 1.92 | 1.000 | 0.725 | 0.841 | 0 | 11 |

(Full grid in `data/sweep_results.json` and reproducible via `scripts/evaluate.py`.)

## Amendment 4 — does Canidae(117) help the gate? (measured)
**No.** `dog_only` and `max_dog_canidae` are identical at every threshold —
Canidae never exceeds Dog(69) on any decisive clip, so it adds neither recall
nor precision. Adding the broad parents (`max_all`: Animal 67 + Domestic 68) is
**actively harmful** — precision collapses to ~0.09 because cats/cows/pigs trip
those classes. **Decision: gate = Dog(69) only.**

## Chosen default config (justified)
```
gate_combine: dog_only
dog_score_threshold: 0.50
smoothing_window_frames: 3   (median)
min_event_duration_s: 0.96
merge_gap_s: 0.48
```
**Measured at this point:** P=**0.841**, R=**0.925**, F1=**0.881**
(tp 37 / fp 7 / fn 3 / tn 1953 over 2000 clips).
False positives: `brushing_teeth ×2, pig ×2, rooster ×2, crying_baby ×1`.

Why not the F1-max (thr 0.6, F1 0.889)? Deliberately **recall-leaning**: real
phone/far-field audio produces *weaker* YAMNet scores than ESC-50's clean
close-mic clips, so a clean-tuned high threshold would lose field recall. 0.50
keeps recall (0.925) with only 2 more FPs than 0.60. If false alarms prove more
costly than misses in the field, raise to 0.60 (or push min_event_duration to
1.44–1.92 s for near-zero FP at the cost of recall).

## Amendment 3 — Yip & Whimper viability: CANNOT be measured yet
The spec (rightly) wants Yip and Whimper P/R reported **separately**, because it
gates a product feature. **ESC-50 has no vocalization-type labels**, so I cannot
compute a type confusion matrix or Yip/Whimper P/R from it. I will not fabricate
one.

What I *can* report (descriptive, NOT P/R):
- Of the 39 detected ESC-50 dog events, **all 39 typed as `bark`** — expected,
  ESC-50 "dog" is overwhelmingly barking.
- Max raw per-type score seen on *any* ESC-50 dog clip:
  `bark 0.92, growling 0.76, yip 0.52, whimper 0.40, howl 0.38`.
- **Hint (not a conclusion):** whimper and howl never exceed ~0.4 even on real
  dog audio, so they may be hard to trigger — but this needs a type-labelled set
  to confirm. Do **not** treat this as a measurement.

To actually measure Yip/Whimper: pull a **type-labelled** dog set and re-run.
Open question to verify first: whether Barkopedia/DogSpeak even carry
YAMNet-compatible type labels (bark/yip/howl/growl/whimper) vs. breed/context
labels — TBD before committing to that download.

## Limitations
1. **Clean-audio → phone-mic domain gap (the big one).** ESC-50 "dog" is clean,
   close-mic. Real users record across a room on a phone mic: lower SNR, room
   reverb, codec artifacts, distance attenuation. **Every threshold here will
   need re-tuning on real recorded audio.** Expect the operating threshold to
   drop and precision to fall (more environmental false positives). Treat the
   chosen defaults as a *starting point*, not shippable constants.
2. **Single dataset, tiny positive set.** 40 dog clips. Numbers have wide
   confidence intervals; a few clips swing precision/recall by points. No
   LibriSpeech/household-noise negatives were added, so speech- and TV-driven
   false positives are **unmeasured** here.
3. **Clip-level, not event-timing.** Precision/recall are per-5 s-clip, not per
   onset/offset. Event-boundary accuracy (start_s/end_s) is untested against
   ground-truth timings (none exist in ESC-50).
4. **Type tier largely unvalidated.** Only `bark` is exercised by ESC-50;
   yip/howl/growling/whimper have no ground truth here (Amendment 3).
5. **arousal_proxy is a heuristic**, not a model (95th-pct RMS in dB, normalized
   to config anchors). It is labelled as such in code and config; it has not
   been validated against any arousal ground truth (none available).
6. **Python 3.10, not 3.11** as specified.
