"""Check the explicit RTL observer boundary; this is not a post-route timing proof."""
from pathlib import Path
import argparse
import hashlib
import json
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def clean(text):
    return re.sub(r'/\*.*?\*/|//[^\n]*', '', text, flags=re.S)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def header_ports(body, module):
    header = re.search(r'\bmodule\s+'+module+r'\s*(?:#\(.*?\)\s*)?\((.*?)\);',
                       clean(body), flags=re.S)
    if header is None:
        raise AssertionError('Cannot resolve explicit module header: '+module)
    return {m.group(2): m.group(1) for m in re.finditer(
        r'\b(input|output|inout)\s+(?:wire\s+|reg\s+)?(?:\[[^\]]+\]\s*)?(\w+)', header.group(1))}


def declared_names(group):
    parts=[];begin=0;depth=0
    for index,char in enumerate(group):
        if char in '({[':depth+=1
        elif char in ')}]':depth-=1
        elif char==',' and depth==0:parts.append(group[begin:index]);begin=index+1
    parts.append(group[begin:])
    return [part.split('=',1)[0].strip() for part in parts]


def remove_port(body,name):
    return re.sub(r'\boutput\s+wire\s*(?:\[[^\]]+\]\s*)?'+name+r'\b\s*,?', '',body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    top = ROOT/'src_fpga/rtl/anlogic2026.v'
    observer = ROOT/'src_fpga/rtl/uart_status_observer.v'
    snapshot = ROOT/'src_fpga/rtl/uart_observer_snapshot.v'
    product = ROOT/'src_fpga/rtl/product_pcie_transport.v'
    endpoint = ROOT/'src_fpga/rtl/c2h_pcie_endpoint.v'
    native = ROOT/'src_fpga/rtl/c2h_native_rx_transport.v'
    body = clean(top.read_text())
    assert re.search(r'parameter\s+integer\s+DEBUG_UART_ENABLE\s*=\s*0\b', body)
    assert re.search(r'parameter\s+integer\s+READONLY_UART_ENABLE\s*=\s*1\b', body)
    start = body.index('if (READONLY_UART_ENABLE != 0) begin:g_status_uart')
    end = body.index('end else begin:g_no_status_uart', start)
    region = body[start:end]
    outside = body[:start]+body[end:]
    declarations = re.findall(r'\b(?:reg|wire)\s*(?:\[[^\]]+\]\s*)?([^;]+);', region)
    tap_names = sorted(name for group in declarations for name in declared_names(group))
    assert tap_names and all(re.fullmatch(r'\w+', name) for name in tap_names)
    escaped = [name for name in tap_names if re.search(r'\b'+name+r'\b', outside)]
    assert not escaped, 'Observer-local tap escaped its generate scope: '+str(escaped)
    outside_without_link=re.sub(r'\bwire\s*\[7:0\]\s*transport_observe\s*;', '',outside)
    outside_without_link=re.sub(r'\.o_observe\s*\(transport_observe\)', '',outside_without_link)
    assert not re.search(r'\btransport_observe\b',outside_without_link), 'Observation bus has a business consumer outside observer'
    product_body=clean(product.read_text())
    assert header_ports(product.read_text(),'product_pcie_transport')['o_observe']=='output'
    product_rest=remove_port(product_body,'o_observe')
    product_rest=re.sub(r'\.o_observe\s*\(o_observe\)', '',product_rest)
    assert not re.search(r'\bo_observe\b',product_rest), 'Product consumes observer output functionally'
    endpoint_body=clean(endpoint.read_text())
    assert header_ports(endpoint.read_text(),'c2h_pcie_endpoint')['o_observe']=='output'
    endpoint_assign=re.search(r'\bassign\s+o_observe\s*=\s*([^;]+);',endpoint_body)
    assert endpoint_assign is not None
    assert re.sub(r'\s+','',endpoint_assign.group(1))==(
        '{native_observe_submit,native_observe_state,completion_fault||completion_incident,'
        'supervised_fault,supervisor_ready,bme[0]}')
    endpoint_rest=remove_port(endpoint_body,'o_observe').replace(endpoint_assign.group(), '')
    assert not re.search(r'\bo_observe\b',endpoint_rest), 'Endpoint consumes packed observation bus'
    for name,port in [('native_observe_state','o_observe_state'),('native_observe_submit','o_observe_submit')]:
        endpoint_rest=re.sub(r'\bwire\s*(?:\[[^\]]+\]\s*)?'+name+r'\s*;', '',endpoint_rest)
        endpoint_rest=re.sub(r'\.'+port+r'\s*\('+name+r'\)', '',endpoint_rest)
        assert not re.search(r'\b'+name+r'\b',endpoint_rest), 'Native observation has a functional endpoint consumer'
    native_body=clean(native.read_text());native_ports=header_ports(native.read_text(),'c2h_native_rx_transport')
    for name,source in [('o_observe_state','state[2:0]'),('o_observe_submit','accept_submit')]:
        assert native_ports[name]=='output'
        assignment=re.search(r'\bassign\s+'+name+r'\s*=\s*([^;]+);',native_body)
        assert assignment is not None and re.sub(r'\s+','',assignment.group(1))==source
        rest=remove_port(native_body,name).replace(assignment.group(),'')
        assert not re.search(r'\b'+name+r'\b',rest), 'Observation output feeds native business logic'
    compact=re.sub(r'\s+','',region)
    assert 'user_first_fault_phase<=transport_observe[6:4];' in compact
    assert 'if(user_faults==0&&|user_causes)' in compact
    ports = header_ports(observer.read_text(), 'uart_status_observer')
    assert {name for name,direction in ports.items() if direction!='input'} == {
        'o_uart_tx','o_trace_request','o_trace_index'}
    assert ports['o_uart_tx']=='output' and 'i_uart_rx' not in ports and 'uart_rx' not in ports
    instance = re.search(r'\buart_status_observer\s*#\(.*?\)\s+u_observer\s*\((.*?)\);', region, re.S)
    assert instance is not None
    connections = dict(re.findall(r'\.(\w+)\s*\(([^()]*)\)', instance.group(1)))
    assert set(connections)==set(ports), 'Every observer port must be explicitly connected'
    assert connections['o_uart_tx'].strip()=='uart_tx'
    # RT/V1 is explicitly retired. The remaining observer has no live request
    # output and cannot reach a receiver/reset/READY or writable UART input.
    trace_instance=re.search(r'\brx_first_loss_trace\s+u_trace\s*\((.*?)\);',region,re.S)
    assert trace_instance is None and 'u_trace_word_reset' not in region
    assert '.RX_TRACE_ENABLE(0)' in compact and '.RX_DIAG_ENABLE(1)' in compact
    assert '.CFG_DIAG_ENABLE(1)' in compact and '.CFG_FRAME_VERSION(2)' in compact
    assert connections['o_trace_request'].strip()==connections['o_trace_index'].strip()==''
    assert connections['i_trace_ack'].strip()=="1'b0"
    assert connections['i_trace_data'].strip()=="320'd0"
    assert not re.search(r'\brx_trace_(sample|trigger|cohort_n|enable)\b',body)
    uart_lines = [line.strip() for line in body.splitlines() if re.search(r'\buart_tx\b',line)]
    assert all(re.search(r'output\s+wire\s+uart_tx|\.o_tx\(uart_tx\)|\.o_uart_tx\(uart_tx\)|assign\s+uart_tx\s*=\s*1\x27b1',line)
               for line in uart_lines), 'UART output has an unexpected feedback consumer'
    assert not re.search(r'\b(force|release)\b', clean(observer.read_text())+clean(snapshot.read_text()))
    source_ports = header_ports(snapshot.read_text(), 'uart_observer_snapshot')
    assert {name for name,direction in source_ports.items() if direction!='input'} == {'o_ack','o_snapshot'}
    paths = [Path(__file__),top,observer,snapshot,product,endpoint,native]
    result = {'status':'PASS','scope':'Explicit RTL generate/port boundary. Source-level read-only connectivity; not physical fanout/timing or post-synthesis equivalence.',
              'inputs':[{'path':p.resolve().as_posix(),'sha256':digest(p)} for p in paths],
              'production_parameters':{'DEBUG_UART_ENABLE':0,'READONLY_UART_ENABLE':1,'RX_TRACE_ENABLE':0},
              'top_observer_region_sha256':hashlib.sha256(region.encode()).hexdigest(),
              'observer_ports':ports,'top_connections':connections,'observer_local_taps':tap_names,
              'local_tap_count':len(tap_names),
              'transport_observation_chain':{'top':'declaration + product output + observer reads only',
                  'product':'output passthrough only','endpoint':'packed assign only',
                  'native':{'o_observe_state':'state[2:0]','o_observe_submit':'accept_submit'}},
              'phase_kind':'first_observed_fault_phase',
              'phase_scope':'Native phase when observer first sees a cause; not an assertion of physical incident-time phase.',
              'escaped_taps':escaped,'uart_top_occurrences':uart_lines,
              'retired_protocol':'RT/V1 history ring only; OB/CGv2/RX unchanged',
              'conclusion':'Observer trace outputs are open and trace inputs are constant zero. The sole external observer output is uart_tx. No UART RX or business feedback exists.',
              'physical_timing':'NOT_RUN','board':'NOT_RUN'}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print('READONLY_UART_STRUCTURE PASS taps='+str(len(tap_names))+' sole_output=uart_tx RX=absent')


if __name__=='__main__':
    main()
