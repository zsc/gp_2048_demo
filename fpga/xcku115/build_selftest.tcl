set_param general.maxThreads 12
set script_dir [file normalize [file dirname [info script]]]
set project_root [file normalize [file join $script_dir ../..]]

set workers [expr {$argc >= 1 ? [lindex $argv 0] : 32}]
set vector_dir [expr {$argc >= 2 ? [file normalize [lindex $argv 1]] : ""}]
set output_dir [expr {$argc >= 3 ? [file normalize [lindex $argv 2]] : \
  [file normalize [file join $project_root _fpga_build/xcku115_selftest_w${workers}]]}]
set part "xcku115-flvb2104-2-e"

if {![string is integer -strict $workers] || $workers < 1 || $workers > 64} {
  error "workers must be an integer in 1..64"
}
if {$vector_dir eq "" || ![file isdirectory $vector_dir]} {
  error "vector_dir must name a directory containing search_*.mem"
}
if {[llength [get_parts -quiet $part]] != 1} {
  error "XCKU115 part is unavailable: $part"
}

file mkdir $output_dir
foreach name {search_boards.mem search_moves.mem search_calls.mem \
              search_expanded.mem search_cutoffs.mem} {
  set source [file join $vector_dir $name]
  if {![file exists $source]} { error "missing self-test vector: $source" }
  file copy -force $source [file join $output_dir $name]
}
cd $output_dir

read_verilog -sv [file join $project_root fpga/rtl/game2048_pkg.sv]
read_verilog -sv [file join $project_root fpga/rtl/search_worker.sv]
read_verilog -sv [file join $project_root fpga/rtl/search_accel.sv]
read_verilog -sv [file join $script_dir search_jtag_status.sv]
read_verilog -sv [file join $script_dir search_xcku115_selftest_top.sv]
synth_design -top search_xcku115_selftest_top -part $part \
  -flatten_hierarchy rebuilt -generic WORKERS=$workers

set_property PACKAGE_PIN BA34 [get_ports sys_clk_p]
set_property PACKAGE_PIN BB34 [get_ports sys_clk_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports {sys_clk_p sys_clk_n}]
create_clock -name sys_clk_300mhz -period 3.333333 [get_ports sys_clk_p]
create_generated_clock -name test_clk -source [get_ports sys_clk_p] \
  -divide_by 5 [get_pins u_extclk_div5/O]

report_utilization -file [file join $output_dir utilization_synth.rpt]
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

set bitstream [file join $output_dir search_xcku115_selftest_w${workers}.bit]
write_bitstream -force $bitstream
set timing_path [get_timing_paths -quiet -max_paths 1]
if {[llength $timing_path] > 0} {
  puts "SEARCH_XCKU115_WNS [get_property SLACK [lindex $timing_path 0]]"
}
puts "SEARCH_XCKU115_PART $part"
puts "SEARCH_XCKU115_CLOCK_MHZ 60.0"
puts "SEARCH_XCKU115_BITSTREAM $bitstream"
exit 0
