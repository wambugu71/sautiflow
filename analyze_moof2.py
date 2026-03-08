import struct

def r32(data, off):
    return struct.unpack_from('>I', data, off)[0]

def fc(v):
    return bytes([(v>>24)&0xFF,(v>>16)&0xFF,(v>>8)&0xFF,v&0xFF]).decode('latin-1', errors='replace')

path = r'C:\Users\wambugukinyua\Downloads\iLoveYt.net_YouTube_Naughty-Boy-Sam-Smith-La-la-la-Lyrics_Media_2WmBa1CviYE_008_128k.m4a'

# Parse first moof at offset 976, size 1816
with open(path, 'rb') as f:
    f.seek(976)
    moof_data = f.read(1816)

# Raw hex dump of first 128 bytes
print("RAW HEX of first moof (first 128 bytes):")
for i in range(0, min(128, len(moof_data)), 16):
    chunk = moof_data[i:i+16]
    hex_part = ' '.join('%02x' % b for b in chunk)
    asc_part = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
    print('  %04x: %-47s  %s' % (i, hex_part, asc_part))

print()
print("Parsing moof children:")

pos = 0
end = len(moof_data)
# Level 0: moof itself starts at 0 with size=1816, type='moof'
# so children start at offset 8
pos = 8  # skip moof header
while pos + 8 <= end:
    size = r32(moof_data, pos)
    btype = fc(r32(moof_data, pos+4))
    print(f'  [{pos}] box={btype!r} size={size}')
    if size < 8:
        break
    if btype == 'traf':
        # parse traf children
        traf_end = pos + size
        cp = pos + 8
        while cp + 8 <= traf_end:
            csz = r32(moof_data, cp)
            ctype = fc(r32(moof_data, cp+4))
            print(f'    [{cp}] box={ctype!r} size={csz}')
            if csz < 8:
                break
            if ctype == 'tfhd':
                p = cp + 8
                ver_flags = r32(moof_data, p)
                flags = ver_flags & 0xFFFFFF
                track_id = r32(moof_data, p+4)
                print(f'      tfhd: flags=0x{flags:06x} track_id={track_id}')
                off = p + 8
                if flags & 0x01: print(f'        base_data_offset={struct.unpack_from(">Q",moof_data,off)[0]}'); off+=8
                if flags & 0x02: print(f'        sdi={r32(moof_data,off)}'); off+=4
                if flags & 0x08: print(f'        default_dur={r32(moof_data,off)}'); off+=4
                if flags & 0x10: print(f'        default_size={r32(moof_data,off)}'); off+=4
                if flags & 0x20: print(f'        default_flags=0x{r32(moof_data,off):08x}'); off+=4
            elif ctype == 'trun':
                p = cp + 8
                ver_flags = r32(moof_data, p)
                flags = ver_flags & 0xFFFFFF
                sc = r32(moof_data, p+4)
                print(f'      trun: flags=0x{flags:06x} sample_count={sc}')
                off = p + 8
                if flags & 0x001:
                    do_ = struct.unpack_from('>i', moof_data, off)[0]
                    print(f'        data_offset={do_}  (absolute in file: 976+{do_}={976+do_})')
                    off += 4
                if flags & 0x004:
                    print(f'        first_sample_flags=0x{r32(moof_data,off):08x}')
                    off += 4
                for i in range(min(5, sc)):
                    sd = ss = None
                    if flags & 0x100: sd = r32(moof_data, off); off += 4
                    if flags & 0x200: ss = r32(moof_data, off); off += 4
                    if flags & 0x400: off += 4
                    if flags & 0x800: off += 4
                    print(f'        sample[{i}]: dur={sd} size={ss}')
                if sc > 5: print(f'        ... ({sc-5} more)')
            cp += csz
    pos += size
