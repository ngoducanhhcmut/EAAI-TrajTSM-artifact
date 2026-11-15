#!/bin/bash
# Claude 05/11/2026 (W8, copy run_w8c: adds *_tsmxc = TSM-X + B1 freshness contract): nuPlan closed-loop (reactive IDM agents), nominal IDM +/- planner fault +/- TSM-X.
# Claude 07/11/2026 (W11): rerun of the tsmx arms with TSMX_DUMP_DIR set (golden B4/B3 call dump for RTL replay).
# usage (inside WSL): bash run_w8.sh <tag> <per_type> <cond...>      cond = none_raw none_tsmx blind_raw blind_tsmx stale_raw stale_tsmx
# Launch detached from Windows: Start-Process wsl -ArgumentList '-e','bash','<this>','pilot','1','blind_tsmx'
TAG=$1; PER=$2; shift 2
HERE=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/eval_nuplan
mkdir -p $HERE/logs/$TAG
exec > $HERE/logs/$TAG/run.log 2>&1
source ~/miniconda3/etc/profile.d/conda.sh; conda activate nuplan
export NUPLAN_DATA_ROOT=/mnt/c/nuplan/dataset NUPLAN_MAPS_ROOT=/mnt/c/nuplan/dataset/maps NUPLAN_EXP_ROOT=$HOME/nuplan_exp
export PYTHONPATH=$HERE:$PYTHONPATH
# longitudinal-interaction scenario types of the nuPlan challenge list
TYPES="[following_lane_with_lead,stopping_with_lead,behind_long_vehicle,near_multiple_vehicles,stationary_in_traffic,starting_straight_traffic_light_intersection_traversal,waiting_for_pedestrian_to_cross,traversing_pickup_dropoff]"
cd ~/nuplan-devkit
for C in "$@"; do
  F=${C%_*}; M=${C#*_}; TS=$([ "$M" = raw ] && echo false || echo true); CT=$([ "$M" = tsmxc ] && echo true || echo false)
  export TSMX_LOG_DIR=$HERE/logs/$TAG/$C TSMX_DUMP_DIR=$HERE/w11/dump/$C; mkdir -p $TSMX_LOG_DIR $TSMX_DUMP_DIR
  start=$(date +%s)
  nice -n 10 python nuplan/planning/script/run_simulation.py \
    +simulation=closed_loop_reactive_agents planner=tsmx_planner \
    planner.tsmx_planner.fault=$F planner.tsmx_planner.tsmx=$TS planner.tsmx_planner.contract=$CT planner.tsmx_planner.condition=$C \
    scenario_builder=nuplan_mini scenario_builder.data_root=/mnt/c/nuplan/dataset/data/cache/mini \
    scenario_builder.map_root=/mnt/c/nuplan/dataset/maps scenario_builder.sensor_root=null \
    scenario_filter=all_scenarios "scenario_filter.scenario_types=$TYPES" scenario_filter.num_scenarios_per_type=$PER \
    scenario_filter.shuffle=false \
    worker=${W8_WORKER:-sequential} experiment_name=w8_${TAG}_$C \
    "hydra.searchpath=[file://$HERE/config, pkg://nuplan.planning.script.config.common, pkg://nuplan.planning.script.experiments]"
  echo "W8 cond=$C rc=$? elapsed_s=$(( $(date +%s)-start ))"
done
echo "rc=0" > $HERE/logs/$TAG/done
