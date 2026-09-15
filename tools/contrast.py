#!/usr/bin/env python3
"""Contrast ratio between two colours, by the WCAG 2 definition.

    tools/contrast.py 0057B7 FFFFFF   ->  6.87

The README states these ratios. A stated accessibility number that nothing
recomputes is a number that stays in the file after the colour beside it
changes, which is worse than not stating one, so the test suite runs this over
every pair the README claims.
"""
import sys


def luminance(hexcolour):
    c = hexcolour.lstrip("#")
    parts = []
    for i in (0, 2, 4):
        v = int(c[i:i + 2], 16) / 255.0
        parts.append(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4)
    r, g, b = parts
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


if __name__ == "__main__":
    print("%.2f" % ratio(sys.argv[1], sys.argv[2]))
