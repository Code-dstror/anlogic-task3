#=============================================================================
# Dump a device package's pin information.
#
# Edit DEVICE_DB / DEVICE_PKG below (look them up in
# references/device-database.md), then run:
#     python <skill>/scripts/run_td.py dump_pins.tcl --workdir <workspace>
#
# Output goes to PIN_DUMP_FILE. `-clock_io` is the important one: only pads
# listed there may drive a clock.
#=============================================================================

set DEVICE_DB  "ph1_60.db"
set DEVICE_PKG "PH1A60GEG324"
set DEVICE_SPEED "3"

# Where to write the dump. Use forward slashes, absolute path.
set PIN_DUMP_FILE "C:/Work/td-example/pins_dump.txt"

set rc [catch { import_device $DEVICE_DB -package $DEVICE_PKG -speed $DEVICE_SPEED } out]
if { $rc != 0 } {
  puts "@@@FAIL import_device: $out"
  puts "  Check DEVICE_DB / DEVICE_PKG / DEVICE_SPEED against references/device-database.md"
  exit 1
}

set fh [open $PIN_DUMP_FILE w]

proc dump { fh label cmd } {
  puts $fh "@@@${label}_START"
  if { [catch { $cmd } r] } {
    puts $fh "  (query failed: $r)"
  } else {
    puts $fh $r
  }
  puts $fh "@@@${label}_END"
}

dump $fh "FIO"          { query_current_package -fio }
dump $fh "CLKIO"        { query_current_package -clock_io }
dump $fh "LVDS"         { query_current_package -lvds }
dump $fh "SINGLE_ENDED" { query_current_package -single_ended }

close $fh
puts "@@@WROTE $PIN_DUMP_FILE"

# Also echo a compact clock-pad summary to stdout, since that is what you
# almost always need when writing a .adc file.
puts "@@@ clock-capable pads for $DEVICE_PKG:"
catch { puts [query_current_package -clock_io] }
