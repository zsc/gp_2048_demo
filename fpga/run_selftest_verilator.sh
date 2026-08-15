#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
vector_dir=${1:?vector directory is required}
build_dir=${2:-"$repo_root/_fpga_build/verilator_selftest"}

mkdir -p "$build_dir"
build_dir=$(cd "$build_dir" && pwd)
verilator --binary --timing -Wall -Wno-fatal -DSIM \
  --top-module tb_search_selftest \
  "$repo_root/fpga/rtl/game2048_pkg.sv" \
  "$repo_root/fpga/rtl/search_worker.sv" \
  "$repo_root/fpga/rtl/search_accel.sv" \
  "$repo_root/fpga/xcku115/search_jtag_status.sv" \
  "$repo_root/fpga/xcku115/search_xcku115_selftest_top.sv" \
  "$repo_root/fpga/tb/tb_search_selftest.sv" \
  --Mdir "$build_dir/obj" \
  -o tb_search_selftest

(cd "$vector_dir" && "$build_dir/obj/tb_search_selftest")
