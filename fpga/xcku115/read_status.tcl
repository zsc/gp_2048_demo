connect -url tcp:127.0.0.1:3121
jtag targets -set -filter {name =~ "xcku115*"}
set status_bits 512
set seq [jtag sequence]
$seq irshift -state IDLE -integer 12 0x0A4
$seq drshift -state IDLE -tdi 0 -capture $status_bits
set captures [$seq run -bits]
set bits [lindex $captures 0]
if {[string length $bits] != $status_bits} {
  error "Unexpected USER1 status length: [string length $bits]"
}
set hex_lsb ""
for {set index 0} {$index < $status_bits} {incr index 4} {
  set value 0
  for {set bit 0} {$bit < 4} {incr bit} {
    if {[string index $bits [expr {$index + $bit}]] eq "1"} {
      set value [expr {$value | (1 << $bit)}]
    }
  }
  append hex_lsb [format %x $value]
}
set status_hex [string reverse $hex_lsb]
set status_value [expr 0x$status_hex]
proc status_field {value offset width} {
  return [expr {($value >> $offset) & ((1 << $width) - 1)}]
}
puts "STATUS_BITS=$status_bits"
puts "STATUS_HEX=$status_hex"
puts [format \
  "SEARCH_STATUS magic=%08x version=%d done=%d pass=%d timeout=%d overflow=%d state=%d vectors=%d completed=%d move_mismatches=%d metric_mismatches=%d workers=%d fractional_bits=%d wall_cycles=%d total_search_cycles=%d max_search_cycles=%d" \
  [status_field $status_value 0 32] \
  [status_field $status_value 32 8] \
  [status_field $status_value 40 1] \
  [status_field $status_value 41 1] \
  [status_field $status_value 42 1] \
  [status_field $status_value 43 1] \
  [status_field $status_value 44 3] \
  [status_field $status_value 47 8] \
  [status_field $status_value 55 8] \
  [status_field $status_value 63 8] \
  [status_field $status_value 71 16] \
  [status_field $status_value 101 8] \
  [status_field $status_value 109 8] \
  [status_field $status_value 117 32] \
  [status_field $status_value 149 64] \
  [status_field $status_value 213 64]]
$seq delete
disconnect
exit
