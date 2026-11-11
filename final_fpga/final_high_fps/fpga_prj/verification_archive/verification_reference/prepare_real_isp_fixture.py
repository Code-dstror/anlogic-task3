"""Maintainer-only projection preparation; no test stimulus or expected DUT data."""
from pathlib import Path

base = Path(__file__).resolve().parents[1]
target = base / 'verification_reference/fusion_product_public'
target.mkdir(parents=True, exist_ok=True)
s = (base / 'verification_reference/uhd_integration_public/project_fixture.ps1').read_text(encoding='utf-8')
a = s.index("$rgb=Replace-Instance $rgb 'shared_wide_isp' 'u_isp' @'")
b = s.index('$rgb=Exact $rgb', a)
s = s[:a] + '''# Keep the actual shared ISP and its accepted-SOF quality snapshot.
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
''' + s[b:]
s = s.replace('tmp/uhd_integration_projection/', 'tmp/fusion_product_projection/')
s = s.replace("'verification_reference/rate_r2_manifest.json'", "'SOURCE_MANIFEST.json'")
s = s.replace("'fpga_prj/rfcamera_rate_r3.al'", "'fpga_prj/rfcamera_fusion_r1.al'")
s = s.replace("'jpeg_rom_recip','jpeg_rom_huff'", "'jpeg_rom_recip','jpeg_rom_huff','tone96_rom0','tone96_rom1','gamma_rom_8x1024_ip'")
(target / 'project_fixture.ps1').write_text(s, encoding='utf-8', newline='\n')
s = (base / 'verification_reference/uhd_integration_public/prepare_rom.ps1').read_text(encoding='utf-8')
s = s.replace("foreach($name in @('lane0_q','lane1_q','lane2_q','lane3_q','lane4_q','lane5_q','lane6_q','lane7_q','reciprocal','ac_huffman')) {\n    $source=Join-Path $candidate \"src_fpga/rtl/jpeg/quant_data/$name.mif\"", '''$romPaths=@('lane0_q','lane1_q','lane2_q','lane3_q','lane4_q','lane5_q','lane6_q','lane7_q','reciprocal','ac_huffman') | ForEach-Object { "src_fpga/rtl/jpeg/quant_data/$_.mif" }
$romPaths+=@('src_fpga/ip/coefficients/tone96_0.mif','src_fpga/ip/coefficients/tone96_1.mif','src_fpga/rtl/isp/color/gamma22_10to8.mif')
foreach($relativePath in $romPaths) {
    $source=Join-Path $candidate $relativePath
    $name=[IO.Path]::GetFileNameWithoutExtension($source)''')
assert '$romPaths' in s
(target / 'prepare_rom.ps1').write_text(s, encoding='utf-8', newline='\n')
print('Prepared real-ISP product projection and 13-ROM initializer; not generated or run.')
