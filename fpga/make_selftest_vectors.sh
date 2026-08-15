#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 GOLDEN_VECTORS OUTPUT_DIR" >&2
  exit 2
fi

input_file=$1
output_dir=$2
mkdir -p "$output_dir"

awk '{print $1}' "$input_file" > "$output_dir/search_boards.mem"
awk '{printf "%x\n", $2}' "$input_file" > "$output_dir/search_moves.mem"
awk '{printf "%016x\n", $3}' "$input_file" > "$output_dir/search_calls.mem"
awk '{printf "%016x\n", $4}' "$input_file" > "$output_dir/search_expanded.mem"
awk '{printf "%016x\n", $5}' "$input_file" > "$output_dir/search_cutoffs.mem"

line_count=$(wc -l < "$input_file")
echo "SELFTEST_VECTORS count=$line_count output=$output_dir"
