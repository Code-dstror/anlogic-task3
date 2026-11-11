"""Bounded scalar proof for R3 bin-parity shared winner update routing."""
import hashlib,itertools,json,random
from pathlib import Path

def rank(p):return (-p['strength'],p['native_x'],p['width_quarter'])
def insert(old,p):
    if p is None:return old[:]
    out=[]
    for q in sorted(old+[p],key=rank):
        if all(abs(q['native_x']-s['native_x'])>=24 for s in out):
            out.append(q)
            if len(out)==2:break
    return out
def point(left,width,strength,row=200):
    return dict(native_x=4*left+2*width,width_quarter=width,strength=strength,quarter_y=row)
def full_step(state,items,clear=None):
    out=[row[:] for row in state]
    for p in items:
        if p is not None:
            key=(p['quarter_y']&1)*12+p['native_x']//160
            out[key]=insert(out[key],p)
    if clear is not None:out[clear*12:clear*12+12]=[[] for _ in range(12)]
    return out
def shared_step(state,items,clear=None):
    out=[row[:] for row in state]
    for parity in range(2):
        selected=[p for p in items if p is not None and (p['native_x']//160)&1==parity]
        if not selected:continue
        addresses={(p['quarter_y']&1)*6+(p['native_x']//160)//2 for p in selected}
        assert len(addresses)==1
        address=addresses.pop()
        key=(address//6)*12+(address%6)*2+parity
        value=state[key]
        for p in selected:value=insert(value,p)
        out[key]=value
    if clear is not None:out[clear*12:clear*12+12]=[[] for _ in range(12)]
    return out
def run_checks():
    geometry=0;max_distance=0
    for left in range(480):
        for gap in [2,3]:
            for w0,w1 in itertools.product(range(1,9),repeat=2):
                if left+w0>=480 or left+gap+w1>=480:continue
                a=4*left+2*w0;b=4*(left+gap)+2*w1
                assert abs(a-b)<=26 and abs(a//160-b//160)<=1
                if (a//160)&1==(b//160)&1:assert a//160==b//160
                max_distance=max(max_distance,abs(a-b));geometry+=1
    mixed=0
    for new_left in [0,1]:
        for width in range(1,9):
            items=[point(478,1,100,200),point(new_left,width,120,201)]
            assert items[0]['native_x']//160==11 and items[1]['native_x']//160==0
            assert full_step([[] for _ in range(24)],items)==shared_step([[] for _ in range(24)],items)
            mixed+=1
    rng=random.Random(20261030);state=[[] for _ in range(24)];traces=0
    for row in range(169,270):
        for base in range(2,468,4):
            offsets=rng.choice([[],[0],[1],[2],[3],[0,2],[0,3],[1,3]])
            items=[point(base+i,rng.randrange(1,9),rng.randrange(2041),row) for i in offsets]
            clear=(row&1)^1 if base==466 else None
            a=full_step(state,items,clear);b=shared_step(state,items,clear)
            assert a==b;state=a;traces+=1
    old=full_step([[] for _ in range(24)],[point(46,2,100)])
    ordered=[point(50,8,120),point(52,1,110)]
    assert full_step(old,ordered)==shared_step(old,ordered)
    assert [p['native_x'] for p in shared_step(old,ordered)[1]]==[216,188]
    assert shared_step(old,list(reversed(ordered)))!=shared_step(old,ordered)
    state=[[] for _ in range(24)]
    for p in [point(46,2,100),point(50,2,150),point(54,2,200)]:
        assert full_step(state,[p])==shared_step(state,[p]);state=full_step(state,[p])
    assert [p['native_x'] for p in state[1]]==[220]
    # Verify row-clear priority even in an intentionally coincident update.
    for clear in [0,1]:assert full_step(state,ordered,clear)==shared_step(state,ordered,clear)
    return dict(status='PASS',source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        geometry_pairs_checked=geometry,max_center_distance=max_distance,mixed_EoL_cases=mixed,
        continuous_bank_updates_checked=traces,center_reverse_order_sensitive=True,
        back_to_back_samebin=True,row_clear_priority=True,new_runtime_error_checks=False)
if __name__=='__main__':print(json.dumps(run_checks(),indent=2))
