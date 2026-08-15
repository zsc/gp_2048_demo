set output_path [expr {$argc >= 1 ? [file normalize [lindex $argv 0]] : ""}]
set capture_last_page [expr {$argc >= 2 ? [lindex $argv 1] : 8192}]
set timeout_ms [expr {$argc >= 3 ? [lindex $argv 2] : 1500000}]
set poll_ms [expr {$argc >= 4 ? [lindex $argv 3] : 60000}]
set output_channel stdout
if {$output_path ne ""} {
  set output_channel [open $output_path w]
}

proc status_field {value offset width} {
  return [expr {($value >> $offset) & ((1 << $width) - 1)}]
}

proc bits_to_value {bits} {
  set width [string length $bits]
  set hex_lsb ""
  for {set index 0} {$index < $width} {incr index 4} {
    set value 0
    for {set bit 0} {$bit < 4} {incr bit} {
      if {[string index $bits [expr {$index + $bit}]] eq "1"} {
        set value [expr {$value | (1 << $bit)}]
      }
    }
    append hex_lsb [format %x $value]
  }
  return [expr 0x[string reverse $hex_lsb]]
}

connect -url tcp:127.0.0.1:3121
jtag targets -set -filter {name =~ "xcku115*"}

# Polling page zero with TDI=0 never advances the stream.  This makes progress
# visible and catches a stalled tournament before the final bulk read.  Once
# done, keep USER1 selected for one bulk sequence; splitting data pages into
# separate sequences can disturb TAP/USER state.
set poll_start [clock milliseconds]
while {1} {
  set poll_sequence [jtag sequence]
  $poll_sequence irshift -state IDLE -integer 12 0x0A4
  $poll_sequence drshift -state IDLE -tdi 0 -capture 512
  set poll_captures [$poll_sequence run -bits]
  $poll_sequence delete
  set poll_header [bits_to_value [lindex $poll_captures 0]]
  set poll_magic [status_field $poll_header 0 32]
  set poll_version [status_field $poll_header 32 8]
  if {$poll_magic != 0x51323048 || $poll_version != 2} {
    error [format "Bad live header: magic=%08x version=%d" \
        $poll_magic $poll_version]
  }
  set poll_done [status_field $poll_header 40 1]
  set poll_busy [status_field $poll_header 41 1]
  set poll_games [status_field $poll_header 42 16]
  set poll_completed [status_field $poll_header 214 16]
  set poll_wins [status_field $poll_header 230 16]
  set poll_moves [status_field $poll_header 246 64]
  set poll_wall [status_field $poll_header 374 64]
  set poll_state [status_field $poll_header 446 4]
  puts [format \
      "QUEUE_PROGRESS completed=%d/%d wins_2048=%d total_moves=%d wall_cycles=%d busy=%d state=%d" \
      $poll_completed $poll_games $poll_wins $poll_moves $poll_wall \
      $poll_busy $poll_state]
  flush stdout
  if {$poll_done} {
    break
  }
  if {[clock milliseconds] - $poll_start >= $timeout_ms} {
    error "Timed out waiting for the tournament to finish"
  }
  after $poll_ms
}

set bulk_sequence [jtag sequence]
$bulk_sequence irshift -state IDLE -integer 12 0x0A4
$bulk_sequence drshift -state IDLE -tdi 0 -capture 512
# The advancing scan captures header page zero once more, then moves to page 1.
$bulk_sequence drshift -state IDLE -tdi 1 -capture 512
for {set page 1} {$page <= $capture_last_page} {incr page} {
  $bulk_sequence drshift -state IDLE -tdi 1 -capture 512
}
set captures [$bulk_sequence run -bits]
$bulk_sequence delete
if {[llength $captures] != $capture_last_page + 2} {
  error "Unexpected USER1 capture count: [llength $captures]"
}
set header_bits [lindex $captures 0]
if {[string length $header_bits] != 512} {
  error "Unexpected USER1 page length: [string length $header_bits]"
}
set header [bits_to_value $header_bits]

set magic [status_field $header 0 32]
if {$magic != 0x51323048} {
  error [format "Unexpected queue magic: %08x" $magic]
}
set version [status_field $header 32 8]
if {$version != 2} {
  error "Unsupported queue header version: $version"
}
set done [status_field $header 40 1]
if {!$done} {
  error "Timed out waiting for the tournament to finish"
}
set busy [status_field $header 41 1]
set game_count [status_field $header 42 16]
set search_engines [status_field $header 58 8]
set workers [status_field $header 66 8]
set fractional_bits [status_field $header 74 8]
set node_budget [status_field $header 82 16]
set replay_games [status_field $header 98 8]
set max_replay_records [status_field $header 106 16]
set base_seed [status_field $header 122 32]
set summary_page_base [status_field $header 154 14]
set summary_pages [status_field $header 168 16]
set replay_page_base [status_field $header 184 14]
set replay_pages [status_field $header 198 16]
set completed [status_field $header 214 16]
set wins [status_field $header 230 16]
set total_moves [status_field $header 246 64]
set total_search_cycles [status_field $header 310 64]
set wall_cycles [status_field $header 374 64]
set engine_busy [status_field $header 438 8]
set state [status_field $header 446 4]
set clock_mhz [status_field $header 450 16]
set active_game_count [status_field $header 466 16]

set expected_last_page [expr {$replay_page_base +
    $replay_games * $replay_pages - 1}]
if {$capture_last_page != $expected_last_page} {
  error "capture_last_page=$capture_last_page, header requires $expected_last_page"
}

puts $output_channel [format \
  "TOURNAMENT magic=%08x version=%d done=%d busy=%d games=%d active_game_count=%d search_engines=%d workers_per_engine=%d fractional_bits=%d node_budget=%d replay_games=%d max_replay_records=%d base_seed=%08x summary_page_base=%d summary_pages=%d replay_page_base=%d replay_pages=%d completed=%d wins_2048=%d total_moves=%d total_search_cycles=%d wall_cycles=%d engine_busy=%02x state=%d clock_mhz=%d" \
  $magic $version $done $busy $game_count $active_game_count $search_engines $workers \
  $fractional_bits $node_budget $replay_games $max_replay_records \
  $base_seed $summary_page_base $summary_pages $replay_page_base \
  $replay_pages $completed $wins $total_moves $total_search_cycles \
  $wall_cycles $engine_busy $state $clock_mhz]

array set replay_counts {}
for {set page_index 0} {$page_index < $summary_pages} {incr page_index} {
  set stream_page [expr {$summary_page_base + $page_index}]
  set page [bits_to_value [lindex $captures [expr {$stream_page + 1}]]]
  for {set slot 0} {$slot < 4} {incr slot} {
    set game [expr {$page_index * 4 + $slot}]
    if {$game < $game_count} {
      set record [expr {($page >> ($slot * 128)) & ((1 << 128) - 1)}]
      set final_board [expr {$record & ((1 << 64) - 1)}]
      set meta [expr {$record >> 64}]
      set moves [status_field $meta 0 16]
      set highest_exponent [status_field $meta 16 4]
      set won [status_field $meta 20 1]
      set game_over [status_field $meta 21 1]
      set overflow [status_field $meta 22 1]
      set invalid [status_field $meta 23 1]
      set replay_truncated [status_field $meta 24 1]
      set game_done [status_field $meta 25 1]
      set replay_count [status_field $meta 26 13]
      if {$game < $replay_games} {
        set replay_counts($game) $replay_count
      }
      puts $output_channel [format \
        "GAME game=%d done=%d game_over=%d won_2048=%d moves=%d highest_exponent=%d final_board=%016x overflow=%d invalid=%d replay_truncated=%d replay_records=%d" \
        $game $game_done $game_over $won $moves $highest_exponent \
        $final_board $overflow $invalid $replay_truncated $replay_count]
    }
  }
}

for {set game 0} {$game < $replay_games} {incr game} {
  set record_count $replay_counts($game)
  set page_count [expr {($record_count + 3) / 4}]
  for {set page_index 0} {$page_index < $page_count} {incr page_index} {
    set stream_page [expr {$replay_page_base +
        $game * $replay_pages + $page_index}]
    set page [bits_to_value [lindex $captures [expr {$stream_page + 1}]]]
    for {set slot 0} {$slot < 4} {incr slot} {
      set record_index [expr {$page_index * 4 + $slot}]
      if {$record_index < $record_count} {
        set record [expr {($page >> ($slot * 128)) & ((1 << 128) - 1)}]
        set board [expr {$record & ((1 << 64) - 1)}]
        set meta [expr {$record >> 64}]
        puts $output_channel [format \
          "RECORD game=%d index=%d board=%016x move=%d spawn_cell=%d spawn_value=%d search_cycles=%d sequence=%d" \
          $game $record_index $board [status_field $meta 0 3] \
          [status_field $meta 3 5] [status_field $meta 8 2] \
          [status_field $meta 10 32] [status_field $meta 42 22]]
      }
    }
  }
}

if {$output_path ne ""} {
  close $output_channel
  puts "QUEUE_CAPTURE=$output_path"
}
disconnect
exit
