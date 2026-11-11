#=============================================================================
# Write the standard report bundle for a completed project.
#
# Every report is wrapped in `catch` so one unsupported report cannot abort the
# batch. Verify the files exist afterwards - `catch` also hides real failures.
#
# Run:  python <skill>/scripts/run_td.py report_bundle.tcl --workdir <ws>
#=============================================================================

if { ![info exists PROJECT_DIR] } { set PROJECT_DIR "C:/Work/td-example/build" }
if { ![info exists PROJECT_NAME] } { set PROJECT_NAME "demo" }
if { ![info exists RUN_NAME] } { set RUN_NAME "phy_1" }
if { ![info exists REPORT_DIR] } { set REPORT_DIR "$PROJECT_DIR/reports" }

file mkdir $REPORT_DIR

proc banner { m } { puts "\n@@@ $m" }

banner "open_project $PROJECT_DIR/$PROJECT_NAME.al"
set rc [catch { open_project $PROJECT_DIR/$PROJECT_NAME.al } out]
if { $rc != 0 } { puts "@@@FAIL open_project: $out"; exit 1 }

banner "open_run $RUN_NAME"
set rc [catch { open_run $RUN_NAME } out]
if { $rc != 0 } {
  puts "@@@FAIL open_run $RUN_NAME: $out"
  puts "  The run may not have completed. Check <project>_Runs/$RUN_NAME/run.log"
  exit 1
}

banner "timing analysis"
# update_timing modes: basic | manhattan | final
# final is the sign-off mode after routing.
catch { update_timing -mode final }
catch { report_timing_summary    -file $REPORT_DIR/timing_summary.rpt }
catch { report_timing_path       -file $REPORT_DIR/timing_paths.rpt }
catch { report_timing_status     -file $REPORT_DIR/timing_status.ts }
catch { report_timing_exception  -file $REPORT_DIR/timing_exceptions.rpt }
catch { report_timing_ignored    -file $REPORT_DIR/timing_ignored.rpt }
catch { report_clock_summary     -file $REPORT_DIR/clock_summary.rpt }
catch { report_clock_intersection -file $REPORT_DIR/clock_intersection.rpt }
catch { check_timing             -file $REPORT_DIR/check_timing.rpt }

banner "qor / area / utilization"
catch { report_qor -step route  -file $REPORT_DIR/qor_route.rpt }
catch { report_qor -step place  -file $REPORT_DIR/qor_place.rpt }
catch { report_area -io_info    -file $REPORT_DIR/area.rpt }
catch { report_logic_level      -file $REPORT_DIR/logic_level.rpt }
catch { report_clock_utilization -file $REPORT_DIR/clock_utilization.rpt }

banner "routing health"
catch { report_route_status -drc -file $REPORT_DIR/route_drc.rpt }
catch { report_congestion -step route -file $REPORT_DIR/congestion.rpt }

banner "artifacts written"
set written 0
set missing 0
foreach f [glob -nocomplain $REPORT_DIR/*] {
  puts "  [file size $f] bytes  $f"
  incr written
}
if { $written == 0 } { puts "  !! no reports were produced" }

close_run
close_project
banner "DONE"
