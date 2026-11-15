#!/bin/bash
# Claude 09/11/2026 (W11): rerun only the scenarios whose W11 rerun was cut by the WSL restart of 08/11.
# usage: bash run_rerun_tokens.sh <logtag w11a|w11b> <cond>     tokens from w11/tokens_<cond>.txt
# Same planner/config as run_rerun.sh (W8 settings); per-step logs go to logs/<logtag>/<cond>, dumps to w11/dump/<cond>.
TAG=$1; C=$2
HERE=/mnt/c/Users/TransformerDA/Downloads/vla_new_arch/journalQ1/tsmx_hw/eval_nuplan
TOK=$(cat $HERE/w11/tokens_$C.txt | tr -d '\r\n')
exec > $HERE/logs/$TAG/run_tokens_$C.log 2>&1
source ~/miniconda3/etc/profile.d/conda.sh; conda activate nuplan
export NUPLAN_DATA_ROOT=/mnt/c/nuplan/dataset NUPLAN_MAPS_ROOT=/mnt/c/nuplan/dataset/maps NUPLAN_EXP_ROOT=$HOME/nuplan_exp
export PYTHONPATH=$HERE:$PYTHONPATH
TYPES="[following_lane_with_lead,stopping_with_lead,behind_long_vehicle,near_multiple_vehicles,stationary_in_traffic,starting_straight_traffic_light_intersection_traversal,waiting_for_pedestrian_to_cross,traversing_pickup_dropoff]"
cd ~/nuplan-devkit
F=${C%_*}; M=${C#*_}; TS=$([ "$M" = raw ] && echo false || echo true); CT=$([ "$M" = tsmxc ] && echo true || echo false)
export TSMX_LOG_DIR=$HERE/logs/$TAG/$C TSMX_DUMP_DIR=$HERE/w11/dump/$C
start=$(date +%s)
nice -n 10 python nuplan/planning/script/run_simulation.py \
  +simulation=closed_loop_reactive_agents planner=tsmx_planner \
  planner.tsmx_planner.fault=$F planner.tsmx_planner.tsmx=$TS planner.tsmx_planner.contract=$CT planner.tsmx_planner.condition=$C \
  scenario_builder=nuplan_mini scenario_builder.data_root=/mnt/c/nuplan/dataset/data/cache/mini \
  scenario_builder.map_root=/mnt/c/nuplan/dataset/maps scenario_builder.sensor_root=null \
  scenario_filter=all_scenarios "scenario_filter.scenario_types=$TYPES" scenario_filter.num_scenarios_per_type=8 \
  "scenario_filter.scenario_tokens=[$TOK]" scenario_filter.shuffle=false \
  worker=sequential experiment_name=w11_tokens_$C \
  "hydra.searchpath=[file://$HERE/config, pkg://nuplan.planning.script.config.common, pkg://nuplan.planning.script.experiments]"
echo "W11 tokens cond=$C rc=$? elapsed_s=$(( $(date +%s)-start ))"
touch $HERE/logs/$TAG/tokens_$C.done
