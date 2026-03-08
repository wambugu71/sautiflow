import struct, glob, os

# Find the SCAR file
paths = (glob.glob(r'C:\Users\wambugukinyua\Downloads\SCAR*SHARE*.m4a') +
         glob.glob(r'C:\Users\wambugukinyua\Downloads\*SHARE*.m4a') +
         glob.glob(r'C:\Users\wambugukinyua\Downloads\SCAR*.m4a'))
if not paths:
    print('ERROR: SCAR m4a file not found in Downloads')
    exit(1)
path = paths[0]
print('Testing file:', path)
print('File size:', os.path.getsize(path))

def r32(d, o):
    return struct.unpack_from('>I', d, o)[0]

def fc(v):
    return bytes([(v>>24)&0xFF,(v>>16)&0xFF,(v>>8)&0xFF,v&0xFF]).decode('latin-1', errors='.')

# Read enough header data
with open(path, 'rb') as f:
    header = f.read(65536)

# Scan for top-level boxes
i = 0
moof_pos = None
moof_size = 0
print('\nTop-level boxes:')
while i + 8 <= len(header):
    sz = r32(header, i)
    if sz < 8:
        break
    tp = fc(r32(header, i+4))
    print(f'  {tp} at={i} size={sz}')
    if tp == 'moof':
        moof_pos = i
        moof_size = sz
        break
    i += sz

if moof_pos is None:
    print('\nERROR: No moof found in first 64KB')
    exit(1)

print(f'\nFirst moof: offset={moof_pos} size={moof_size}')
moof_data = header[moof_pos:moof_pos+moof_size]

# Parse tfhd and trun inside the moof
p = 8  # skip moof header
while p + 8 <= len(moof_data):
    sz = r32(moof_data, p)
    tp = fc(r32(moof_data, p+4))
    if sz < 8:
        break
    if tp == 'traf':
        cp = p + 8
        while cp + 8 <= p + sz:
            csz2 = r32(moof_data, cp)
            ctp2 = fc(r32(moof_data, cp+4))
            if ctp2 == 'tfhd':
                vf = r32(moof_data, cp+8)
                flags = vf & 0xFFFFFF
                track = r32(moof_data, cp+12)
                print(f'\n  tfhd: flags=0x{flags:06x} track_id={track}')
                has_base = bool(flags & 0x01)
                is_moof_relative = bool(flags & 0x020000)
                print(f'    base-data-offset-present: {has_base}')
                print(f'    default-base-is-moof:     {is_moof_relative}')
                if has_base:
                    base = struct.unpack_from('>Q', moof_data, cp+16)[0]
                    print(f'    base_data_offset = {base}')
            elif ctp2 == 'trun':
                vf = r32(moof_data, cp+8)
                flags = vf & 0xFFFFFF
                sc = r32(moof_data, cp+12)
                print(f'\n  trun: flags=0x{flags:06x} sample_count={sc}')
                off = cp + 16
                if flags & 0x001:
                    do_ = struct.unpack_from('>i', moof_data, off)[0]
                    abs_offset = moof_pos + do_
                    print(f'    data_offset={do_} => absolute file offset = {moof_pos} + {do_} = {abs_offset}')
                    with open(path, 'rb') as f2:
                        f2.seek(abs_offset)
                        sample0_bytes = f2.read(16)
                    print(f'    First 16 bytes at {abs_offset}: {sample0_bytes.hex()}')
                    # Check if it looks like an AAC syncword or ADTS header:
                    # ADTS starts with 0xFFF... Our decoder uses raw AAC (no ADTS)
                    # Just check non-zero
                    if all(b == 0 for b in sample0_bytes):
                        print('    WARNING: First sample bytes are ALL ZEROS -- bad offset!')
                    else:
                        print('    OK: Non-zero sample data found at this offset')
                    off += 4
                # Check first few sample sizes
                print('    First samples (size only):')
                for j in range(min(5, sc)):
                    if flags & 0x100:
                        dur = r32(moof_data, off); off += 4
                    else:
                        dur = None
                    if flags & 0x200:
                        size = r32(moof_data, off); off += 4
                    else:
                        size = None
                    if flags & 0x400: off += 4
                    if flags & 0x800: off += 4
                    print(f'      sample[{j}]: dur={dur} size={size}')
            cp += csz2
    p += sz

print('\nDone.')
