#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
bitstream=${1:?bitstream path is required}
output_dir=${2:-"$repo_root/_fpga_build/queue_capture"}
xsdb_bin=${XSDB_BIN:-/tools/Xilinx/Vivado/2024.1/bin/xsdb}

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
capture="$output_dir/tournament_capture.txt"
report="$output_dir/tournament_report.html"
capture_last_page=${JTAG_LAST_PAGE:-8192}
wait_ms=${TOURNAMENT_WAIT_MS:-1500000}
poll_ms=${TOURNAMENT_POLL_MS:-60000}

BITSTREAM="$bitstream" "$xsdb_bin" \
  "$repo_root/fpga/xcku115/program_bit.tcl"
"$xsdb_bin" "$repo_root/fpga/xcku115/read_queue.tcl" \
  "$capture" "$capture_last_page" "$wait_ms" "$poll_ms"
python3 "$repo_root/fpga/report/generate_queue_report.py" "$capture" "$report"

echo "QUEUE_CAPTURE=$capture"
echo "QUEUE_REPORT=$report"
