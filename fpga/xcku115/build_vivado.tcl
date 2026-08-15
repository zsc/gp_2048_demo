# Non-project XCKU115 build for the parallel 2048 search accelerator.
#
# Usage:
#   vivado -mode batch -source fpga/xcku115/build_vivado.tcl -tclargs \
#     <workers> <period-ns> <synth|full> <output-dir>

set_param general.maxThreads 12
set script_dir [file normalize [file dirname [info script]]]
set project_root [file normalize [file join $script_dir ../..]]
set workers [expr {$argc >= 1 ? [lindex $argv 0] : 32}]
set period_ns [expr {$argc >= 2 ? [lindex $argv 1] : 16.0}]
set build_mode [expr {$argc >= 3 ? [lindex $argv 2] : "synth"}]
set output_dir [expr {$argc >= 4 ? [file normalize [lindex $argv 3]] : \
  [file normalize [file join $project_root _fpga_build/vivado_w${workers}]]}]
set part "xcku115-flva1517-2-e"

if {![string is integer -strict $workers] || $workers < 1 || $workers > 64} {
  error "workers must be an integer in 1..64"
}
if {![string is double -strict $period_ns] || $period_ns <= 0.0} {
  error "period must be positive"
}
if {$build_mode ni {synth full}} {
  error "build mode must be synth or full"
}
if {[llength [get_parts -quiet $part]] != 1} {
  error "XCKU115 part is unavailable: $part"
}

file mkdir $output_dir
read_verilog -sv [file join $project_root fpga/rtl/game2048_pkg.sv]
read_verilog -sv [file join $project_root fpga/rtl/search_worker.sv]
read_verilog -sv [file join $project_root fpga/rtl/search_accel.sv]

synth_design -top search_accel -part $part -mode out_of_context \
  -flatten_hierarchy rebuilt -generic WORKERS=$workers
create_clock -name search_clock -period $period_ns [get_ports clock]

report_utilization -file [file join $output_dir utilization_synth.rpt]
report_utilization -hierarchical -hierarchical_depth 4 \
  -file [file join $output_dir utilization_synth_hier.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
  -file [file join $output_dir timing_synth.rpt]
if {[catch {
  write_checkpoint -force [file join $output_dir post_synth.dcp]
} checkpoint_error]} {
  puts "SEARCH_CHECKPOINT_WARNING stage=synth error=$checkpoint_error"
}

if {$build_mode eq "synth"} {
  puts "SEARCH_SYNTH_COMPLETE workers=$workers period_ns=$period_ns out=$output_dir"
  exit 0
}

opt_design
place_design
phys_opt_design
report_utilization -file [file join $output_dir utilization_place.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
  -file [file join $output_dir timing_place.rpt]
if {[catch {
  write_checkpoint -force [file join $output_dir post_place.dcp]
} checkpoint_error]} {
  puts "SEARCH_CHECKPOINT_WARNING stage=place error=$checkpoint_error"
}

route_design
phys_opt_design -directive AggressiveExplore
report_route_status -file [file join $output_dir route_status.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
  -file [file join $output_dir timing_route.rpt]
report_timing -delay_type max -max_paths 20 -path_type full_clock_expanded \
  -file [file join $output_dir critical_paths_route.rpt]
report_drc -file [file join $output_dir drc_route.rpt]
if {[catch {
  write_checkpoint -force [file join $output_dir post_route.dcp]
} checkpoint_error]} {
  puts "SEARCH_CHECKPOINT_WARNING stage=route error=$checkpoint_error"
}

set timing_path [get_timing_paths -quiet -max_paths 1]
if {[llength $timing_path] > 0} {
  puts "SEARCH_ROUTE_WNS [get_property SLACK [lindex $timing_path 0]]"
}
puts "SEARCH_ROUTE_COMPLETE workers=$workers period_ns=$period_ns out=$output_dir"
