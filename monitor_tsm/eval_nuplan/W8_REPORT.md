# W8 — nuPlan mini, closed loop, reactive IDM agents (Claude 05/11/2026)

Scenarios common to all conditions: 63 (paired); per condition: {'none_raw': 64, 'none_tsmx': 64, 'blind_raw': 64, 'blind_tsmx': 63, 'stale_raw': 64, 'stale_tsmx': 64, 'stale_tsmxc': 64}; MISSING conditions: []. CI: scenario bootstrap 2000, seed 20261105.

| Condition | n | At-fault collision rate | TTC compliance | Progress | nuPlan score | MRM entries / scen. | MRM before fault | uncertified MRM |
|---|---|---|---|---|---|---|---|---|
| none_raw | 63 | 7.9% [1.6, 14.3] | 0.825 | 0.864 | 0.850 [0.779, 0.912] | 0.00 | 0 | 0 |
| none_tsmx | 63 | 6.3% [1.6, 12.7] | 0.857 | 0.803 | 0.795 [0.714, 0.870] | 4.51 | 284 | 9 |
| blind_raw | 63 | 49.2% [36.5, 61.9] | 0.460 | 0.908 | 0.477 [0.363, 0.590] | 0.00 | 0 | 0 |
| blind_tsmx | 63 | 23.8% [14.3, 34.9] | 0.492 | 0.810 | 0.582 [0.489, 0.674] | 10.13 | 29 | 9 |
| stale_raw | 63 | 20.6% [11.1, 30.2] | 0.698 | 0.800 | 0.652 [0.544, 0.749] | 0.00 | 0 | 0 |
| stale_tsmx | 63 | 14.3% [6.3, 22.2] | 0.794 | 0.716 | 0.593 [0.480, 0.700] | 5.59 | 29 | 9 |
| stale_tsmxc | 63 | 0.0% [0.0, 0.0] | 0.921 | 0.546 | 0.621 [0.513, 0.720] | 66.08 | 29 | 770 |

| Condition | MRM steps / scen. (0.1 s) | out-of-ODD step fraction |
|---|---|---|
| none_raw | 0.0 | 0.000 |
| none_tsmx | 17.2 | 0.092 |
| blind_raw | 0.0 | 0.000 |
| blind_tsmx | 37.0 | 0.095 |
| stale_raw | 0.0 | 0.000 |
| stale_tsmx | 23.9 | 0.214 |
| stale_tsmxc | 114.1 | 0.617 |

Paired (same scenario) collision changes raw -> tsmx:
- none raw->tsmx: avoided 2, introduced 1 ['0467e9cf8b7159f5'], both 3
- blind raw->tsmx: avoided 16, introduced 0 [], both 15
- stale raw->tsmx: avoided 4, introduced 0 [], both 9
- stale raw->tsmxc: avoided 13, introduced 0 [], both 0
- stale tsmx->tsmxc: avoided 9, introduced 0 [], both 0

TSM-X soundness is claimed for its 1D constant-velocity world model only; reactive agents, cut-ins and lateral
motion are outside it, so nuPlan collisions are an empirical measurement, not a verified property.
