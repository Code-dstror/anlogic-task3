"""Deterministic 31 packet-boundary fixtures; ideal deserialized bytes only."""
def ecc(h):
    return sum(((h & m).bit_count() & 1) << i for i, m in enumerate(
        [0xf12cb7, 0xf2555b, 0x749a6d, 0xb8e38e, 0xdf03f0, 0xeffc00]))

def header(dt, wc):
    h = wc << 8 | dt
    return (ecc(h) << 24) | h

def crc(data):
    c = 0xffff
    for b in data:
        c ^= b
        for _ in range(8):
            c = (c >> 1) ^ (0x8408 if c & 1 else 0)
    return c

def pkt(dt, wc):
    packet = header(dt, wc).to_bytes(4, 'little')
    if dt > 15:
        data = bytes([0x55]) * wc
        packet += data + crc(data).to_bytes(2, 'little')
    packet += b'\xff' * (-len(packet) % 4)
    return [int.from_bytes(packet[i:i+4], 'little') for i in range(0, len(packet), 4)]

def burst(words, gap=32, lost_lane=-1, skew_lane=-1, skew=0):
    # All lanes start with zero before the 0xb8 SoT, as required by byte align.
    lanes = [[0] * 3 + [0xb8] + [(w >> (8*l)) & 255 for w in words] for l in range(4)]
    if lost_lane >= 0:
        lanes[lost_lane][3] = 0xb9
    if skew_lane >= 0:
        lanes[skew_lane] = [0xff] * skew + lanes[skew_lane]
    n = max(map(len, lanes))
    return [sum((lane[i] if i < len(lane) else 255) << (8*l) for l, lane in enumerate(lanes))
            for i in range(n)] + [0xffffffff] * gap

def cases():
    result = []
    def frame(name, gap=32, lost_lane=-1, skew_lane=-1, skew=0, continuous=False):
        fs, raw, fe = pkt(0, 1), pkt(0x2b, 2430), pkt(1, 1)
        seq = [0xffffffff] * 12 + burst(fs)
        seq += burst(raw)
        if continuous:
            # Same HS burst, no new SoT: demonstrates the separate DRAIN limit.
            seq = [0xffffffff] * 12 + burst(fs) + burst(raw + raw)
        else:
            seq += burst(raw, gap=gap, lost_lane=lost_lane, skew_lane=skew_lane, skew=skew)
        seq += burst(raw) + burst(fe) + [0xffffffff] * 50
        result.append(dict(id=len(result), name=name, gap=gap, lost_lane=lost_lane,
                           skew_lane=skew_lane, skew=skew, continuous=continuous,
                           all_lane_sync_input_cycles=[i for i,w in enumerate(seq) if w==0xb8b8b8b8], raw=seq))
    frame('baseline')
    for l in range(4):
        frame(f'missing_sync_lane{l}', lost_lane=l)
    for skew in range(1, 9):
        frame(f'lane0_skew_{skew}', skew_lane=0, skew=skew)
    # This is gap AFTER the second long packet, BEFORE the third prefix zeros.
    for gap in range(0, 17):
        frame(f'post_packet_gap_{gap}', gap=gap)
    frame('continuous_two_raw_packets', continuous=True)
    return result

