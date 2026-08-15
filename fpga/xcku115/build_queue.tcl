set_param general.maxThreads 12
set script_dir [file normalize [file dirname [info script]]]
set project_root [file normalize [file join $script_dir ../..]]

set game_count [expr {$argc >= 1 ? [lindex $argv 0] : 16384}]
set search_engines [expr {$argc >= 2 ? [lindex $argv 1] : 4}]
set workers_per_engine [expr {$argc >= 3 ? [lindex $argv 2] : 16}]
set node_budget [expr {$argc >= 4 ? [lindex $argv 3] : 1000}]
set output_dir [expr {$argc >= 5 ? [file normalize [lindex $argv 4]] : \
  [file normalize [file join $project_root \
    _fpga_build/xcku115_queue_g${game_count}_e${search_engines}_w${workers_per_engine}]]}]
set part "xcku115-flvb2104-2-e"

if {![string is integer -strict $game_count] || $game_count < 128 ||
    $game_count > 16384 || (($game_count & ($game_count - 1)) != 0)} {
  error "game_count must be a power of two in 128..16384"
}
if {$search_engines != 2 && $search_engines != 4} {
  error "search_engines must be 2 or 4"
}
if {![string is integer -strict $workers_per_engine] ||
    $workers_per_engine < 4 || $workers_per_engine > 32} {
  error "workers_per_engine must be an integer in 4..32"
}
if {![string is integer -strict $node_budget] ||
    $node_budget < 1 || $node_budget > 65535} {
  error "node_budget must be an integer in 1..65535"
}
if {[llength [get_parts -quiet $part]] != 1} {
  error "XCKU115 part is unavailable: $part"
}

file mkdir $output_dir
cd $output_dir
read_verilog -sv [file join $project_root fpga/rtl/game2048_pkg.sv]
read_verilog -sv [file join $project_root fpga/rtl/search_worker.sv]
read_verilog -sv [file join $project_root fpga/rtl/search_accel.sv]
read_verilog -sv [file join $project_root fpga/rtl/game2048_tournament_queue.sv]
read_verilog -sv [file join $script_dir search_jtag_pages.sv]
read_verilog -sv [file join $script_dir search_xcku115_queue_top.sv]
synth_design -top search_xcku115_queue_top -part $part \
  -flatten_hierarchy rebuilt \
  -generic GAME_COUNT=$game_count \
  -generic SEARCH_ENGINES=$search_engines \
  -generic WORKERS_PER_ENGINE=$workers_per_engine \
  -generic NODE_BUDGET=$node_budget

set_property PACKAGE_PIN BA34 [get_ports sys_clk_p]
set_property PACKAGE_PIN BB34 [get_ports sys_clk_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports {sys_clk_p sys_clk_n}]
create_clock -name sys_clk_300mhz -period 3.333333 [get_ports sys_clk_p]
create_generated_clock -name game_clk -source [get_ports sys_clk_p] \
  -divide_by 5 [get_pins u_extclk_div5/O]

report_utilization -file [file join $output_dir utilization_synth.rpt]
report_utilization -hierarchical -hierarchical_depth 3 \
  -file [file join $output_dir utilization_hierarchical_synth.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
  -file [file join $output_dir timing_synth.rpt]
write_checkpoint -force [file join $output_dir post_synth.dcp]

opt_design
place_design
phys_opt_design
report_utilization -file [file join $output_dir utilization_place.rpt]
write_checkpoint -force [file join $output_dir post_place.dcp]

route_design
report_route_status -file [file join $output_dir route_status.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
  -file [file join $output_dir timing_route.rpt]
report_timing -delay_type max -max_paths 20 -path_type full_clock_expanded \
  -file [file join $output_dir critical_paths_route.rpt]
report_drc -file [file join $output_dir drc_route.rpt]
write_checkpoint -force [file join $output_dir post_route.dcp]

set bitstream [file join $output_dir \
  search_xcku115_queue_g${game_count}_e${search_engines}_w${workers_per_engine}.bit]
write_bitstream -force $bitstream
set timing_path [get_timing_paths -quiet -max_paths 1]
if {[llength $timing_path] > 0} {
  puts "QUEUE_XCKU115_WNS [get_property SLACK [lindex $timing_path 0]]"
}
puts "QUEUE_XCKU115_PART $part"
puts "QUEUE_XCKU115_GAME_COUNT $game_count"
puts "QUEUE_XCKU115_SEARCH_ENGINES $search_engines"
puts "QUEUE_XCKU115_WORKERS_PER_ENGINE $workers_per_engine"
puts "QUEUE_XCKU115_NODE_BUDGET $node_budget"
puts "QUEUE_XCKU115_CLOCK_MHZ 60.0"
puts "QUEUE_XCKU115_BITSTREAM $bitstream"
exit 0
