import struct

def read32be(data, off):
    return struct.unpack_from('>I', data, off)[0]

def fourcc(v):
    return bytes([(v>>24)&0xFF,(v>>16)&0xFF,(v>>8)&0xFF,v&0xFF]).decode('latin-1')

path = r'C:\Users\wambugukinyua\Downloads\iLoveYt.net_YouTube_Naughty-Boy-Sam-Smith-La-la-la-Lyrics_Media_2WmBa1CviYE_008_128k.m4a'

# Parse first moof at offset 976, size 1816
with open(path, 'rb') as f:
    f.seek(976)
    moof_data = f.read(1816)

def parse_children(data, offset, end, depth=0):
    pos = offset
    while pos + 8 <= end:
        size = read32be(data, pos)
        btype = fourcc(read32be(data, pos+4))
        payload = data[pos+8:pos+size]
        print(' ' * depth*2 + '%s size=%d (payload=%d bytes)' % (btype, size, len(payload)))
        if btype in ('moof', 'traf', 'mfhd'):
            parse_children(data, pos+8, pos+size, depth+1)
        elif btype == 'tfhd':
            ver_flags = read32be(payload, 0)
            flags = ver_flags & 0xFFFFFF
            track_id = read32be(payload, 4)
            print(' ' * (depth+1)*2 + 'tfhd: flags=0x%06x track_id=%d' % (flags, track_id))
            off = 8
            if flags & 0x01:
                v = struct.unpack_from('>Q', payload, off)[0]
                print(' '*(depth+1)*2 + '  base_data_offset = %d' % v)
                off += 8
            if flags & 0x02:
                print(' '*(depth+1)*2 + '  sample_desc_idx = %d' % read32be(payload, off))
                off += 4
            if flags & 0x08:
                print(' '*(depth+1)*2 + '  default_duration = %d' % read32be(payload, off))
                off += 4
            if flags & 0x10:
                print(' '*(depth+1)*2 + '  default_size = %d' % read32be(payload, off))
                off += 4
            if flags & 0x20:
                print(' '*(depth+1)*2 + '  default_flags = %08x' % read32be(payload, off))
                off += 4
        elif btype == 'trun':
            ver_flags = read32be(payload, 0)
            flags = ver_flags & 0xFFFFFF
            sample_count = read32be(payload, 4)
            print(' '*(depth+1)*2 + 'trun: flags=0x%06x sample_count=%d' % (flags, sample_count))
            off = 8
            data_offset = None
            if flags & 0x001:
                data_offset = struct.unpack_from('>i', payload, off)[0]
                print(' '*(depth+1)*2 + '  data_offset=%d (mdat starts at moof_start + %d = %d)' % (data_offset, data_offset, 976+data_offset))
                off += 4
            if flags & 0x004:
                print(' '*(depth+1)*2 + '  first_sample_flags=%08x' % read32be(payload, off))
                off += 4
            # Show first 5 samples
            for i in range(min(5, sample_count)):
                sd = ss = None
                if flags & 0x100: sd = read32be(payload, off); off += 4
                if flags & 0x200: ss = read32be(payload, off); off += 4
                if flags & 0x400: off += 4
                if flags & 0x800: off += 4
                print(' '*(depth+1)*2 + '  sample[%d]: dur=%s size=%s' % (i, sd, ss))
            if sample_count > 5:
                print(' '*(depth+1)*2 + '  ... (%d more samples)' % (sample_count - 5))
        pos += size

parse_children(moof_data, 0, len(moof_data))
