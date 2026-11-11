# Read-only query of the existing elaborated candidate. No synthesis/P&R.
cd [file normalize [file join [file dirname [info script]] ../al]]
import_device ph1_90.db -package PH1A90SEG324 -speed 2
import_db rfcamera_fusion_r1_Runs/syn_1/rfcamera_fusion_r1_elaborate.db
foreach path {
    u_jpeg u_jpeg/u_mcu u_camera/u_pipeline
    {g_stereo_control$u_stereo_control}
    {g_config$u_config} {g_config$u_config/u_engine}
    {g_s04$u_raw_service}
    {g_hdr_source$u_native_source/u_transport}
    {g_preprocess$g_live_f21$u_live}
    {g_record_builder$u_builder}
} {
    set cells [get_cells -nowarn $path]
    puts "UHD_CELL $path count=[llength $cells] ref=[get_property -nowarn REF_NAME $cells]"
}
foreach path {
    {g_stereo_control$u_stereo_control/held_profile[14]}
    {g_stereo_control$u_stereo_control/active_uhd}
    {g_stereo_control$u_stereo_control/o_pixel_uhd}
    {g_stereo_control$u_stereo_control/o_dfi_uhd}
    admitted_uhd
} {
    puts "UHD_REG $path count=[llength [get_regs -nowarn $path]]"
}
exit 0
