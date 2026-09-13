# Dataset & model licenses

**Scope of use in this project:** every dataset below is used **only locally, to
measure detection metrics and tune a handful of scalar threshold constants** in
`config.yaml`. We do **not** train, fine-tune, or distill any weights (hard
project constraint), and we do **not** redistribute any dataset. The only ML
artifact that ships in the product is YAMNet itself.

> ⚠️ I am not a lawyer. The commercial-use notes below are an engineering
> risk assessment, not legal advice. Get counsel to confirm before shipping.

## The one that ships: YAMNet

| Artifact | License | Commercial use |
|---|---|---|
| YAMNet (TF Hub `google/yamnet/1`, TFLite build, `yamnet_class_map.csv`) | **Apache-2.0** | ✅ Yes. This is the only model we ship. |

Because the shipped detector is stock YAMNet (Apache-2.0) plus our own rule code,
**no dataset below ends up inside the product.**

## Dev datasets (local eval/tuning only, never shipped)

| Dataset | Purpose | License | Commercial use of the *data* | Blocks commercial use of *our code*? |
|---|---|---|---|---|
| **ESC-50** | dog positives + ~49 negative classes | **CC BY-NC 3.0** | ❌ non-commercial | **No** — see analysis |
| **LibriSpeech** | speech negatives | **CC BY 4.0** | ✅ with attribution | No |
| **ArlingtonCL2/DogSpeak_Dataset** | dog-sound variety | **CC BY-NC-SA 4.0** | ❌ non-commercial + ShareAlike | **No** — see analysis (SA caveat) |
| **ArlingtonCL2/Barkopedia_\*** | dog-sound variety | ⚠️ **VERIFY on HF dataset card** | unknown until verified | unknown until verified |
| Household/TV noise | negatives | ⚠️ **source not yet fixed** | depends on source | depends on source |

### Items I still must verify (not guessed here)
- **Barkopedia_\*** — license not stated in the task; I will read each HF dataset
  card and record the exact license + any usage terms before using it. If any is
  NC/unstated, it stays dev-only like the others.
- **Household/TV noise source** — I will pick a specific corpus (candidates:
  ESC-50's own non-dog classes, MUSAN, DEMAND, FSD50K) and record its exact
  license here once chosen. Nothing gets used until its license is logged.

## Does anything block commercial use of the *resulting code*?

**Assessment: No — provided all three hold.** The NC / NC-SA restrictions
(ESC-50, DogSpeak) attach to *the data and to derivative works of the data*
(e.g. trained weights, redistributed copies). Our resulting code:

1. **Ships no dataset content** — `detect.py`/`rules.py` contain no audio and no
   samples from any dataset.
2. **Ships no weights derived from the data** — hard "no training" constraint;
   the shipped model is Apache-2.0 YAMNet.
3. **Only outputs a few scalar threshold constants** informed by measured
   metrics — numbers, not the datasets' copyrighted expression.

Under that usage, the tuned constants are very unlikely to be a "derivative
work"/"adaptation" of the datasets, so **NonCommercial and ShareAlike do not
propagate to our code.**

### Caveats worth surfacing to counsel
- **ShareAlike (DogSpeak, CC BY-NC-SA 4.0):** SA only bites if our output is
  deemed an *adaptation* of that data. Tuning scalar thresholds almost certainly
  is not — but if anyone ever bakes DogSpeak audio/features into a shipped
  artifact, SA + NC would then apply. Keep it dev-only.
- **NonCommercial (ESC-50, DogSpeak):** fine for our internal tuning; do **not**
  redistribute these datasets or ship anything containing them.
- **Attribution (LibriSpeech CC BY 4.0):** trivial to satisfy; not a blocker.
- If commercial-use certainty is required, the clean path is to **re-tune the
  final shipping thresholds on our own recorded/commercially-licensed audio**
  (which we need anyway for the phone-mic domain gap — see RESULTS Limitations).
