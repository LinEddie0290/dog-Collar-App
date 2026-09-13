# YAMNet class map — dog vocalization classes (Step 1, GATE — APPROVED w/ amendments)

## Provenance / what was actually verified

- **File read:** `docs/yamnet_class_map.csv`, from the canonical source shipped
  inside YAMNet:
  `https://raw.githubusercontent.com/tensorflow/models/master/research/audioset/yamnet/yamnet_class_map.csv`
- **Row count verified:** header + **521** classes (index `0`–`520`). ✔
- Both TF Hub `google/yamnet/1` and the TFLite build use this same AudioSet map.
  **Byte-parity of the two model builds' output order/values is verified as the
  FIRST action of Step 2** (per amendment 5) before anything is built on it.

## CRITICAL: YAMNet is multi-label **sigmoid**, not softmax

The 521 scores are independent per-class probabilities in `[0,1]`; they do **not**
sum to 1, and the dog classes are **not mutually exclusive** (a bark frame can
score high on Dog, Bark, Domestic-animals simultaneously). Therefore we split the
dog classes into **two tiers** with different jobs:

### Gate tier — "is this a dog at all?" (parents + umbrella)

| index | mid          | display_name           | role |
|------:|--------------|------------------------|------|
| 67    | `/m/0jbk`    | Animal                 | broadest; cats/livestock too — weak gate |
| 68    | `/m/068hy`   | Domestic animals, pets | parent of Dog **and** Cat — weak gate |
| 69    | `/m/0bt9lr`  | Dog                    | primary gate |
| 117   | `/m/01z5f`   | Canidae, dogs, wolves  | **gate only, never type**; wolf-inclusive |

`gate_score` is derived from this tier (exact combiner chosen in Step 3, e.g.
max of Dog/Canidae with broader parents as fallback). **Whether Canidae(117)
actually improves the gate is quantified in Step 4** (amend. 4) — it is never
allowed into the type tier.

### Type tier — mutually competing event type (the vote)

| index | mid          | display_name    | type label | notes |
|------:|--------------|-----------------|------------|-------|
| 70    | `/m/05tny_`  | Bark            | `bark`     | **Bow-wow (73) merged in here** |
| 73    | `/m/07rc7d9` | Bow-wow         | `bark`     | folded into `bark` (same event) |
| 71    | `/m/07r_k2n` | Yip             | `yip`      | ⚠ few AudioSet clips — see amend. 3 |
| 72    | `/m/07qf0zm` | Howl            | `howl`     | overlaps wolf/coyote/siren/wind |
| 74    | `/m/0ghcn6`  | Growling        | `growling` | acoustically generic |
| 75    | `/t/dd00136` | Whimper (dog)   | `whimper`  | ⚠ few AudioSet clips — see amend. 3 |

**Bow-wow (73) is merged into `bark`** (amend. 1): same acoustic event; keeping
them split would fragment the type vote. So the type tier resolves to **5 labels:
`bark`, `yip`, `howl`, `growling`, `whimper`.**

### Low-support classes to report separately (amend. 3)

**Yip (71)** and **Whimper-dog (75)** have far fewer AudioSet training clips than
Bark. Step 4 will report **per-class precision/recall for these two on their own**
(not averaged into a macro), and state plainly if either is too weak to ship —
this decides whether those product features survive.

## Panting — OUT of scope for v1 (amend. 2)

- **No dog-panting class exists** in YAMNet. ✔
- A general `Pant` class exists — **index 40, `/m/07pyy8b` — HUMAN respiratory**
  (neighbors: Breathing 36, Wheeze 37, Snoring 38, Gasp 39, Pant 40, Snort 41,
  Cough 42).
- **Decision:** `Pant(40)` is **never repurposed for dogs, never surfaced, never
  allowed to influence detection.** Its **raw per-frame score is logged only**
  (to a side channel) for possible later offline analysis. That's the sole use.

## Event JSON schema change (amend. 1)

Separate the two tiers explicitly in every event:

```json
{
  "gate_score": 0.78,
  "type": "bark",
  "type_scores": {"bark": 0.71, "yip": 0.05, "howl": 0.04, "growling": 0.02, "whimper": 0.01},
  "...": "start_s/end_s/duration_s/confidence/n_frames/arousal_proxy/rms_db as before"
}
```

- `gate_score` — from the gate tier ("is this a dog").
- `type_scores` — the 5 competing type-tier labels (bow-wow folded into bark).
- `Pant(40)` raw score is logged to a diagnostic side field, **not** in `type_scores`.

## Two false-friend cautions (carried forward)

1. **Human `Whimper` (21, `/m/07qz6j3`)** is separate from **`Whimper (dog)` (75)** —
   different ontology blocks; never merge.
2. **`Growling` (74)** / **`Howl` (72)** are acoustically generic; usability
   measured in Step 4, reported plainly if too weak.
