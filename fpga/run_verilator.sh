#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
build_dir=${1:-"$repo_root/_fpga_build/verilator"}
workers=${2:-32}
vector_file=${3:-}

mkdir -p "$build_dir"
verilator --binary --timing -Wall -Wno-fatal \
  --top-module tb_search_accel \
  -GWORKERS="$workers" \
  "$repo_root/fpga/rtl/game2048_pkg.sv" \
  "$repo_root/fpga/rtl/search_worker.sv" \
  "$repo_root/fpga/rtl/search_accel.sv" \
  "$repo_root/fpga/tb/tb_search_accel.sv" \
  --Mdir "$build_dir/obj" \
  -o tb_search_accel

if [[ -n "$vector_file" ]]; then
  "$build_dir/obj/tb_search_accel" "+VECTOR_FILE=$vector_file"
else
  "$build_dir/obj/tb_search_accel"
fi
