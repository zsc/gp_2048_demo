if {![info exists ::env(BITSTREAM)] || $::env(BITSTREAM) eq ""} {
  error "BITSTREAM environment variable is required"
}
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "xcku115*"}
fpga -file $::env(BITSTREAM)
disconnect
exit
