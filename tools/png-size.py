#!/usr/bin/env python3
"""Print WIDTHxHEIGHT of a PNG, reading the header directly.

No Pillow, no ImageMagick, no sips. The renderer, the test suite and CI all
need this one number, and a dependency that has to be installed is a dependency
that will be missing on the one machine where it matters.
"""
import struct
import sys

with open(sys.argv[1], "rb") as f:
    head = f.read(24)
if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
    sys.exit("%s is not a PNG" % sys.argv[1])
print("%dx%d" % struct.unpack(">II", head[16:24]))
