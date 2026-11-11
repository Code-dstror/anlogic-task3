param([Parameter(Mandatory)][string]$RunName)
$ErrorActionPreference = 'Stop'
if ($RunName -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { throw 'Specify a new simple run name' }
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$relative = "tmp/fusion_product_projection/$RunName"
$out = Join-Path $root $relative
if (Test-Path -LiteralPath $out) { throw "Projection already exists at $out" }
New-Item -ItemType Directory -Path $out | Out-Null
$changes = [Collections.Generic.List[object]]::new()
$origins = [Collections.Generic.List[object]]::new()
$generated = [Collections.Generic.List[string]]::new()
$utf8 = [Text.UTF8Encoding]::new($false)

function TextHash([string]$Value) {
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($hasher.ComputeHash($utf8.GetBytes($Value))).ToLowerInvariant() }
    finally { $hasher.Dispose() }
}
function Exact([string]$Body,[string]$Needle,[string]$Replacement,[string]$Label) {
    $pos = $Body.IndexOf($Needle,[StringComparison]::Ordinal)
    if ($pos -lt 0 -or $Body.IndexOf($Needle,$pos+$Needle.Length,[StringComparison]::Ordinal) -ge 0) {
        throw "Missing or ambiguous projection anchor $Label"
    }
    $changes.Add([ordered]@{
        name=$Label; before_sha256=(TextHash $Needle); after_sha256=(TextHash $Replacement)
        before=$Needle; after=$Replacement
    })
    return $Body.Substring(0,$pos)+$Replacement+$Body.Substring($pos+$Needle.Length)
}
function Source([string]$Name) {
    $path = "src_fpga/rtl/$Name.v"
    $file = Join-Path $root $path
    $origins.Add([ordered]@{path=$path; sha256=(Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant()})
    return [IO.File]::ReadAllText($file).Replace("`r`n","`n")
}
function Mask([string]$Body) {
    return [regex]::Replace($Body,'(?s)//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"',{
        param($token) [regex]::Replace($token.Value,'[^\r\n]',' ')
    })
}
function End-Group([string]$Masked,[int]$At) {
    if ($Masked[$At] -ne '(') { throw 'Expected open parenthesis' }
    $level=1
    for ($cursor=$At+1;$cursor -lt $Masked.Length;$cursor++) {
        if ($Masked[$cursor] -eq '(') { $level++ }
        if ($Masked[$cursor] -eq ')') { $level--; if ($level -eq 0) { return $cursor } }
    }
    throw 'Unclosed parenthesis'
}
function Skip-Space([string]$Masked,[int]$At) {
    while ($At -lt $Masked.Length -and [char]::IsWhiteSpace($Masked[$At])) { $At++ }
    return $At
}
function Header([string]$Body,[string]$Unit) {
    $masked=Mask $Body
    $decl=[regex]::Match($masked,"(?m)^module\s+$Unit\b")
    if (!$decl.Success) { throw "No module declaration for $Unit" }
    $start=Skip-Space $masked ($decl.Index+$decl.Length)
    if ($masked[$start] -eq '#') {
        $start=Skip-Space $masked ($start+1)
        $start=Skip-Space $masked ((End-Group $masked $start)+1)
    }
    return @{start=$decl.Index; close=(End-Group $masked $start)}
}
function Project-Header([string]$Body,[string]$Old,[string]$New,[string[]]$Ports) {
    $header=Header $Body $Old
    $oldText=$Body.Substring($header.start,$header.close-$header.start)
    $newText=$oldText.TrimEnd()+",`n    "+($Ports -join ",`n    ")+"`n"
    $newText=$newText.Replace("module $Old","module $New")
    return Exact $Body $oldText $newText "$Old module and fixture ports"
}
function Instance([string]$Body,[string]$Unit,[string]$Name) {
    $masked=Mask $Body
    $found=@()
    foreach ($candidate in [regex]::Matches($masked,"(?m)^[ \t]*$Unit\b")) {
        $cursor=Skip-Space $masked ($candidate.Index+$candidate.Length)
        if ($masked[$cursor] -eq '#') {
            $cursor=Skip-Space $masked ($cursor+1)
            $cursor=Skip-Space $masked ((End-Group $masked $cursor)+1)
        }
        $inst=[regex]::Match($masked.Substring($cursor),'^([A-Za-z_]\w*)\s*\(')
        if (!$inst.Success -or $inst.Groups[1].Value -cne $Name) { continue }
        $close=End-Group $masked ($cursor+$inst.Length-1)
        $semicolon=Skip-Space $masked ($close+1)
        if ($masked[$semicolon] -ne ';') { throw "No instance terminator for $Name" }
        $found+=@{text=$Body.Substring($candidate.Index,$semicolon-$candidate.Index+1); close=$close-$candidate.Index}
    }
    if ($found.Count -ne 1) { throw "Missing or ambiguous instance $Unit.$Name" }
    return $found[0]
}
function Replace-Instance([string]$Body,[string]$Unit,[string]$Name,[string]$Boundary) {
    $old=Instance $Body $Unit $Name
    return Exact $Body $old.text $Boundary "$Unit.$Name boundary"
}
function Project-Instance([string]$Body,[string]$Old,[string]$Name,[string]$New,[string[]]$Ports) {
    $inst=Instance $Body $Old $Name
    $bind=@($Ports | ForEach-Object {
        $port=([regex]::Match($_,'[A-Za-z_]\w*$')).Value
        ".$port($port)"
    })
    $newText=$inst.text.Substring(0,$inst.close).TrimEnd()+",`n        "+($bind -join ",`n        ")+"`n    );"
    $newText=[regex]::Replace($newText,"(?m)^([ \t]*)$Old\b",('$1'+$New))
    return Exact $Body $inst.text $newText "$Old.$Name fixture ports"
}
function Override-Parameter([string]$Body,[string]$Unit,[string]$Name,[string]$Old,[string]$New) {
    $inst=Instance $Body $Unit $Name
    $edited=Exact $inst.text $Old $New "$Unit.$Name parameter"
    return $Body.Replace($inst.text,$edited)
}
function Emit([string]$Name,[string]$Body) {
    $file="$Name.v"
    [IO.File]::WriteAllText((Join-Path $out $file),"// Generated verification projection. See CONTRACT.md.`n"+$Body,$utf8)
    $generated.Add("$relative/$file")
}

$memPorts=@(
    'input wire i_mem_clk','input wire i_mem_ready','output wire o_mem_reset_n',
    'output wire [3:0] o_mem_awid','output wire [27:0] o_mem_awaddr',
    'output wire [7:0] o_mem_awlen','output wire [2:0] o_mem_awsize','output wire [1:0] o_mem_awburst',
    'output wire o_mem_awvalid','input wire i_mem_awready',
    'output wire [127:0] o_mem_wdata','output wire [15:0] o_mem_wstrb',
    'output wire o_mem_wlast','output wire o_mem_wvalid','input wire i_mem_wready',
    'input wire [3:0] i_mem_bid','input wire [1:0] i_mem_bresp','input wire i_mem_bvalid','output wire o_mem_bready',
    'output wire [3:0] o_mem_arid','output wire [27:0] o_mem_araddr',
    'output wire [7:0] o_mem_arlen','output wire [2:0] o_mem_arsize','output wire [1:0] o_mem_arburst',
    'output wire o_mem_arvalid','input wire i_mem_arready',
    'input wire [3:0] i_mem_rid','input wire [127:0] i_mem_rdata','input wire [1:0] i_mem_rresp',
    'input wire i_mem_rlast','input wire i_mem_rvalid','output wire o_mem_rready'
)
$hostPorts=@(
    'input wire i_host_clk','input wire i_host_link_up','input wire i_host_bme',
    'input wire [127:0] i_cq_data','input wire [3:0] i_cq_keep','input wire [87:0] i_cq_user',
    'input wire i_cq_last','input wire i_cq_valid','output wire o_cq_ready',
    'output wire [127:0] o_cc_data','output wire [3:0] o_cc_keep','output wire [32:0] o_cc_user',
    'output wire o_cc_last','output wire o_cc_valid','input wire i_cc_ready',
    'output wire [127:0] o_tlp_data','output wire [63:0] o_tlp_address',
    'output wire [7:0] o_tlp_byte_enable','output wire [12:0] o_tlp_byte_length',
    'output wire [1:0] o_tlp_format','output wire [9:0] o_tlp_tag',
    'output wire o_tlp_header_valid','output wire o_tlp_data_valid','output wire o_tlp_end','input wire i_tlp_halt',
    'input wire [127:0] i_rc_data','input wire [3:0] i_rc_keep','input wire [74:0] i_rc_user',
    'input wire i_rc_last','input wire i_rc_valid','output wire o_rc_ready'
)
$ispPorts=@(
    'output wire o_isp_reset_n','output wire [12:0] o_isp_width','output wire [12:0] o_isp_height',
    'output wire [55:0] o_isp_raw_data','output wire o_isp_raw_valid','output wire o_isp_raw_sof',
    'output wire o_isp_raw_eol','input wire i_isp_raw_ready','input wire i_isp_idle',
    'input wire [95:0] i_isp_rgb','input wire i_isp_rgb_valid','input wire i_isp_rgb_sof',
    'input wire i_isp_rgb_eol','output wire o_isp_rgb_ready'
)
$cameraPorts=@(
    'input wire [39:0] i_crop_data','input wire i_crop_valid','output wire o_crop_ready',
    'input wire i_crop_sof','input wire i_crop_eol','input wire i_crop_abort',
    'input wire [31:0] i_crop_sequence','input wire i_crop_identity_valid',
    'input wire i_event_valid','output wire o_event_ready','input wire [1:0] i_event_kind',
    'input wire i_event_ok','input wire [3:0] i_event_error',
    'input wire [31:0] i_event_sequence','input wire i_event_identity_valid',
    'output wire [2:0] o_sensor_profile','input wire [2:0] i_sensor_profile',
    'input wire i_sensor_config_done','input wire i_sensor_config_error','input wire i_sensor_mode_running'
)
$obsPorts=@(
    'output wire o_pixel_reset_n','output wire o_dfi_reset_n','output wire o_user_reset_n',
    'output wire o_cfg_ack_fire','output wire o_cfg_ack_ok','output wire [31:0] o_cfg_ack_session','output wire [31:0] o_cfg_ack_epoch',
    'output wire o_cold_config_sof','output wire o_uhd_pixel','output wire o_capture_enabled','output wire o_capture_frame_accept',
    'output wire o_session_armed','output wire o_buffer_armed',
    'output wire o_replay_source_fire','output wire o_replay_source_ok','output wire [63:0] o_replay_source_tag',
    'output wire o_jpeg_source_done','output wire o_jpeg_source_failed',
    'output wire o_jpeg_start_fire','output wire [15:0] o_jpeg_start_width','output wire [15:0] o_jpeg_start_height',
    'output wire [31:0] o_jpeg_start_sequence',
    'output wire o_jpeg_result_fire','output wire o_jpeg_result_ok','output wire [24:0] o_jpeg_result_length',
    'output wire o_writer_ack_fire','output wire o_writer_ack_ok','output wire [31:0] o_writer_ack_sequence',
    'output wire o_ticket_result','output wire o_ticket_error','output wire [63:0] o_ticket_job',
    'output wire o_raw_slot_retired','output wire o_raw_empty',
    'output wire o_record_offer','output wire o_record_retire_fire',
    'output wire o_ring_retire_response_valid','output wire [3:0] o_ring_retire_response_code',
    'output wire o_record_quiet','output wire o_fault'
)

$ddr=Source 'ddr3_jpeg_store'
$ddr=Project-Header $ddr 'ddr3_jpeg_store' 'uhd_short_ddr_store' $memPorts
$ddr=Replace-Instance $ddr 'ui_ddr' 'u_ddr' @'
    // Only the DDR UI hard block is replaced by the external AXI boundary.
    assign o_dfi_clk=i_mem_clk;
    assign o_ddrphy_rst_n=i_sys_rst_n&&i_session_rst_n;
    assign o_pll_locked=i_mem_ready;
    assign o_ddr_init_cal_done=i_mem_ready;
    assign o_ddr_init_cal_err=0;
    assign o_ddr_init_cal_step=0;
    assign o_mem_reset_n=o_ddrphy_rst_n;
    assign {o_ddr_ck_p,o_ddr_ck_n,o_ddr_reset_n,o_ddr_cke,o_ddr_odt,o_ddr_cs_n,
        o_ddr_ras_n,o_ddr_cas_n,o_ddr_we_n,o_ddr_ba,o_ddr_addr}=0;
    assign {o_mem_awid,o_mem_awaddr,o_mem_awlen,o_mem_awsize,o_mem_awburst,o_mem_awvalid}=
        {awid,awaddr,awlen,awsize,awburst,awvalid};
    assign awready=i_mem_awready;
    assign {o_mem_wdata,o_mem_wstrb,o_mem_wlast,o_mem_wvalid}={wdata,wstrb,wlast,wvalid};
    assign wready=i_mem_wready;
    assign {bid,bresp,bvalid}={i_mem_bid,i_mem_bresp,i_mem_bvalid};
    assign o_mem_bready=bready;
    assign {o_mem_arid,o_mem_araddr,o_mem_arlen,o_mem_arsize,o_mem_arburst,o_mem_arvalid}=
        {arid,araddr,arlen,arsize,arburst,arvalid};
    assign arready=i_mem_arready;
    assign {rid,rdata,rresp,rlast,rvalid}={i_mem_rid,i_mem_rdata,i_mem_rresp,i_mem_rlast,i_mem_rvalid};
    assign o_mem_rready=rready;
'@
Emit 'uhd_short_ddr_store' $ddr

$endpoint=Source 'c2h_pcie_endpoint'
$endpoint=Project-Header $endpoint 'c2h_pcie_endpoint' 'uhd_short_endpoint' $hostPorts
$pllStart=$endpoint.IndexOf('    sys_pll_125m_25m clocks(')
$pllEnd=$endpoint.IndexOf('    // This reset never follows bridge')
if ($pllStart -lt 0 -or $pllEnd -lt $pllStart) { throw 'PCIe hard clock anchors changed' }
$endpoint=Exact $endpoint ($endpoint.Substring($pllStart,$pllEnd-$pllStart)) "    assign pll_lock=i_host_link_up;`n" 'PCIe hard PLL and stabilization'
$endpoint=Replace-Instance $endpoint 'camera_pcie_hard_port' 'bridge' @'
    // Native transport, its CQ/CC translation and checked fence stay in RTL.
    assign o_user_clk=i_host_clk;
    assign o_link_up=i_pcie_mperst&&i_host_link_up;
    assign physical_link_up=o_link_up;
    assign core_reset_n=o_link_up;
    assign bme={1'b0,i_host_bme};
    assign {completion_fault,completion_incident,o_pcie_txp,o_pcie_txn}=0;
    assign {cq_data,cq_keep,cq_user,cq_last,cq_valid}={i_cq_data,i_cq_keep,i_cq_user,i_cq_last,i_cq_valid};
    assign o_cq_ready=cq_ready;
    assign {o_cc_data,o_cc_keep,o_cc_user,o_cc_last,o_cc_valid}={cc_data,cc_keep,cc_user,cc_last,cc_valid};
    assign cc_ready=i_cc_ready;
    assign {o_tlp_data,o_tlp_address,o_tlp_byte_enable,o_tlp_byte_length,o_tlp_format,o_tlp_tag,
        o_tlp_header_valid,o_tlp_data_valid,o_tlp_end}=
        {rq_data,native_address,native_be,native_length,native_format,native_tag,native_hv,native_dv,native_eot};
    assign native_halt=i_tlp_halt;
    assign {rc_data,rc_keep,rc_user,rc_last,rc_valid}={i_rc_data,i_rc_keep,i_rc_user,i_rc_last,i_rc_valid};
    assign o_rc_ready=rc_ready;
'@
Emit 'uhd_short_endpoint' $endpoint

$product=Source 'product_pcie_transport'
$product=Project-Header $product 'product_pcie_transport' 'uhd_short_product' $hostPorts
$product=Project-Instance $product 'c2h_pcie_endpoint' 'endpoint' 'uhd_short_endpoint' $hostPorts
Emit 'uhd_short_product' $product

$rgb=Source 'physical_camera_rgb_pipeline'
$rgb=Project-Header $rgb 'physical_camera_rgb_pipeline' 'uhd_short_camera_rgb' $ispPorts
$rgb=Replace-Instance $rgb 'physical_camera_crop' 'u_crop' @'
    // Input at the already cropped RAW4 boundary.
    assign {cropped_data,cropped_valid,cropped_sof,cropped_eol,crop_abort}=
        {i_raw_data,i_raw_valid,i_raw_sof,i_raw_eol,i_raw_abort};
    assign o_raw_ready=cropped_ready;
    assign o_cropped_raw_sequence=i_raw_sequence;
    assign o_cropped_raw_identity_valid=i_raw_identity_valid;
'@
# Keep the actual shared ISP and its accepted-SOF quality snapshot.
$rgb=Exact $rgb "(job_replay_uhd ? 13'd3840 : FRAME_WIDTH)" "(job_replay_uhd ? 13'd480 : 13'd240)" 'Real ISP short width'
$rgb=Exact $rgb "(job_replay_uhd ? 13'd2160 : FRAME_HEIGHT)" "(job_replay_uhd ? 13'd32 : 13'd16)" 'Real ISP short height'
$rgb=Exact $rgb "endmodule`n" @'
    assign o_isp_reset_n=g_internal_isp.wide.core_run;
    assign o_isp_width=job_replay_uhd ? 13'd480 : 13'd240;
    assign o_isp_height=job_replay_uhd ? 13'd32 : 13'd16;
    assign {o_isp_raw_data,o_isp_raw_valid,o_isp_raw_sof,o_isp_raw_eol}=
        {g_internal_isp.wide.input_data,g_internal_isp.wide.input_valid&&g_internal_isp.wide.core_run,g_internal_isp.wide.input_sof,g_internal_isp.wide.input_eol};
    assign o_isp_rgb_ready=g_internal_isp.wide.core_rgb_ready;
    // Legacy external ISP inputs are unused; this fixture instantiates the real core.
endmodule
'@ 'Passive real ISP input observations'
$rgb=Exact $rgb "(job_replay_uhd ? 13'd2159 : FRAME_HEIGHT - 13'd1)" "(job_replay_uhd ? 13'd31 : 13'd15)" 'Replay RGB height at short raster'
Emit 'uhd_short_camera_rgb' $rgb

$camera=Source 'real_hdr_camera_observe_axis'
$camera=Project-Header $camera 'real_hdr_camera_observe_axis' 'uhd_short_camera' ($cameraPorts+$ispPorts)
$camera=Project-Instance $camera 'physical_camera_rgb_pipeline' 'u_pipeline' 'uhd_short_camera_rgb' $ispPorts
$camera=Exact $camera '    `include "camera_physical_capture.vh"' @'
    wire raw_ready,pipeline_raw_ready;
    wire [1:0] pixel_reset={2{i_reset_n}};
    wire [39:0] raw_data=i_crop_data;
    wire raw_valid=i_crop_valid,raw_sof=i_crop_sof,raw_eol=i_crop_eol,raw_abort=i_crop_abort;
    wire [31:0] raw_sequence=i_crop_sequence;
    wire raw_identity_valid=i_crop_identity_valid;
    wire receive_fault=1'b0;
    assign o_crop_ready=i_reset_n&&raw_ready;
    assign o_sensor_profile=i_sdr_profile_cfg;
    assign o_sdr_profile=i_sensor_profile;
    assign o_config_done=i_sensor_config_done;
    assign o_config_error=i_sensor_config_error;
    assign o_mode_running=i_sensor_mode_running;
    assign o_phy_ready=i_sensor_mode_running;
    assign o_hdr_mode=0;assign o_hdr_stable=0;
    assign {m_frame_event_valid,m_frame_event_kind,m_frame_event_ok,m_frame_event_error,
        m_frame_event_sequence,m_frame_event_identity_valid}=
        {i_event_valid,i_event_kind,i_event_ok,i_event_error,i_event_sequence,i_event_identity_valid};
    assign o_event_ready=i_reset_n&&m_frame_event_ready;
    assign o_rx_diag_word_clk=i_pixel_clk;
    assign {m_hdr0_data,m_hdr1_data,m_hdr0_valid,m_hdr1_valid,o_rx_diag_word,o_rx_diag_cfg}=0;
    assign {o_rx_trace_sample,o_rx_trace_trigger,o_rx_trace_cohort_n,o_rx_trace_enable}=0;
    assign {o_ecc_errors,o_crc_errors,o_overflows,o_format_errors,o_source_identity_fault,o_delay_ready}=0;
    assign {cam_scl,cam_mclk,cam_xclr}=0;
    always @(posedge i_pixel_clk)begin
        o_delay_debug<=0;o_delay_window<=0;o_delay_status_valid<=0;
    end
'@ 'CAM0 cropped RAW4 and event boundary'
Emit 'uhd_short_camera' $camera

$originalTop=Source 'anlogic2026'
$top=Project-Header $originalTop 'anlogic2026' 'uhd_integration_fixture' (
    @('input wire i_pixel_clk','input wire i_clock_ready')+$cameraPorts+$ispPorts+$memPorts+$hostPorts+$obsPorts
)
$top=Exact $top 'parameter integer READONLY_UART_ENABLE = 1' 'parameter integer READONLY_UART_ENABLE = 0' 'Passive UART excluded from short fixture'
$top=Exact $top 'localparam integer UHD_WIDTH = 3840, UHD_HEIGHT = 2160;' @'
localparam integer UHD_WIDTH = 480, UHD_HEIGHT = 32;
    localparam integer SHORT_BASE_WIDTH=240, SHORT_BASE_HEIGHT=16;
'@ 'Short raster constants'
$top=Exact $top ': FRAME_WIDTH[15:0];' ': SHORT_BASE_WIDTH[15:0];' 'Admitted base width on fixture'
$top=Exact $top ': FRAME_HEIGHT[15:0];' ': SHORT_BASE_HEIGHT[15:0];' 'Admitted base height on fixture'
$top=Override-Parameter $top 'full_raw_store' 'u_raw_service' '.WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT)' '.WIDTH(SHORT_BASE_WIDTH),.HEIGHT(SHORT_BASE_HEIGHT)'
$top=Override-Parameter $top 'stereo_capture_source4' 'u_stereo_capture0' '.WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT)' '.WIDTH(SHORT_BASE_WIDTH),.HEIGHT(SHORT_BASE_HEIGHT)'
$top=Override-Parameter $top 'stereo_capture_source4' 'u_stereo_capture1' '.WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT)' '.WIDTH(SHORT_BASE_WIDTH),.HEIGHT(SHORT_BASE_HEIGHT)'
$top=Override-Parameter $top 'shared_raw10_decode_service' 'u_decode_service' '.WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT)' '.WIDTH(SHORT_BASE_WIDTH),.HEIGHT(SHORT_BASE_HEIGHT)'
$top=Override-Parameter $top 'hdr_pair_native_source_service4' 'u_native_source' '.MAX_WIDTH(FRAME_WIDTH),.MAX_HEIGHT(FRAME_HEIGHT)' '.MAX_WIDTH(SHORT_BASE_WIDTH),.MAX_HEIGHT(SHORT_BASE_HEIGHT)'
$top=Override-Parameter $top 'raw_pair_processing_service' 'u_processing' '.WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT)' '.WIDTH(SHORT_BASE_WIDTH),.HEIGHT(SHORT_BASE_HEIGHT)'
$top=Override-Parameter $top 'private_raw_isp_borrow4' 'u_original_source' '.RAW_SAMPLE_BITS(PRIVATE_RAW_SAMPLE_BITS)' '.BASE_WIDTH(SHORT_BASE_WIDTH),.BASE_HEIGHT(SHORT_BASE_HEIGHT),.RAW_SAMPLE_BITS(PRIVATE_RAW_SAMPLE_BITS)'
$top=Replace-Instance $top 'sys_pll_125m_25m' 'u_pixel_pll' @'
    assign pixel_clk=i_pixel_clk;
    assign pixel_pll_lock=i_clock_ready;
    assign unused_pixel_aux=sys_clk;
'@
$top=Replace-Instance $top 'imx415_sensor_pll_25m' 'u_camera_pll' @'
    assign camera_pll_lock=i_clock_ready;
    assign {camera_ref_clk,sensor_clk,sensor_hdr_clk}={3{sys_clk}};
'@
$top=Replace-Instance $top 'PH1_LOGIC_BUFG' 'u_board_ref_bufg' '    assign board_ref_clk_100m_gclk=board_ref_clk_100m;'
$top=Replace-Instance $top 'PH1_LOGIC_BUFG' 'u_camera_ref_global' '    assign camera_pll_refclk=sys_clk;'
$top=Project-Instance $top 'real_hdr_camera_observe_axis' 'u_camera' 'uhd_short_camera' ($cameraPorts+$ispPorts)
$top=Replace-Instance $top 'sdr_camera_raw_frontend' 'u_camera1' @'
    // The short UHD fixture runs the single physical-eye configuration.
    assign {cam1_sdr_profile,cam1_hdr_mode,cam1_hdr_mode_running,cam1_hdr_stable}=0;
    assign {cam1_hdr_token0,cam1_hdr_token1,cam1_hdr_token_valid}=0;
    assign {camera1_raw,camera1_valid,camera1_sof,camera1_eol,camera1_abort,camera1_sequence,camera1_identity_valid}=0;
    assign {camera1_event_valid,camera1_event_kind,camera1_event_ok,camera1_event_error,
        camera1_event_sequence,camera1_event_identity_valid}=0;
    assign {camera1_config_done,camera1_config_error,camera1_phy_ready,rx_diag_cfg1}=0;
    assign {camera1_ecc,camera1_crc,camera1_overflow,camera1_format,camera1_identity_fault,camera1_receive_fault}=0;
    assign {cam1_scl,cam1_mclk,cam1_xclr}=0;
'@
$top=Exact $top ".o_retire_rsp_valid(),.i_retire_rsp_ready(1'b1),.o_retire_rsp_code()" ".o_retire_rsp_valid(o_ring_retire_response_valid),.i_retire_rsp_ready(1'b1),.o_retire_rsp_code(o_ring_retire_response_code)" 'Observe real JPEG slot retire result'
$top=Project-Instance $top 'ddr3_jpeg_store' 'u_ddr_store' 'uhd_short_ddr_store' $memPorts
$top=Project-Instance $top 'product_pcie_transport' 'u_pcie' 'uhd_short_product' $hostPorts

$observation=@'
    // Read-only copies of original handshake and terminal boundaries.
    assign {o_pixel_reset_n,o_dfi_reset_n,o_user_reset_n}={pixel_rst_n,dfi_rst_n,user_rst_n};
    assign o_cfg_ack_fire=whole_config_ack_valid&&whole_config_ack_ready;
    assign o_cfg_ack_ok=whole_config_ack_ok;
    assign o_cfg_ack_session=whole_config_ack_data[63:32];
    assign o_cfg_ack_epoch=whole_config_ack_data[159:128];
    assign o_cold_config_sof=cold_config_sof;
    assign o_uhd_pixel=uhd_pixel;
    assign o_capture_enabled=stereo_capture_enable;
    assign o_capture_frame_accept=raw_capture0_frame_accept;
    assign {o_session_armed,o_buffer_armed}={session_armed,product_buffer_armed};
    assign o_replay_source_fire=hdr_raw_source_valid&&hdr_raw_source_ready;
    assign o_replay_source_ok=hdr_raw_source_ok;
    assign o_replay_source_tag=hdr_raw_source_tag;
    assign {o_jpeg_source_done,o_jpeg_source_failed}={private_jpeg_source_done,private_jpeg_source_error};
    assign o_jpeg_start_fire=ring_start_valid&&ring_start_ready&&!bridge_fault&&nr_writer_start_permitted;
    assign {o_jpeg_start_width,o_jpeg_start_height,o_jpeg_start_sequence}={ddr_width,ddr_height,ddr_capture_id};
    assign o_jpeg_result_fire=jpeg_result_valid&&jpeg_result_ready;
    assign {o_jpeg_result_ok,o_jpeg_result_length}={jpeg_result_ok,jpeg_result_length};
    assign o_writer_ack_fire=writer_ack_valid&&writer_ack_ready;
    assign {o_writer_ack_ok,o_writer_ack_sequence}={writer_ack_ok,writer_ack_sequence};
    assign {o_ticket_result,o_ticket_error,o_ticket_job}=
        {stereo_processing_result_valid,stereo_processing_result_error,stereo_processing_result_job};
    assign {o_raw_slot_retired,o_raw_empty}={stereo_retire_done,stereo_empty};
    assign o_record_offer=jpeg_offer;
    assign o_record_retire_fire=retire_valid&&retire_ready;
    assign o_record_quiet=record_ring_quiescent;
    assign o_fault=raw_processing_fault||capture_frontend_fault||processing_event_fault||bridge_fault||
        store_recovery||transport_recovery||jpeg_cdc_source_fault||jpeg_cdc_user_fault||record_source_fault;
'@
$top=Exact $top "endmodule`n" ($observation+"`nendmodule`n") 'Public transaction observations'
Emit 'uhd_integration_fixture' $top
$topDecl=Header $top 'uhd_integration_fixture'
[IO.File]::WriteAllText((Join-Path $out 'uhd_integration_fixture_ports.vh'),
    $top.Substring($topDecl.start,$topDecl.close-$topDecl.start+1)+";`n",$utf8)

$seams=@(
    'wire configured_frame_accept=','assign cold_config_observe=','assign cold_config_sof=',
    'wire stored_sdr_pixel=','wire stored_sdr_dfi=','assign stereo_capture_enable=',
    'assign stereo_processing_selected=','wire processing_uhd=','admitted_uhd<=processing_uhd;',
    '.frame_required(2''b01)', '.i_skip_neutral_stats(uhd_pixel)',
    'assign private_no_work_complete=uhd_pixel&&private_jpeg_source_error;',
    'wire private_pipeline_quiet=','wire private_writer_required=','assign private_writer_ack_valid=',
    'assign writer_ack_ready=','assign retire_valid=jpeg_source_retire_valid;','assign record_dfi_data_quiescent='
)
$preserved=@(foreach($anchor in $seams){
    $at=$originalTop.IndexOf($anchor,[StringComparison]::Ordinal)
    if ($at -lt 0) { throw "Missing preserved expression $anchor" }
    if ($anchor.StartsWith('.') -or $anchor.EndsWith(';')) { $expression=$anchor }
    else { $expression=$originalTop.Substring($at,$originalTop.IndexOf(';',$at)-$at+1) }
    if (!$top.Contains($expression)) { throw "Changed protected expression $anchor" }
    [ordered]@{anchor=$anchor; sha256=(TextHash $expression)}
})

$manifest=Get-Content -LiteralPath (Join-Path $root 'SOURCE_MANIFEST.json') -Raw | ConvertFrom-Json
$projectPath='fpga_prj/rfcamera_fusion_r1.al'
$projectText=[IO.File]::ReadAllText((Join-Path $root $projectPath))
$includes=@([regex]::Matches($projectText,'<Option Name="IncludeDir" Val="\.\./([^"]+)"/>') |
    ForEach-Object {$_.Groups[1].Value})
$defines=@([regex]::Matches($projectText,'<Define Name="([^"]+)" Val="([^"]+)"/>') |
    ForEach-Object {$_.Groups[1].Value+'='+$_.Groups[2].Value})
if ($includes.Count -ne 5 -or $defines.Count -eq 0) { throw 'Native include/define options changed' }
$omit=@('anlogic2026.v','ddr3_jpeg_store.v','c2h_pcie_endpoint.v','product_pcie_transport.v',
    'physical_camera_rgb_pipeline.v','real_hdr_camera_observe_axis.v','sdr_camera_raw_frontend.v')
$rtlFiles=@([regex]::Matches($projectText,'<File Path="\.\./(src_fpga/rtl/[^"]+\.v)">') |
    ForEach-Object {$_.Groups[1].Value} | Where-Object {(Split-Path -Leaf $_) -notin $omit})
$ipFiles=@($manifest.files | ForEach-Object {$_.path} | Where-Object {
    $_ -like 'src_fpga/ip/*.v' -and $_ -notmatch '/(ui_ddr|camera_pcie_ep|csi2_phy|imx415_sensor_pll)/'
})
# The frozen ROM wrappers use project-relative native INIT_FILE paths. The
# simulation copies change only that filename to the public run/rom_init path.
$romCopies=@{}
foreach($name in @('jpeg_rom_q_lane0','jpeg_rom_q_lane1','jpeg_rom_q_lane2','jpeg_rom_q_lane3',
                   'jpeg_rom_q_lane4','jpeg_rom_q_lane5','jpeg_rom_q_lane6','jpeg_rom_q_lane7',
                   'jpeg_rom_recip','jpeg_rom_huff','tone96_rom0','tone96_rom1','gamma_rom_8x1024_ip')) {
    $romCopies["$name.v"]="src_fpga/simulation/assets/${name}_sim.v"
}
$ipFiles=@($ipFiles | ForEach-Object {
    $baseName=Split-Path -Leaf $_
    if($romCopies.ContainsKey($baseName)) { $romCopies[$baseName] } else { $_ }
})
$tdModels=@(
    'sim_release/common/al_phy_glbl.v',
    'sim_release/ph1/ph1_logic_clk.v','sim_release/ph1/ph1_phy_gclk_v2.v','sim_release/ph1/ph1_phy_pll.v',
    'sim_release/ph1/ph1_logic_dram.v','sim_release/ph1/ph1_logic_eram.v','sim_release/ph1/ph1_phy_eram.v',
    'sim_release/ph1/ph1_logic_fifo.v','sim_release/ph1/ph1_logic_ramfifo.v','sim_release/ph1/ph1_phy_fifoctrl.v',
    'sim_release/ph1/ph1_logic_mult.v','sim_release/ph1/ph1_phy_dspmult.v','sim_release/ph1/ph1_phy_dspmult_v2.v',
    'sim_release/ph1/ph1_phy_dspsiou.v','sim_release/ph1/ph1_phy_dspadd_v2.v','sim_release/ph1/ph1_phy_dsptadd_v2.v',
    'sim_release/ph1/ph1_phy_dsplogic_v2.v','sim_release/ph1/ph1_phy_gsr.v'
)
$compile=[ordered]@{
    top='uhd_integration_fixture'; sources=@($rtlFiles+$ipFiles+$generated); include=$includes
    defines=$defines; td_models=$tdModels; sibling_tops=@('work.PH1_PHY_GSR','ph1.glbl')
}
foreach ($path in $compile.sources) {
    if (!(Test-Path -LiteralPath (Join-Path $root $path))) { throw "Missing opaque input $path" }
}
$seal=[ordered]@{
    root_sources=$origins; replaced=$changes; preserved_top_expressions=$preserved
    manifest_inputs=@($projectPath,'SOURCE_MANIFEST.json' | ForEach-Object {
        [ordered]@{path=$_; sha256=(Get-FileHash -LiteralPath (Join-Path $root $_)).Hash.ToLowerInvariant()}
    })
    generated=@($generated | ForEach-Object {
        [ordered]@{path=$_; sha256=(Get-FileHash -LiteralPath (Join-Path $root $_)).Hash.ToLowerInvariant()}
    })
}
[IO.File]::WriteAllText((Join-Path $out 'compile.json'),($compile | ConvertTo-Json -Depth 6),$utf8)
[IO.File]::WriteAllText((Join-Path $out 'projection.json'),($seal | ConvertTo-Json -Depth 8),$utf8)
Write-Output $out
