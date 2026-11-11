#=============================================================================
# Stepwise "single run" flow: drive every stage yourself.
#
# Use this instead of flow_full.tcl when you need per-stage control, an
# existing project, or intermediate netlists. Note the stage-ordering rules:
#   - read_adc  must precede optimize_rtl
#   - read_sdc  must precede optimize_gate
#   - read_sdc  must be re-issued after legalize_phy_inst
#
# Run:  python <skill>/scripts/run_td.py flow_single_run.tcl --workdir <ws>
#=============================================================================

#------------------------------- CONFIG --------------------------------------
if { ![info exists DEVICE_DB] }    { set DEVICE_DB    "ph1_60.db" }
if { ![info exists DEVICE_PKG] }   { set DEVICE_PKG   "PH1A60GEG324" }
if { ![info exists DEVICE_SPEED] } { set DEVICE_SPEED "3" }

if { ![info exists HDL_FILES] } { set HDL_FILES {C:/Work/td-example/demo/top.v
                                                 C:/Work/td-example/demo/uart_tx.v} }
if { ![info exists ADC_FILE] }  { set ADC_FILE  "C:/Work/td-example/demo/demo.adc" }
if { ![info exists SDC_FILE] }  { set SDC_FILE  "C:/Work/td-example/demo/demo.sdc" }
if { ![info exists TOP_MODULE] } { set TOP_MODULE "top" }

# Output directory and bitstream name.
if { ![info exists OUT_DIR] } { set OUT_DIR "C:/Work/td-example/single" }
if { ![info exists BIT_FILE] } { set BIT_FILE "$OUT_DIR/${TOP_MODULE}.bit" }

proc banner { m } { puts "\n@@@ $m" }

file mkdir $OUT_DIR

#----------------------------- device ----------------------------------------
banner "import_device $DEVICE_DB -package $DEVICE_PKG -speed $DEVICE_SPEED"
set rc [catch { import_device $DEVICE_DB -package $DEVICE_PKG -speed $DEVICE_SPEED } out]
if { $rc != 0 } { puts "@@@FAIL import_device: $out"; exit 1 }

#--------------------------- read design + synth -----------------------------
banner "read_hdl"
set rc [catch { read_hdl -file $HDL_FILES -top $TOP_MODULE } out]
if { $rc != 0 } { puts "@@@FAIL read_hdl: $out"; exit 1 }

banner "read_adc (must precede optimize_rtl)"
set rc [catch { read_adc $ADC_FILE } out]
if { $rc != 0 } { puts "@@@FAIL read_adc: $out"; exit 1 }

banner "optimize_rtl"
set rc [catch { optimize_rtl } out]
if { $rc != 0 } { puts "@@@FAIL optimize_rtl: $out"; exit 1 }

banner "read_sdc (must precede optimize_gate)"
set rc [catch { read_sdc $SDC_FILE } out]
if { $rc != 0 } { puts "@@@FAIL read_sdc: $out"; exit 1 }

banner "optimize_gate"
set rc [catch { optimize_gate } out]
if { $rc != 0 } { puts "@@@FAIL optimize_gate: $out"; exit 1 }

banner "legalize_phy_inst + re-read sdc"
catch { legalize_phy_inst }
catch { read_sdc $SDC_FILE }

catch { export_db $OUT_DIR/gate.db }
catch { report_qor  -step gate -file $OUT_DIR/gate.qor }
catch { report_area -file $OUT_DIR/gate.area }
catch { update_timing; report_timing_summary -file $OUT_DIR/gate.timing }

#--------------------------- place & route -----------------------------------
banner "place"
set rc [catch { place } out]
if { $rc != 0 } { puts "@@@FAIL place: $out"; exit 1 }
catch { report_qor -step place -file $OUT_DIR/place.qor }
catch { update_timing -mode manhattan }
catch { report_timing_summary -file $OUT_DIR/place.timing }

banner "route"
set rc [catch { route } out]
if { $rc != 0 } { puts "@@@FAIL route: $out"; exit 1 }
catch { export_db $OUT_DIR/route.db }
catch { report_qor -step route -file $OUT_DIR/route.qor }
catch { report_area -io_info -file $OUT_DIR/route.area }
catch { update_timing -mode final }
catch { report_timing_status  -file $OUT_DIR/route.ts }
catch { report_timing_summary -file $OUT_DIR/route.timing }

#------------------------------- bitstream -----------------------------------
banner "bitgen"
set rc [catch { bitgen -bit $BIT_FILE } out]
if { $rc != 0 } { puts "@@@FAIL bitgen: $out"; exit 1 }

banner "artifacts"
foreach f [list $BIT_FILE $OUT_DIR/route.timing $OUT_DIR/route.qor] {
  if { [file exists $f] } {
    puts "  OK   $f ([file size $f] bytes)"
  } else {
    puts "  MISS $f"
  }
}

banner "DONE"
