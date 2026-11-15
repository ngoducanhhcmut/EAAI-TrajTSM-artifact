# W7 secondary (post-hoc) analysis — Claude 05/11/2026

Not preregistered. Same frames, plan states, stored oracle labels and unchanged golden as W7_REPORT.md; only the
object ADAPTER differs (see w7_secondary.py docstring). V0 reproduces the primary run: 0 decision mismatches over all plans.

| Variant | Plan | Acceptance | False reject / SAFE | False accept / UNSAFE |
|---|---|---|---|---|
| V0 | H | 37.81% [35.40, 40.19] | 57.89% [55.27, 60.49] (8986/15523) | 0.20% [0.00, 0.53] (2/979) |
| V0 | T | 36.24% [33.80, 38.67] | 57.97% [55.32, 60.63] (8718/15038) | 0.25% [0.00, 0.64] (2/794) |
| V0 | U | 29.57% [26.90, 32.18] | 67.14% [64.33, 70.05] (5858/8725) | 0.60% [0.20, 1.14] (6/992) |
| VA | H | 55.31% [52.54, 58.00] | 38.61% [35.71, 41.54] (5994/15523) | 0.31% [0.00, 0.68] (3/979) |
| VA | T | 51.73% [48.94, 54.54] | 40.02% [37.06, 43.03] (6018/15038) | 0.50% [0.12, 1.01] (4/794) |
| VA | U | 55.88% [52.76, 58.87] | 37.89% [34.72, 41.00] (3306/8725) | 1.11% [0.32, 2.14] (11/992) |
| VB | H | 91.03% [90.11, 91.88] | 3.01% [2.52, 3.52] (467/15523) | 66.60% [59.93, 72.71] (652/979) |
| VB | T | 86.09% [84.50, 87.65] | 3.36% [2.81, 3.95] (505/15038) | 61.08% [53.71, 68.07] (485/794) |
| VB | U | 84.17% [82.30, 86.05] | 10.54% [8.97, 12.19] (920/8725) | 37.70% [30.20, 45.76] (374/992) |

V0 = primary adapter; VA = sound negative-velocity reduction (proof/adapter_lemmas.py);
VB = VA without rear objects (RSS-style responsibility ablation, NOT a collision-freedom claim).
CI: scene bootstrap, 2000 replicates, seed 20261104.

## Notes (Claude 05/11)
- Adapter history: a first VA run (shift-only, no length inflation) was UNSOUND — an oncoming object shifted by
  |v|(L+H) could land behind the ego and its pass-through was then checked as a rear object (H false accepts 74/979).
  Caught by the false-accept audit; lemma `proof/adapter_lemmas.py` N1 now refutes that version. The table above is the
  corrected swept-interval cover (A1–A3 PROVEN). The shift-only numbers are discarded, not reported.
- VA vs V0, H plan: false reject 57.89% -> 38.61%; false accept 2 -> 3 (/979), CIs overlap. Recall on oracle-UNSAFE U:
  1 - 11/992 = 98.89%.
- The 5 false accepts that VA adds over V0 (H scene-0560; T scene-0219, scene-0276; U scene-1067 x4 tokens share one
  culprit pattern, scene-1081) are constant-velocity violations of a NON-negative-velocity culprit (GT deviates
  0.45–2.56 m from constant-v by the collision time; lead braking or follower accelerating), except T scene-0219
  (oracle margin -0.00 m, rear object v = 0: a float boundary case). In V0 these frames were rejected only because some
  OTHER object had v in [-0.01, 0) (annotation noise) — the rejection was accidental, not a safety property.
- Remaining false rejects (38.6%) are dominated by B3 `separation` (rear objects held at constant speed while the ego
  stops + 2 s hold; front objects at constant speed). VB (drop rear objects) shows the rear check costs ~35 points of
  false reject but is required: without it the oracle-UNSAFE acceptance rises to 66.6% (H).
