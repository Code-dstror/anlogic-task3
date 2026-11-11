#=============================================================================
# Self-test: run the shipped example design through the full flow.
#
# This is the skill's regression test. Run it after changing any script here:
#
#   python <skill>/scripts/run_td.py <skill>/scripts/selfcheck_example.tcl \
#          --workdir <scratch> --log <scratch>/selfcheck.log
#
# Expected: "RESULT : SUCCESS", and a bitstream plus post_route.v/.sdf under
# PROJECT_DIR. If this fails, the skill's scripts are broken.
#
# Override SELFCHECK_DIR to run it somewhere else.
#=============================================================================

# Resolve the skill root from this script's own location, so the test works
# regardless of where the skill is installed.
set SCRIPT_PATH [info script]
set SKILL_ROOT [file dirname [file dirname $SCRIPT_PATH]]
set EX "$SKILL_ROOT/examples/uart_demo"

if { ![info exists SELFCHECK_DIR] } {
  set SELFCHECK_DIR "$SKILL_ROOT/.selfcheck"
}

puts "@@@ selfcheck"
puts "@@@   skill root : $SKILL_ROOT"
puts "@@@   example    : $EX"
puts "@@@   output dir : $SELFCHECK_DIR"

foreach f [list "$EX/top.v" "$EX/uart_tx.v" "$EX/demo.adc" "$EX/demo.sdc"] {
  if { ![file exists $f] } {
    puts "@@@FAIL missing example file: $f"
    exit 1
  }
}

set PROJECT_NAME "selfcheck"
set PROJECT_DIR  $SELFCHECK_DIR
set HDL_FILES [list "$EX/top.v" "$EX/uart_tx.v"]
set ADC_FILES [list "$EX/demo.adc"]
set SDC_FILES [list "$EX/demo.sdc"]

source "$SKILL_ROOT/scripts/flow_full.tcl"

# flow_full.tcl reports artifacts but does not fail on a missing bitstream,
# so assert the two files that matter here.
set bit "$PROJECT_DIR/${PROJECT_NAME}_Runs/phy_1/${PROJECT_NAME}.bit"
set sdf "$PROJECT_DIR/reports/post_route.sdf"

set ok 1
foreach f [list $bit $sdf] {
  if { [file exists $f] && [file size $f] > 0 } {
    puts "@@@ selfcheck OK   $f ([file size $f] bytes)"
  } else {
    puts "@@@ selfcheck MISS $f"
    set ok 0
  }
}

if { $ok } {
  puts "@@@SELFCHECK PASS"
} else {
  puts "@@@SELFCHECK FAIL"
  exit 1
}
