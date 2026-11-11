#=============================================================================
# Anlogic TD - complete project-mode flow (create -> synth -> P&R -> bitstream)
#
# Template. Copy into the project workspace and edit the CONFIG block, or
# override any value from the command line by defining it first, e.g.:
#     set PROJECT_NAME mydesign ; source flow.tcl
#
# Run:  python <skill>/scripts/run_td.py flow.tcl --workdir <workspace>
#=============================================================================

#------------------------------- CONFIG --------------------------------------
# Project name == the .al file stem. Keep it aligned with the top module.
if { ![info exists PROJECT_NAME] } { set PROJECT_NAME "demo" }

# Directory that will hold <PROJECT_NAME>.al and <PROJECT_NAME>_Runs/.
# Use forward slashes and an absolute path; TD stores it verbatim in the .al.
if { ![info exists PROJECT_DIR] } { set PROJECT_DIR "C:/Work/td-example/build" }

# Device db name, package, speed. Look these up in the skill's
# references/device-database.md - they must match a real row.
if { ![info exists DEVICE_DB] }  { set DEVICE_DB  "ph1_60.db" }
if { ![info exists DEVICE_PKG] } { set DEVICE_PKG "PH1A60GEG324" }
if { ![info exists DEVICE_FAMILY] } { set DEVICE_FAMILY "ph1" }
if { ![info exists DEVICE_SPEED] } { set DEVICE_SPEED "3" }

# Top-level module name.
if { ![info exists TOP_MODULE] } { set TOP_MODULE "top" }

# Source files: HDL first, then .adc (pin) and .sdc (timing) constraints.
if { ![info exists HDL_FILES] }  { set HDL_FILES  {C:/Work/td-example/demo/top.v
                                                    C:/Work/td-example/demo/uart_tx.v} }
if { ![info exists ADC_FILES] }  { set ADC_FILES  {C:/Work/td-example/demo/demo.adc} }
if { ![info exists SDC_FILES] }  { set SDC_FILES  {C:/Work/td-example/demo/demo.sdc} }

# Where step reports are written (defaults to inside the project dir).
if { ![info exists REPORT_DIR] } { set REPORT_DIR "$PROJECT_DIR/reports" }

# How far to push each run. NOTE: the two run types accept DIFFERENT step names
# (verified against TD 6.2.1 - an invalid value prints the legal set):
#   syn_1 : read_design | opt_rtl | opt_gate      (default: opt_gate)
#   phy_1 : opt_place  | opt_route | bitgen       (default: bitgen)
if { ![info exists SYN_STEP] } { set SYN_STEP "opt_gate" }
if { ![info exists PHY_STEP] } { set PHY_STEP "bitgen" }

#------------------------------- HELPERS -------------------------------------
proc banner { msg } { puts "\n@@@ $msg" }

# Fail fast with a clear message: TD often only warns, which hides real problems.
proc must { label rc } {
  if { $rc != 0 } {
    puts "@@@FAIL $label (rc=$rc)"
    exit 1
  }
}

#----------------------------- 1. PROJECT ------------------------------------
# import_device first. create_project would load the device anyway, but having
# it here is what keeps a later open_run on a *reopened* project from crashing
# TD with an access violation. It also validates the db/package/speed triple
# before anything is created.
banner "import_device $DEVICE_DB -package $DEVICE_PKG -speed $DEVICE_SPEED"
set rc [catch { import_device $DEVICE_DB -package $DEVICE_PKG -speed $DEVICE_SPEED } out]
if { $rc != 0 } {
  puts "@@@FAIL import_device: $out"
  puts "  Check DEVICE_DB / DEVICE_PKG / DEVICE_SPEED in references/device-database.md"
  exit 1
}
puts "  device OK"

banner "create_project $PROJECT_NAME"
file mkdir $PROJECT_DIR
file mkdir $REPORT_DIR

# create_project aborts if the .al already exists, so clear a previous one and
# any run directory. This makes the script re-runnable.
set AL_FILE "$PROJECT_DIR/$PROJECT_NAME.al"
set RUN_DIR "$PROJECT_DIR/${PROJECT_NAME}_Runs"
if { [file exists $AL_FILE] } {
  puts "  (removing existing $AL_FILE for a clean rebuild)"
  file delete -force $AL_FILE
  file delete -force $RUN_DIR
}

set rc [catch {
  create_project $PROJECT_NAME $PROJECT_DIR \
      -family $DEVICE_FAMILY -device $DEVICE_PKG -speed $DEVICE_SPEED
} out]
puts "  $out"
must "create_project" $rc

banner "open_project"
must "open_project" [catch { open_project $AL_FILE } out]
puts "  $out"

banner "top_module $TOP_MODULE"
must "top_module" [catch { top_module $TOP_MODULE } out]
puts "  $out"

banner "add_files"
foreach f [concat $HDL_FILES $ADC_FILES $SDC_FILES] {
  if { ![file exists $f] } { puts "  !! MISSING FILE: $f"; exit 1 }
  must "add_files $f" [catch { add_files $f } out]
  puts "  + $f"
}

#------------------------------ 2. SYNTHESIS ---------------------------------
banner "reset + launch syn_1 (to $SYN_STEP)"
reset_runs syn_1
must "launch_runs syn_1" [catch { launch_runs -step $SYN_STEP syn_1 } out]
puts "  $out"

# wait_run returns 0 even when the run aborted - the real verdict comes from
# the run log and the .error.f markers, which run_td.py checks.
banner "wait_run syn_1"
wait_run syn_1 -quiet

banner "open_run syn_1 + reports"
set rc [catch { open_run syn_1 } out]
puts "  open_run rc=$rc $out"
if { $rc == 0 } {
  catch { report_area        -file $REPORT_DIR/after_syn.area }
  catch { report_logic_level -file $REPORT_DIR/after_syn.logiclvl }
  catch { report_timing_summary -file $REPORT_DIR/after_syn.timing }
  close_run
}

#--------------------------- 3. PLACE & ROUTE --------------------------------
banner "launch phy_1 (to $PHY_STEP)"
set rc [catch { launch_runs -step $PHY_STEP phy_1 } out]
puts "  $out"
if { $rc != 0 } { puts "@@@FAIL launch_runs phy_1"; exit 1 }

banner "wait_run phy_1"
wait_run phy_1 -quiet

banner "open_run phy_1 + final reports"
set rc [catch { open_run phy_1 } out]
puts "  open_run rc=$rc $out"
if { $rc != 0 } { puts "@@@FAIL open_run phy_1"; exit 1 }

catch { update_timing -mode final }
catch { report_timing_summary -file $REPORT_DIR/final.timing }
catch { report_timing_status  -file $REPORT_DIR/final.ts }
catch { report_qor -step route -file $REPORT_DIR/final.qor }
catch { report_area -io_info    -file $REPORT_DIR/final.area }
catch { report_clock_utilization -file $REPORT_DIR/clock_utilization.txt }
catch { report_timing_path  -file $REPORT_DIR/timing_paths.rpt }
catch { report_clock_summary -file $REPORT_DIR/clock_summary.rpt }
catch { check_timing        -file $REPORT_DIR/check_timing.rpt }

# Simulation inputs must be produced HERE, while the routed db is open.
# Re-opening a finished project in a new process and calling open_run phy_1
# crashes TD 6.2.1, so this script is the only reliable place to do it.
# Set GEN_NETLIST 0 to skip.
if { ![info exists GEN_NETLIST] } { set GEN_NETLIST 1 }
if { $GEN_NETLIST } {
  banner "write_verilog / write_sdf (routed netlist + back-annotation)"
  set rc [catch { write_verilog $REPORT_DIR/post_route.v } out]
  puts "  write_verilog rc=$rc"
  set rc [catch { write_sdf -file $REPORT_DIR/post_route.sdf } out]
  puts "  write_sdf     rc=$rc"
  # An empty SDF means no back-annotation was available - check before using it.
  if { [file exists $REPORT_DIR/post_route.sdf] } {
    if { [file size $REPORT_DIR/post_route.sdf] == 0 } {
      puts "  !! post_route.sdf is EMPTY - do not use it for timing simulation"
    } else {
      puts "  OK post_route.sdf ([file size $REPORT_DIR/post_route.sdf] bytes)"
    }
  }
}
close_run

#------------------------------- 4. RESULTS ----------------------------------
banner "artifacts"
foreach f [list \
    "$RUN_DIR/phy_1/${PROJECT_NAME}.bit" \
    "$RUN_DIR/best_result/${PROJECT_NAME}.bit" \
    "$REPORT_DIR/final.timing" \
    "$REPORT_DIR/final.qor" ] {
  if { [file exists $f] } {
    puts "  OK   $f ([file size $f] bytes)"
  } else {
    puts "  MISS $f"
  }
}

close_project
banner "DONE"
