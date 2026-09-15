#!/usr/bin/env python3
"""Draw every image in this repository from one description.

    tools/build-assets.py             write the vector sources into src/
    tools/build-assets.py --check     report any source that is not what this
                                      file produces, and change nothing
    tools/build-assets.py --manifest  print the build plan, tab separated

WHY THE IMAGES ARE GENERATED. A folder of PNGs is a folder nobody can correct.
The wording, the colours and the destination are baked into pixels, and fixing
a typo means finding whoever made them and hoping they still have the original.
The set this replaced had two different destinations in it, one inside the
banner and a different one in the README, and nothing that could have noticed.
Here the destination is one constant, every image is a function of it, and CI
fails if a published file stops matching the source it came from.

THE FLAG IS 50/50 AND STAYS THAT WAY. It is a national flag, not a layout
device. Everything else is arranged around it.

THE TYPE IS FITTED, NOT GUESSED. The em widths below were measured inside the
renderer rather than estimated, and tests/render-metrics.sh re-measures them on
every run. That matters more than it sounds. The render container has no
Helvetica and no Arial; asking for either yields WenQuanYi Zen Hei, a Chinese
face that also covers Latin, and it does so silently and at different widths.
Every line here is placed by arithmetic over those numbers, so numbers that
quietly stopped being true would move text off the edge of an image that CI had
already called green.
"""
import argparse
import os
import sys

# --- the design -------------------------------------------------------------

BLUE, YELLOW, WHITE, INK = "#0057B7", "#FFD700", "#FFFFFF", "#111111"

# The one destination. UNITED24 is the Ukrainian government's own fundraising
# platform, which is why this is a .gov.ua address and not a charity's.
DESTINATION = "https://u24.gov.ua/"
HEADLINE, CALL, URL_TEXT = "STAND WITH UKRAINE", "DONATE VIA UNITED24", "u24.gov.ua"

# What each line measures. The advance width is in ems at the weight the line
# is set in, measured with canvas measureText at 100px inside the renderer that
# tools/render.sh pins, not estimated from a character count.
# tests/render-metrics.sh re-measures all three and fails if they move.
#
#        line         text        weight  advance (em)  letter-spacing (em)
MEASURED = {
    "headline": (HEADLINE,  800,   11.3032,      0.03),
    "call":     (CALL,      700,   11.2915,      0.05),
    "url":      (URL_TEXT,  600,    5.2407,      0.02),
}


def line_em(key):
    """Total width of a line in ems, advance plus its letter-spacing. SVG adds
    the spacing after every glyph including the last, so the count is the whole
    string, not one less."""
    text, _weight, advance, spacing = MEASURED[key]
    return advance + spacing * len(text)


HEADLINE_EM = line_em("headline")
CALL_EM = line_em("call")
URL_EM = line_em("url")
CAP = 0.714          # cap height of Open Sans as a fraction of the em
DESCENDER = 0.27     # how far the g in gov drops below the baseline

SAFE = 0.74          # widest the headline may be, as a fraction of the frame.
                     # Every one of these platforms crops on some device, and a
                     # message that survives the crop is worth more than one
                     # that fills the canvas.
HEADLINE_MAX = 0.55  # and no taller than this fraction of the blue half, which
                     # is what holds the short wide banner together.

# Open Sans first because that is the face these images are fitted to and the
# one the renderer has. The rest are for a browser opening the .svg on its own:
# each is narrower than Open Sans ExtraBold, so a substituted face makes the
# line shorter than the space reserved for it and cannot overflow.
FONTS = "'Open Sans','Helvetica Neue',Helvetica,Arial,sans-serif"

# src/<name>.svg is drawn here; images/<name>.png is what render.sh produces
# from it. The names under images/ are the names this repository has already
# published: other people's READMEs point at those raw URLs, and renaming a
# file to tidy up its spelling would break every one of them.
FORMATS = [
    # (name, width, height, what it is for)
    ("github-banner",              1200,  240, "README banner, for a repository, profile or organization"),
    ("linkedin-cover",             1584,  396, "LinkedIn profile cover"),
    ("twitter-header",             1500,  500, "X/Twitter profile header"),
    ("facebook-cover",             1640,  624, "Facebook page cover"),
    ("facebook-post",              1200,  630, "Facebook post and general link preview"),
    ("instagram-post",             1080, 1080, "Instagram square post"),
    ("instagram-post-rectangular", 1080, 1350, "Instagram portrait post"),
    ("instagram-story",            1080, 1920, "Instagram and Facebook story"),
]

# The banner also ships as a vector, because it is the one image that gets
# embedded in somebody's README, where it is scaled to a column width nobody
# can predict. The other seven ship as PNG because that is what the platforms
# accept for a cover or a post.
SHIPS_AS_VECTOR = "github-banner"


def clamp(value, low, high):
    return max(low, min(high, value))


def layout(w, h):
    """Every measurement in one place, so a change to the design is a change to
    arithmetic rather than to eight hand-placed files.

    The headline sits above the split and the call to action below it, and both
    are held within a distance of the split measured in multiples of their own
    type size. Centring each line in its own half is the obvious rule and it is
    wrong: on a 1920-pixel story it leaves nine hundred pixels of empty flag
    between the two, and they stop reading as one message. The clamp is what
    makes the 240-pixel banner and the 1920-pixel story one design rather than
    two that happen to share a palette. On the banner it does not bind and the
    arithmetic is the plain centring; on the tall formats it pulls the lines
    together onto the split."""
    half = h / 2.0
    head = min(SAFE * w / HEADLINE_EM, HEADLINE_MAX * half)
    call = head * 0.60
    url = call * 0.68

    gap_above = clamp(half / 2.0 - head * CAP / 2.0, 0.55 * head, 1.60 * head)
    head_baseline = half - gap_above

    gap = url * 0.45
    block = call * CAP + gap + url * CAP
    gap_below = clamp(half / 2.0 - block / 2.0, 0.50 * call, 1.50 * call)
    call_baseline = half + gap_below + call * CAP
    url_baseline = call_baseline + gap + url * CAP
    return half, head, call, url, head_baseline, call_baseline, url_baseline


def fits(w, h):
    """True when every line is inside the frame with its ink, not merely its
    baseline. Run on every format before anything is written: a layout that
    overflows on one aspect ratio should never reach a file."""
    half, head, call, url, hb, cb, ub = layout(w, h)
    return (head * HEADLINE_EM <= w
            and call * CALL_EM <= w
            and url * URL_EM <= w
            and hb - head * CAP >= 0
            and hb <= half
            and cb - call * CAP >= half
            and ub + url * DESCENDER <= h)


def svg(w, h, link):
    half, head, call, url, hb, cb, ub = layout(w, h)
    label = "Stand with Ukraine. Donate via UNITED24 at %s" % URL_TEXT
    open_a = '<a href="%s" target="_blank" rel="noopener noreferrer">' % DESTINATION if link else ""
    close_a = "</a>" if link else ""

    def line(y, size, fill, weight, spacing, text):
        return ('    <text x="%.1f" y="%.1f" fill="%s" font-size="%.2f" '
                'font-weight="%d" letter-spacing="%.3f">%s</text>'
                % (w / 2.0, y, fill, size, weight, size * spacing, text))

    return """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" role="img" aria-label="%s">
  <title>%s</title>
  <rect width="%d" height="%d" fill="%s"/>
  <rect width="%d" height="%.1f" fill="%s"/>
  %s<g font-family="%s" text-anchor="middle">
%s
%s
%s
  </g>%s
</svg>
""" % (w, h, w, h, label, label,
       w, h, YELLOW,
       w, half, BLUE,
       open_a, FONTS,
       line(hb, head, WHITE, 800, 0.03, HEADLINE),
       line(cb, call, INK, 700, 0.05, CALL),
       line(ub, url, BLUE, 600, 0.02, URL_TEXT),
       close_a)


def plan(root):
    """name -> (source path, png path, shipped svg path or None, w, h, use)."""
    out = {}
    for name, w, h, use in FORMATS:
        if not fits(w, h):
            raise SystemExit("the design does not fit %s at %dx%d" % (name, w, h))
        ships = name == SHIPS_AS_VECTOR
        out[name] = (os.path.join("src", "%s.svg" % name),
                     os.path.join("images", "%s.png" % name),
                     os.path.join("images", "%s.svg" % name) if ships else None,
                     w, h, use)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="report sources that differ from what this file produces")
    ap.add_argument("--manifest", action="store_true",
                    help="print name, source, image, shipped vector, width, height, purpose")
    ap.add_argument("--metrics", action="store_true",
                    help="print the type measurements this file is built on")
    ap.add_argument("--root", default=".")
    a = ap.parse_args()
    built = plan(a.root)

    if a.metrics:
        # tests/render-metrics.sh reads these and asks the renderer for the
        # same numbers, rather than keeping a second copy that can drift.
        for key in ("headline", "call", "url"):
            text, weight, advance, _spacing = MEASURED[key]
            print("\t".join([key, text, str(weight), "%.4f" % advance]))
        return

    if a.manifest:
        # The renderer and both test suites read this instead of keeping their
        # own copy of the list, so a format cannot be added in one place and
        # forgotten in another.
        for name, w, h, use in [(n, w, h, u) for n, w, h, u in FORMATS]:
            src, png, vec, w, h, use = built[name]
            print("\t".join([name, src, png, vec or "-", str(w), str(h), use]))
        return

    if a.check:
        drift = []
        for name in sorted(built):
            src, _png, _vec, w, h, _use = built[name]
            path = os.path.join(a.root, src)
            want = svg(w, h, name == SHIPS_AS_VECTOR)
            if not os.path.exists(path):
                drift.append("%s is missing" % src)
            elif open(path, encoding="utf-8").read() != want:
                drift.append("%s is not what tools/build-assets.py produces" % src)
        for d in drift:
            print("::error::%s" % d)
        if drift:
            print("\nrun tools/build-assets.py, then tools/render.sh")
            sys.exit(1)
        print("all %d vector sources match the generator" % len(built))
        return

    for name in sorted(built):
        src, _png, _vec, w, h, _use = built[name]
        path = os.path.join(a.root, src)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(svg(w, h, name == SHIPS_AS_VECTOR))
        print("wrote", src)


if __name__ == "__main__":
    main()
