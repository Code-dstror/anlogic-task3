"""Native catalog identity and application/PH1A port-boundary tests. No PCIe electrical model in the contract test."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--name",required=True)
    ap.add_argument("--td-root",required=True,type=Path)
    ap.add_argument("--modelsim-bin",required=True,type=Path)
    a=ap.parse_args()
    if not re.fullmatch("[a-z][a-z0-9_]{0,40}",a.name):ap.error("invalid evidence name")
    run=ROOT/"tmp/camera_pcie_native"/a.name
    run.mkdir(parents=True,exist_ok=False)
    rtl=ROOT/"src_fpga/rtl"
    ip=ROOT/"src_fpga/ip/camera_pcie_ep"
    params=ET.parse(ip/"camera_pcie_ep.ipc").find("GeneralConfig")
    required=dict(Type="PH1_LOGIC_PCIE",Device="PH1A90SEG324",Version="1.3",inst="camera_pcie_ep",
                  LINK_SPEED_GENERATION="Gen2",PCIE_GEN="Gen2",LINK_WIDTH="X1",LINK_LOC="Bank 83 Lane 1",
                  REF_CLK_FREQ="Bank83 100MHz",AUX_CLK_FREQ="25MHz",PCIE_APP_MODE="Advanced",
                  PF0_VEN_ID="1EDB",PF0_DEV_ID="ABCD",PF0_CLASS_CODE_VALUE="050000",PF0_BAR0_EN="1",
                  PF0_BAR0_VALUE="FFF00000",PF0_BAR0_64_32="0",PF0_BAR0_PREFETCH="0",PF0_BAR0_BUS="0",
                  PF0_MSI_EN="1",PF0_MSI_VECTOR="4",PF0_PV_MSK="1",MSI_SIG_EN="1",DBI_SIG_EN="1",
                  CFG_INFO_SIG_EN="1",BYPASS_SIG_EN="1",XALI0_SIG_EN="1",XALI1_SIG_EN="1",TRGT1_SIG_EN="1")
    for k,v in required.items():
        if params.findtext(k)!=v:raise ValueError("incorrect native property "+k)
    body=re.sub(r'//[^\n]*|/\*[\s\S]*?\*/','',(ip/"camera_pcie_ep.v").read_text()).split('endmodule')[0]
    ports=re.findall(r'\b(input|output|inout)\s*(?:wire\s+)?(\[[^]]+\])?\s*(\w+)\s*;',body)
    if len(ports)!=len({n for _,_,n in ports}) or len(ports)!=264:
        raise ValueError("unexpected generated native terminal list")
    # Generate the electrical boundary from the actual IP signature. Dynamic scenarios
    # drive individual native outputs from tb_native_port; all inactive outputs read zero.
    stub=run/"hard_boundary.sv"
    stub.write_text("module camera_pcie_ep(\n"+",\n".join(f"{io} wire {width} {n}" for io,width,n in ports)+
                    "\n);\n"+"\n".join(f"assign {n}='0;" for io,_,n in ports if io=="output")+"\nendmodule\n")
    names=("reset_release_sync","camera_pcie_bar_rx","camera_pcie_bar_tx","camera_pcie_result_msi",
           "c2h_native_fence_listener","camera_pcie_hard_port","c2h_pcie_endpoint","c2h_link_supervisor",
           "c2h_native_rx_transport","c2h_bar_cq","c2h_native_packetizer","c2h_packet_ram","td_sdp_ram")
    files=[rtl/(n+".v") for n in names]
    files.append(ROOT/"src_fpga/ip/sys_pll_125m_25m/sys_pll_125m_25m.v")
    bench=HERE/"tb_native_port.sv"
    includes=[rtl/"include/01_include",rtl/"include/04_include"]
    models=[a.td_root/"sim_release"/n for n in ("common/al_phy_glbl.v","ph1/ph1_logic_clk.v",
        "ph1/ph1_logic_dram.v","ph1/ph1_logic_eram.v","ph1/ph1_phy_eram.v","ph1/ph1_phy_pll.v",
        "ph1/ph1_phy_sclk_v2.v","ph1/ph1_phy_hclk.v","ph1/ph1_phy_pcie_v3.sv",
        "ph1/ph1_phy_gsr.v")]
    paths=list(ip.iterdir())+files+models+[stub,bench,Path(__file__)]+[
        path for d in includes for path in d.glob("*.vh")]
    inputs={str(p.resolve()):sha(p) for p in paths}
    result=dict(status="RUNNING",properties=required,inputs=inputs,commands=[],board="NOT_RUN")
    def tool(name,arguments,tag):
        argv=[str(a.modelsim_bin/(name+".exe")),*map(str,arguments)]
        result["commands"].append(argv)
        logfile=run/(tag+".log")
        with logfile.open("w",encoding="utf-8") as output:
            proc=subprocess.run(argv,cwd=run,stdout=output,stderr=subprocess.STDOUT,timeout=100)
        log=logfile.read_text(errors="replace")
        if proc.returncode or re.search(r"\*\* (Fatal|Error)(?:\s*\([^)]*\))?:",log):
            raise RuntimeError(tag+" failed: "+log[-5000:])
        return log
    try:
        tool("vmap",["-c"],"vmap")
        for lib in ("work","physical","ph1"):
            tool("vlib",[lib],"lib_"+lib)
            tool("vmap",[lib,lib],"map_"+lib)
        inc=["+incdir+"+str(d) for d in includes]
        tool("vlog",["-quiet","-sv","-work","work",*inc,*files,stub,bench],"compile_boundary")
        sim=tool("vsim",["-c","work.tb_native_port","-l","port.log","-do","run -all;quit -f"],"simulate")
        if "RESULT: PASS NATIVE_CAMERA_PORT" not in sim:raise RuntimeError("missing terminal self-check")
        result["native_port_check"]=next(x for x in sim.splitlines() if "RESULT: PASS" in x)
        tool("vlog",["-quiet","-sv","-work","ph1",*models],"compile_models")
        tool("vlog",["-quiet","-sv","-work","physical",*inc,*files,*sorted(ip.glob("*.v"))],"compile_real_ip")
        for ext in ("dat","txt"):shutil.copyfile(ip/("camera_pcie_ep."+ext),run/("camera_pcie_ep."+ext))
        tool("vsim",["-c","-L","physical","-L","ph1","physical.c2h_pcie_endpoint","ph1.glbl",
                     "ph1.PH1_PHY_GSR","-l","real_ip_elab.log","-do","run 0;quit -f"],"elaborate_real_ip")
        if any(sha(Path(k))!=v for k,v in inputs.items()):raise ValueError("an input changed during the check")
        result.update(status="PASS",real_generated_endpoint="ELABORATED_ONLY")
        print(result["native_port_check"])
    except Exception as exc:
        result.update(status="FAIL",error=str(exc));raise
    finally:
        (run/"result.json").write_text(json.dumps(result,indent=2)+"\n")
        print(run/"result.json")


if __name__=="__main__":
    main()
