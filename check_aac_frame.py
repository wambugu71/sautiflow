"""
Decode the first AAC frame from the SCAR m4a file to verify FAAD2 would get valid data.
We use the fMP4 offsets from the analysis.
"""
import struct, glob

path = glob.glob(r'C:\Users\wambugukinyua\Downloads\SCAR*.m4a')[0]
print(f'File: {path}')

def r32(d, o): return struct.unpack_from('>I', d, o)[0]
def fc(v): return bytes([(v>>24)&0xFF,(v>>16)&0xFF,(v>>8)&0xFF,v&0xFF]).decode('latin-1', errors='.')

with open(path, 'rb') as f:
    header = f.read(8192)

# Find moof position
i = 0
moof_pos = None
while i + 8 <= len(header):
    sz = r32(header, i)
    if sz < 8: break
    tp = fc(r32(header, i+4))
    if tp == 'moof':
        moof_pos = i
        moof_size = sz
        break
    i += sz

print(f'moof at {moof_pos}, size {moof_size}')

# Parse to get data_offset and first sample sizes
moof_data = header[moof_pos:moof_pos+moof_size]
p = 8
data_offset = None
sample_sizes = []

def parse_traf(data, start, end):
    global data_offset, sample_sizes
    cp = start
    while cp + 8 <= end:
        csz = r32(data, cp)
        ctp = fc(r32(data, cp+4))
        if csz < 8: break
        if ctp == 'trun':
            off = cp + 8
            vf = r32(data, off); off += 4
            flags = vf & 0xFFFFFF
            sc = r32(data, off); off += 4
            if flags & 0x001:
                data_offset = struct.unpack_from('>i', data, off)[0]; off += 4
            for i in range(sc):
                if flags & 0x100: off += 4
                if flags & 0x200:
                    ss = r32(data, off); off += 4
                    sample_sizes.append(ss)
                if flags & 0x400: off += 4
                if flags & 0x800: off += 4
        cp += csz

while p + 8 <= len(moof_data):
    sz = r32(moof_data, p)
    tp = fc(r32(moof_data, p+4))
    if tp == 'traf':
        parse_traf(moof_data, p+8, p+sz)
    p += sz

print(f'data_offset={data_offset}')
print(f'sample_sizes[:5]={sample_sizes[:5]}')

if data_offset is None or not sample_sizes:
    print('Could not parse fMP4 structure')
    exit(1)

abs_offset = moof_pos + data_offset
print(f'First sample at absolute offset: {abs_offset}, size: {sample_sizes[0]}')

# Read first sample bytes
with open(path, 'rb') as f:
    f.seek(abs_offset)
    sample0 = f.read(sample_sizes[0])

print(f'Sample 0 ({len(sample0)} bytes):')
for i in range(0, min(64, len(sample0)), 16):
    chunk = sample0[i:i+16]
    print('  ' + ' '.join(f'{b:02x}' for b in chunk))

# Check if it could be valid AAC (raw AAC starts with SyntaxElement ID and other bits)
# Raw AAC (as used in MP4) does not have ADTS header
# Just check that it's not all zeros
nonzero = sum(1 for b in sample0 if b != 0)
print(f'\nNon-zero bytes: {nonzero}/{len(sample0)}')
if nonzero > 0:
    print('Payload looks valid (non-zero bytes present)')
else:
    print('WARNING: Payload is all zeros!')
