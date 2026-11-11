# Inspect only the project's existing read_design DB. No synthesis or physical runs.
set camera_dir [file normalize [file join [file dirname [info script]] ../al]]
cd $camera_dir
import_device ph1_90.db -package PH1A90SEG324 -speed 2
import_db rfcamera_fusion_r1_Runs/syn_1/rfcamera_fusion_r1_elaborate.db
set owner {g_s04$u_raw_service/g_cam1_hdr$shared_owner}
proc require_reference {path model} {
    set cells [get_cells -nowarn $path]
    set actual [get_property -nowarn REF_NAME $cells]
    puts "CAMERA_HDR_CELL $path $actual"
    if {[llength $cells]!=1 || $actual ne $model} {error "Unexpected cell at $path, expected $model"}
}

# Preserve the existing DFI reset synchronizer and falling-edge ASR hierarchy;
# expose the already existing rising-edge state only for synchronous qualifiers.
require_reference {u_product_dfi_reset} {reset_release_sync_data(DATA_RESET_COPIES=0,FALLING_RELEASE=1)}
foreach bit {0 1 2} {
    if {[llength [get_regs -nowarn [format {u_product_dfi_reset/release_pipe[%d]} $bit]]]!=1} {
        error "Missing original DFI reset stage $bit"
    }
}
if {[llength [get_regs -nowarn {u_product_dfi_reset/g_falling_release$released_n}]]!=1} {
    error "Falling-edge DFI ASR stage changed"
}
if {[llength [get_regs -nowarn {u_product_dfi_reset/g_data_release$data_release_n[*]}]]} {
    error "Unexpected additional DFI reset distribution registers"
}
require_reference $owner hdr_eye_shared
require_reference [format {%s/member_history} $owner] {td_sdp_ram40(WIDTH=32,DEPTH=32,ADDR_WIDTH=5)}
foreach eye {0 1} {
    require_reference [format {%s/g_directory[%d]$directory} $owner $eye] hdr_pair_directory
}
foreach path {{g_s04$u_raw_service/u_pair_owner} {g_s04$u_raw_service/g_cam1_hdr$u_pair_owner} {g_s04$u_raw_service/g_mono_hdr_owner$u_pair_owner}} {
    if {[llength [get_cells -nowarn $path]]} {error "Duplicated HDR owner at $path"}
}
foreach {branch compact} {{g_dol2_capture$u_capture} 0 {g_cam1_hdr$u_capture} 1} {
    foreach {lane role} {0 1 1 2} {
        foreach leaf {writer ingress} {
            set path [format {g_s04$u_raw_service/%s/u_member%d/%s} $branch $lane $leaf]
            set match [get_cells -nowarn $path]
            if {[llength $match]!=1} {error "Missing capture member $path"}
            set model [get_property -nowarn REF_NAME $match]
            set value 0
            regexp {FIXED_HDR_ROLE=([0-9]+)} $model all value
            puts "CAMERA_HDR_CELL $path $model"
            if {$value!=($compact?$role:0)} {error "Wrong capture format for $path"}
            set packed 0
            regexp {COMPACT_CAPTURE_HEADER=([0-9]+)} $model all packed
            if {$packed!=(!$compact)} {error "Wrong generic metadata transport for $path"}
        }
    }
}
set pipeline {g_preprocess$g_live_f21$u_live/u_pipeline}
require_reference [format {%s/g_dehaze$u_restore} $pipeline] {dehaze_dcp_restore4(EXTERNAL_DARK_ENABLE=1)}
set hist_path [format {%s/g_full_preprocess$u_hist} $pipeline]
set hist_cells [get_cells -nowarn $hist_path]
set hist_model [get_property -nowarn REF_NAME $hist_cells]
puts "CAMERA_HDR_CELL $hist_path $hist_model"
if {[llength $hist_cells]!=1 || ![string match {preprocess_hist_eq4(*STEREO_HISTORY_ENABLE=1*} $hist_model]} {
    error "Shared stereo histogram missing at $hist_path"
}
foreach member {long short} {
    set fifo_path [format {g_hdr_source$u_native_source/u_pair_reader/u_%s_fifo} $member]
    require_reference $fifo_path td_sdp_ram40
    require_reference [format {%s/u_configured_ip} $fifo_path] ram40_sdp_fixed
}
set pyramid [format {%s/g_full_preprocess$u_filter/pyramid} $pipeline]
foreach {scale depth} {half_service 480 quarter_service 240} {
    foreach bank {0 1} {
        set path [format {%s/%s/g_bank[%d]$ram} $pyramid $scale $bank]
        require_reference $path [format {preprocess_line_ram32x1024(DEPTH=%d)} $depth]
    }
    if {[llength [get_cells -nowarn [format {%s/%s/g_bank[2]$ram} $pyramid $scale]]]} {
        error "Third F22 row bank found in $scale"
    }
}
require_reference {u_jpeg_to_ddr/u_egress/g_staging$u_staging} {ddr_extension_staging_ram(RECORD_EXTENSION_WIDTH=16384,FIRST_FLIT_PRECHECKED=1)}
require_reference {u_jpeg_to_ddr/u_egress/g_staging$u_staging/g_sparse_v4_check$u_check} lane_sparse_extension_checker
require_reference {g_record_metadata$u_gate/u_store} {jpeg_record_metadata_store(RECORD_EXTENSION_WIDTH=16384,BORROW_PENDING_EXTENSION=1,STAGING_EXTENSION_ENABLE=1,STREAM_READ=1,BORROW_READ_IDENTITY=32'b01)}
if {[llength [get_cells -nowarn {g_record_metadata$u_gate/u_store/g_stream_read$append_word}]]} {
    error "Old metadata replay packer is still instantiated"
}
set config_path {g_configured_capture$g_job_config$u_job_config}
set config_cells [get_cells -nowarn $config_path]
set config_type [get_property -nowarn REF_NAME $config_cells]
puts "CAMERA_HDR_CELL $config_path $config_type"
if {[llength $config_cells]!=1 || ![string match {frame_job_config_cdc(EXT_WIDTH=214,*COMPACT_STAGE2_EXTENSION_ENABLE=1*} $config_type]} {
    error "Actual camera job does not enable the 374-bit PIX/DFI tuple"
}
foreach name {u_request u_ack} {
    require_reference [format {%s/%s} $config_path $name] {control_message_fifo_ip(MESSAGE_WIDTH=375,BORROW_SOURCE=1)}
}
foreach name {u_real_hdr_cycle u_cam1_hdr_cycle} {
    require_reference $name {real_hdr_pair_cycle_gate(EXTERNAL_PHASE_ENABLE=1)}
    for {set bit 0} {$bit<24} {incr bit} {
        if {[llength [get_regs -nowarn [format {%s/g_local_phase/phase[%d]} $name $bit]]]} {
            error "Duplicated local HDR timeout counter remains at $name"
        }
    }
}
set shared_phase_bits 0
for {set bit 0} {$bit<32} {incr bit} {
    set count [llength [get_regs -nowarn [format {shared_hdr_timeout_phase[%d]} $bit]]]
    if {$count!=($bit<24 ? 1 : 0)} {error "Shared HDR timeout phase width mismatch at bit $bit"}
    incr shared_phase_bits $count
}
puts "CAMERA_SHARED_HDR_PHASE_BITS $shared_phase_bits"
require_reference {g_hdr_source$u_decode_service/u_decoder} {shared_raw10_decoder_masked(BYTE_COUNT_WIDTH=24,GROUP_COUNT_WIDTH=21)}
require_reference {u_jpeg/stream$u_quant} {jpeg_quant_stream(MAX_WIDTH=3840,MAX_HEIGHT=2160)}
require_reference {u_jpeg/u_entropy} {jpeg_entropy(STREAM_INPUT_ENABLE=1,RESTART_ENABLE=1,COEFF_BANKED_STORAGE_ENABLE=1)}
require_reference {u_jpeg/stream$u_dct/u_shared} {jpeg_fdct1d(TAG_WIDTH=5,INPUT_SAMPLE_WIDTH=10)}
require_reference {g_record_format$u_format/command_fifo} {control_message_fifo_ip(MESSAGE_WIDTH=96,BORROW_SOURCE=1)}
require_reference {g_record_format$u_format/ack_fifo} {control_message_fifo_ip(MESSAGE_WIDTH=131,BORROW_SOURCE=1)}
require_reference {g_private_processing$u_processing/u_job_service/u_scheduler} {raw_hdr_phase_scheduler4(NORMAL_REPLAY_ENABLE=1,NORMAL_SINGLE_MEMBER=1)}
foreach client {0 1} {
    foreach lane {0 1 2 3} {
        require_reference [format {u_ddr_store/g_hdr_shared$u_arbiter/u_response_fifo%d/g_lane[%d]$memory} $client $lane] {td_sdp_ram40(DEPTH=16,ADDR_WIDTH=4)}
    }
}
foreach lane {0 1 2 3} {
    require_reference [format {%s/g_full_preprocess$u_filter/adapter/u_gauss/g_dsp_sum[%d]$u_horizontal} $pipeline $lane] fdct_mac19s14s_z33s_p34_m1p1
}
require_reference {g_production$g_status_uart$u_observer} {uart_status_observer(CFG_DIAG_ENABLE=1,CFG_FRAME_VERSION=4,JOB_PAGE_ENABLE=1,JOB_SYS_CONFIG_ENABLE=1)}
require_reference {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain} paired_raw_capture_drain_cdc
require_reference [format {%s/g_full_preprocess$u_filter/lane/worker} $pipeline] lane_ridge_candidates1_lutram
require_reference [format {%s/g_full_preprocess$u_filter/lane/fifo} $pipeline] {lane_quarter_fifo4_to1(CLEAR_SUPPRESS_VALID=0)}
require_reference {u_pixel_reset} {reset_release_sync_data(DATA_RESET_COPIES=7)}
foreach path {{g_config$u_config/u_pixel_reset}} {
    require_reference $path {reset_release_sync(FALLING_RELEASE=1)}
}
if {[llength [get_cells -nowarn {u_pixel_reset_global}]]} {
    error "Pixel reset must not use a BUFG"
}
set reset_branches [get_regs -nowarn {g_pixel_reset_branch*release_n*}]
if {[llength $reset_branches]!=4} {error "Missing four local falling-edge PIX reset branches: $reset_branches"}
set ddr_hold_targets 0
foreach beat {0 1 2 3 4 5 6 7} {
    for {set lane 0} {$lane<16} {incr lane} {
        set bit [expr {72*$beat+$lane}]
        set path [format {u_ddr_store/u_ddr/u_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_ppc/u_ddrppc.dfi_wrdata[%d]} $bit]
        if {[llength [get_pins -nowarn $path]]!=1} {error "DDR hold target missing: $path"}
        incr ddr_hold_targets
    }
}
puts "CAMERA_RESET_DDR_TARGETS branches=[llength $reset_branches] ddr_bits=$ddr_hold_targets"
foreach {scale width height} {half_service 960 540 quarter_service 480 270} {
    set path [format {%s/%s} $pyramid $scale]
    set cells [get_cells -nowarn $path]
    set model [get_property -nowarn REF_NAME $cells]
    puts "CAMERA_HDR_CELL $path $model"
    if {[llength $cells]!=1 || ![string match "*FIXED_WIDTH=$width*FIXED_HEIGHT=$height*" $model]} {
        error "Fixed F22 geometry missing at $path"
    }
}
set counter_bits 0
foreach branch {{g_dol2_capture$u_capture} {g_cam1_hdr$u_capture}} {
    foreach lane {0 1} {
        set base [format {g_s04$u_raw_service/%s/u_member%d} $branch $lane]
        foreach name {produced consumed frozen_produced fence_count} {
            # Elaborated vector registers require explicit bit queries in TD.
            for {set bit 0} {$bit<32} {incr bit} {
                set regs [get_regs -nowarn [format {%s/%s[%d]} $base $name $bit]]
                set expected [expr {$bit<10 ? 1 : 0}]
                if {[llength $regs]!=$expected} {error "Private fence width mismatch: $base/$name bit $bit"}
                incr counter_bits [llength $regs]
            }
        }
    }
}
puts "CAMERA_PRIVATE_FENCE_BITS $counter_bits"
foreach pixel {0 1 2 3} {
    foreach channel {0 1 2} {
        set path [format {u_camera/u_pipeline/g_internal_isp$wide$u_isp/u_color/lane[%d]$g_identity$wb[%d]$u_gain_round} $pixel $channel]
        require_reference $path fdct_mac19s14s_z33s_p34_m1p1
    }
}
require_reference {g_record_builder$u_builder} {frame_record_extension_builder(NEUTRAL_STATS_ENABLE=1,SEPARATE_DATA_RESET=1,RUNTIME_NEUTRAL_SKIP_ENABLE=1)}
foreach branch {{g_dol2_capture$u_capture} {g_cam1_hdr$u_capture}} {
    foreach lane {0 1} {
        require_reference [format {g_s04$u_raw_service/%s/u_member%d/dr} $branch $lane] {reset_release_sync(FALLING_RELEASE=1)}
    }
}
require_reference {u_soft_reset_fence/u_user_cold_reset} {reset_release_sync(FALLING_RELEASE=1)}
# Check the selected new local data qualifiers explicitly. A ready output may
# not use the falling-edge reset itself as the launch of a long data cone.
set qual_regs [list {g_hdr_source$u_decode_service/ready_run} \
    {g_s04$u_raw_service/g_stereo$u_store/u_owner/u_directory/ready_run} \
    {u_ddr_to_pcie/beats_empty} {u_ddr_to_pcie/tail_expected}]
foreach eye {0 1} {
    lappend qual_regs [format {%s/g_directory[%d]$directory/ready_run} $owner $eye]
}
foreach path $qual_regs {
    if {[llength [get_regs -nowarn $path]]!=1} {error "Missing local qualification register: $path"}
    puts "CAMERA_TIMING_QUALIFIER $path"
}
# The BAR's falling release drives only its local state ASR, never child data.
set bar_phase [get_regs -nowarn {g_config$u_config/u_bar/state_reset_n}]
if {[llength $bar_phase]!=1} {error "Missing local BAR state reset phase"}
puts "CAMERA_BAR_STATE_PHASE [llength $bar_phase]"
foreach name {u_allocation_generation u_ready_identity u_query_identity} {
    set path [format {u_ddr_store/g_ring_store$u_store/%s} $name]
    set cells [get_cells -nowarn $path]
    set model [get_property -nowarn REF_NAME $cells]
    puts "CAMERA_HDR_CELL $path $model"
    if {[llength $cells]!=1 || ![string match {PH1_LOGIC_DRAM*} $model]} {
        error "Missing ring identity DRAM: $path"
    }
}
foreach camera {u_camera u_camera1} {
    set cfg [get_cells -nowarn $camera/u_config]
    set model [get_property -nowarn REF_NAME $cfg]
    puts "CAMERA_RAW_SENSOR $camera $model"
    if {[llength $cfg]!=1 || ![string match {imx415_sensor_config*} $model]} {error "Missing shared sensor sequencer"}
    require_reference $camera/u_config/u_i2c {camera_i2c_write(HALF_PERIOD=125)}
    if {[llength [get_cells -nowarn $camera/u_hdr_config]]} {error "Duplicated HDR configuration remains"}
}
require_reference u_raw_formatter {raw_video_record_formatter(SEPARATE_DATA_RESET=1)}
foreach path {
    {g_s04$u_raw_service/g_dol2_capture$u_capture/arbiter}
    {g_s04$u_raw_service/g_cam1_hdr$u_capture/arbiter}
    {g_s04$u_raw_service/g_cam1_hdr$u_eye_write_arbiter}
} {
    require_reference $path {dol2_axi_write_arbiter(SEPARATE_DATA_RESET=1)}
}
set raw_reader [get_cells -nowarn {g_s04$u_raw_service/g_stereo$u_store/u_reader}]
set raw_reader_model [get_property -nowarn REF_NAME $raw_reader]
puts "CAMERA_RAW_READER $raw_reader_model"
if {[llength $raw_reader]!=1 || ![string match {*EXTERNAL_DECODER=1*VERIFY_DECODE_ACTIVE=1*} $raw_reader_model]} {error "RAW/JPEG reader startup guard missing"}
require_reference {g_production$g_status_uart$u_field_diagnostics} camera_field_diagnostics
set uart_model [get_property -nowarn REF_NAME [get_cells -nowarn {g_production$g_status_uart$u_observer}]]
if {![string match {*CFG_FRAME_VERSION=4*} $uart_model] || ![string match {*JOB_SYS_CONFIG_ENABLE=1*} $uart_model]} {
    error "Field UART page version/system capture missing"
}
set cfg_model [get_property -nowarn REF_NAME [get_cells -nowarn {g_config$u_config}]]
puts "CAMERA_CFG_SERVICE_MODEL $cfg_model"
if {![regexp {APPLY_SOURCE_FAULT_ENABLE=(1|32'b0*1)(,|\))} $cfg_model]} {error "Physical CFG negative terminal missing"}
if {[llength [get_regs -nowarn {g_preprocess$g_live_f21$u_live/u_pipeline/g_dehaze$u_restore/clear_pending}]]!=1} {
    error "Dehaze local cancel flush boundary missing"
}
set rate_owner {g_stereo_control$u_stereo_control}
foreach name {cfg_request_sync cfg_ack_sync} {
    foreach bit {0 1} {
        set path [format {%s/%s[%d]} $rate_owner $name $bit]
        if {[llength [get_regs -nowarn $path]]!=1} {error "Missing rate FIRST/second stage: $path"}
    }
}
foreach bit {0 1 2} {
    foreach name {o_cfg_sdr_profile o_pixel_sdr_profile} {
        set path [format {%s/%s[%d]} $rate_owner $name $bit]
        if {[llength [get_regs -nowarn $path]]!=1} {error "Missing held rate recipient: $path"}
    }
    foreach camera {u_camera u_camera1} {
        foreach name {sdr_profile_cfg sdr_profile_pixel} {
            set path [format {%s/%s[%d]} $camera $name $bit]
            if {[llength [get_regs -nowarn $path]]!=1} {error "Missing sensor profile boundary: $path"}
        }
    }
}
foreach camera {u_camera u_camera1} {
    if {[llength [get_regs -nowarn $camera/sdr_profile_ready]]!=1} {error "Missing held profile validity"}
    foreach old {slow_request_cfg slow_mode_cfg slow_mode_pixel} {
        if {[llength [get_regs -nowarn [format {%s/%s*} $camera $old]]]} {error "Obsolete scalar rate CDC remains"}
    }
}
puts "CAMERA_RATE_PROFILE_BOUNDARIES_PASS"
proc require_profile {path prefix fragments} {
    set cells [get_cells -nowarn $path]
    if {[llength $cells]!=1} {error "Missing UHD profile cell: $path"}
    set ref [get_property -nowarn REF_NAME $cells]
    if {![string match "$prefix*" $ref]} {error "Unexpected UHD reference: $ref"}
    foreach fragment $fragments {
        if {[string first $fragment $ref]<0} {error "Missing parameter $fragment in $path: $ref"}
    }
    puts "CAMERA_UHD_PROFILE $path $ref"
}
require_profile {g_stereo_control$u_stereo_control} stereo_cold_control {UHD_ENABLE=1}
require_profile {g_config$u_config} mono_config_service_v2 {UHD_COLOR_ENABLE=1 UHD_PREPROCESS_ENABLE=1 QUALITY_CONTROL_ENABLE=1}
require_profile {g_config$u_config/u_engine} mono_config_engine_v2 {FRAME_APPLY_REQUIRE_IDLE=0 UHD_COLOR_ENABLE=1 UHD_PREPROCESS_ENABLE=1 QUALITY_CONTROL_ENABLE=1}
require_profile {g_config$u_config/u_bar/u_validator} mono_config_scan_v2 {UHD_COLOR_ENABLE=1 UHD_PREPROCESS_ENABLE=1 QUALITY_CONTROL_ENABLE=1}
require_profile {u_camera/u_pipeline} physical_camera_rgb_pipeline {REPLAY_UHD_ENABLE=1 LIVE_UHD_ENABLE=1}
require_profile {u_jpeg} jpeg_encoder_top {DUAL_GEOMETRY_ENABLE=1}
require_profile {u_jpeg/u_mcu} jpeg_mcu_422 {ROW_STREAM_ENABLE=1 DUAL_GEOMETRY_ENABLE=1}
require_profile {g_hdr_source$u_native_source/g_shared_native$u_transport} hdr_raw14_shared_transport4 {SINK_MAX_WIDTH=3840 SINK_MAX_HEIGHT=2160}
require_profile {g_preprocess$g_live_f21$u_live} preprocess_live_f21_service4 {UHD_COLOR_BYPASS_ENABLE=1 UHD_PREPROCESS_ENABLE=1}
foreach name {active_uhd o_pixel_uhd o_dfi_uhd} {
    set path [format {%s/%s} $rate_owner $name]
    if {[llength [get_regs -nowarn $path]]!=1} {error "Missing cold geometry recipient: $path"}
}
foreach path {{g_stereo_control$u_stereo_control/held_profile[14]} admitted_uhd} {
    if {[llength [get_regs -nowarn $path]]!=1} {error "Missing frame-frozen geometry: $path"}
}
puts "CAMERA_UHD_SHARED_GEOMETRY_PASS"
foreach path {{u_ddr_store/g_ring_store$u_record_owner_reset} {u_jpeg_to_ddr/u_source_reset} {g_private_processing$u_source_events/u_pixel_reset} {g_private_processing$u_original_source/u_pixel_reset}} {
    require_reference $path {reset_release_sync_data(DATA_RESET_COPIES=0,FALLING_RELEASE=1)}
}
require_profile {u_ddr_store/g_ring_store$u_store} jpeg_frame_ring {SEPARATE_DATA_RESET=1}
require_profile {u_jpeg_to_ddr/u_ingress} ordered_frame_ingress {SEPARATE_DATA_RESET=1}
foreach branch {{g_dol2_capture$u_capture} {g_cam1_hdr$u_capture}} {
    foreach member {0 1} {
        require_reference [format {g_s04$u_raw_service/%s/u_member%d/pr} $branch $member] {reset_release_sync(FALLING_RELEASE=1)}
    }
}
require_profile {g_private_processing$u_original_source/u_original_cleanup} hdr_pair_product_abort_drain4 {SYNC_CLEAR_ENABLE=1 FALLING_INPUT_RESET=1}
puts "CAMERA_FUSION_LOCAL_RESET_PHASE_PASS"
set tone_path {u_camera/u_pipeline/g_internal_isp$wide$u_isp/u_color/u_tone96}
require_reference $tone_path hdr_tone96_shared4
foreach lane {0 1} {
    foreach part {low high} {
        set path [format {%s/g_pixel_lane[%d]$u_rom_%s} $tone_path $lane $part]
        set cells [get_cells -nowarn $path]
        if {[llength $cells]!=1} {error "Missing two-pixel Tone ROM: $path"}
        puts "CAMERA_TONE2_ROM $path [get_property -nowarn REF_NAME $cells]"
    }
    set path [format {%s/g_pixel_lane[%d]$u_highlight_floor} $tone_path $lane]
    if {[llength [get_cells -nowarn $path]]!=1} {error "Missing highlight arithmetic lane: $path"}
}
foreach lane {0 1 2 3} {
    require_reference [format {g_hdr_source$u_native_source/u_pair_reader/u_cursor/u_response_buffer/g_lane[%d]$memory} $lane] {td_sdp_ram40(DEPTH=16,ADDR_WIDTH=4)}
}
require_profile {g_production$g_status_uart$u_observer/g_cfg_diag$g_domain[1]$u_snapshot} cfg_diag_snapshot {DATA_WIDTH=256}
foreach lane {0 1 2 3} {
    set path [format {g_hdr_source$u_native_source/u_pair_reader/u_merge/g_lane[%d]$u_blend} $lane]
    if {[llength [get_cells -nowarn $path]]!=1} {error "Missing HDR MAC lane: $path"}
}
puts "CAMERA_FUSION_HDR_THROUGHPUT_PASS"
puts "CAMERA_RAW_HDR_HIERARCHY_PASS"
exit 0
