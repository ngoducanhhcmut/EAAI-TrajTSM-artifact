#!/usr/bin/env bash
# Eight shard runners in parallel; <=3151 jobs/invocation for existing obj_2.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$here/../../tb/integ"
binary=./obj_2/Vtb_m_tsmx_top
test -x "$binary"
test -s "$here/rtl_batches_lf.tsv"
logdir=vl_claude_r17_a8_apos
mkdir -p "$logdir"
pids=()
for k in {0..7}; do
  (
    logfile="$logdir/w10a_shard_${k}.txt"
    rm -f -- "$logfile.done"
    : > "$logfile"
    while IFS=$'\t' read -r shard batch start count file; do
      [[ "$shard" == "$k" ]] || continue
      printf 'W10A_BATCH shard=%s batch=%s start=%s count=%s\n' "$shard" "$batch" "$start" "$count" >> "$logfile"
      "$binary" "+FILE=$here/$file" "+LIMIT=$count" +ALLOW_INACTIVE >> "$logfile" 2>&1
    done < "$here/rtl_batches_lf.tsv"
    printf '0\n' > "$logfile.done"
  ) &
  pids+=("$!")
done
status=0
for pid in "${pids[@]}"; do wait "$pid" || status=1; done
if [[ "$status" != 0 ]]; then echo 'At least one W10a shard failed; inspect logs.' >&2; fi
python3 "$here/check_rtl.py" || status=1
exit "$status"
