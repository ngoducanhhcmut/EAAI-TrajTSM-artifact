# AMENDMENT A7 - 2026-11-05T08:36:23+07:00: offline state-estimation clarification

PROTOCOL.md's execution-assumption sentence saying that T uses only data available at t0 is too strong. The supplied build_tokens_for_sample calls nusc.box_velocity; the supplied NuScenesLite implementation estimates object velocity using prev/next annotation positions when both exist. Thus the annotation token is at t0, but its offline velocity estimate can use the next keyframe. The TSM-X object adapter also uses prev/next differences. Ego central differences already explicitly require the next keyframe in the requested protocol.

T receives no GT waypoint target and has no GT-waypoint proxy substitution. Nevertheless this experiment is an offline, annotation-based open-loop evaluation and does NOT establish causal online model performance. This correction was identified during provenance review while the full run was in progress.

No input, weight, checkpoint adaptation, ODD threshold, object filtering, label, decision, metric, seed, or frame selection changes. The computation has used the same supplied loader throughout. The preregistered PROTOCOL.md and its recorded hash remain unchanged; this separately timestamped clarification preserves that registration and is linked from the final report. It documents the existing estimator lookahead rather than retroactively describing it as causal.
