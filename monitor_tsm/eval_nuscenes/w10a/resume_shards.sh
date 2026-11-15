#!/bin/bash
# Claude 09/11/2026: resume the 8-shard W10a RTL replay after the WSL restart of 08/11. Completed batches (with their
# "PASS top jobs=" completion and assertion summary) are kept; the interrupted batch is cut from the log and rerun from
# its start (batches are independent invocations, so the strict check_rtl.py still applies unchanged).
cd /mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/eval_nuscenes/w10a
here=$(pwd)
start=$(date +%s)
cd ../../tb/integ
binary=./obj_2/Vtb_m_tsmx_top
logdir=vl_claude_r17_a8_apos
python3 - <<'EOF'
import re, pathlib
d = pathlib.Path('vl_claude_r17_a8_apos')
for k in range(8):
    p = d / f'w10a_shard_{k}.txt'
    t = p.read_text(errors='replace')
    heads = [m.start() for m in re.finditer(r'^W10A_BATCH ', t, re.M)]
    keep = 0
    for i, h in enumerate(heads):
        end = heads[i + 1] if i + 1 < len(heads) else len(t)
        body = t[h:end]
        if re.search(r'^PASS top jobs=\d+ max_cycles=\d+\s*$', body, re.M) and 'assertion failures: 0' in body:
            keep = end
        else:
            break
    p.write_text(t[:keep])
    print(f'shard {k}: kept {t[:keep].count("W10A_BATCH")} complete batches')
EOF
pids=()
for k in {0..7}; do
  (
    logfile="$logdir/w10a_shard_${k}.txt"
    rm -f -- "$logfile.done"
    done_batches=$(grep -c '^W10A_BATCH' "$logfile")
    n=0
    while IFS=$'\t' read -r shard batch bstart count file; do
      [[ "$shard" == "$k" ]] || continue
      n=$((n+1)); [[ $n -le $done_batches ]] && continue
      printf 'W10A_BATCH shard=%s batch=%s start=%s count=%s\n' "$shard" "$batch" "$bstart" "$count" >> "$logfile"
      nice -n 10 "$binary" "+FILE=$here/$file" "+LIMIT=$count" +ALLOW_INACTIVE >> "$logfile" 2>&1
    done < "$here/rtl_batches_lf.tsv"
    printf '0\n' > "$logfile.done"
  ) &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
python3 "$here/check_rtl.py" > "$here/run_rtl_shards.log" 2>&1
echo "rc=$? elapsed_s=$(( $(date +%s)-start )) $(date)" > "$here/run_rtl_shards.done"
