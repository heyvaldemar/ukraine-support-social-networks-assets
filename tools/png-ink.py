#!/usr/bin/env python3
"""Report how much of a PNG is each of the given colours.

    tools/png-ink.py image.png 0057B7 FFD700 FFFFFF

prints one "RRGGBB share" line per colour, as a fraction of all pixels.

This exists so a test can tell a rendered image from a blank one. A screenshot
that failed silently is still a valid PNG of the right size; the only thing
that separates it from the real thing is what is drawn on it. Decoding here
rather than shelling out to ImageMagick or Pillow keeps the check runnable on
any machine with a Python, which is the machine the check will be needed on.
"""
import struct
import sys
import zlib


def rows(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit("%s is not a PNG" % path)
    pos, idat, hdr = 8, [], None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
        pos += 12 + length
    w, h, depth, colour, _comp, _filt, interlace = hdr
    if depth != 8 or colour not in (2, 6) or interlace != 0:
        sys.exit("%s: only 8-bit RGB/RGBA, non-interlaced, is supported" % path)
    bpp = 3 if colour == 2 else 4
    raw = zlib.decompress(b"".join(idat))
    stride = w * bpp
    out, prev, pos = [], bytearray(stride), 0
    for _ in range(h):
        ft = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ft == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
        elif ft != 0:
            sys.exit("%s: unknown filter %d" % (path, ft))
        out.append(bytes(line))
        prev = line
    return w, h, bpp, out


def main():
    path, wanted = sys.argv[1], [c.lstrip("#").upper() for c in sys.argv[2:]]
    w, h, bpp, lines = rows(path)
    total = w * h
    for c in wanted:
        px = bytes.fromhex(c) + (b"\xff" if bpp == 4 else b"")
        # bytes.count runs at C speed, which is what makes this check cheap
        # enough to run on a two-megapixel story image in CI.
        n = sum(line.count(px) for line in lines)
        print("%s %.6f" % (c, n / float(total)))


if __name__ == "__main__":
    main()
