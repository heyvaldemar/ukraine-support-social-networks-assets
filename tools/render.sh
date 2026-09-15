#!/usr/bin/env bash
# render.sh - turn the vector sources into the PNGs the platforms take.
#
# The renderer is a pinned Chromium in a container, not whatever is installed
# on the machine running this. That is the only way two people, or a person and
# CI, get the same pixels: a local Chrome, a local Inkscape and a local
# rsvg-convert disagree about font fallback, and the disagreement is invisible
# until someone compares two files that should be identical.
#
# The SVG is inlined into a bare HTML page rather than loaded through <img>,
# because an SVG loaded as an image resolves fonts differently in some builds,
# and the fitted type in these files has no room for that kind of surprise.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# zenika/alpine-chrome, pinned by digest. A tag would let a rebuilt image change
# the type metrics under a green CI run; tests/render-metrics.sh is what notices
# if this pin is ever moved to a build whose fonts differ.
IMAGE="${RENDER_IMAGE:-zenika/alpine-chrome@sha256:eb3378c1ed0079f94db054a5fe1aaa790a254ec0d6bbc67eda052420d86a179d}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
while IFS=$'\t' read -r name svg png vec w h _use; do
  {
    printf '<!doctype html><meta charset="utf-8">'
    printf '<style>html,body{margin:0;padding:0;overflow:hidden}svg{display:block}</style>'
    cat "$ROOT/$svg"
  } > "$WORK/$name.html"

  docker run --rm -v "$WORK:/w" "$IMAGE" \
    --no-sandbox --headless --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --virtual-time-budget=4000 \
    --window-size="$w,$h" --screenshot="/w/$name.png" "file:///w/$name.html" >/dev/null 2>&1

  if [ ! -s "$WORK/$name.png" ]; then
    echo "render failed: $name produced no image" >&2
    fail=1
    continue
  fi
  # A screenshot at the wrong size is the failure this pipeline actually has:
  # Chrome will happily letterbox or clip and say nothing. Check here, at the
  # point it happened, rather than leaving it for the test suite to find later.
  got="$(python3 "$ROOT/tools/png-size.py" "$WORK/$name.png")"
  if [ "$got" != "${w}x${h}" ]; then
    echo "render failed: $name came out $got, the design says ${w}x${h}" >&2
    fail=1
    continue
  fi
  mkdir -p "$ROOT/$(dirname "$png")"
  cp "$WORK/$name.png" "$ROOT/$png"
  chmod 0644 "$ROOT/$png"
  echo "rendered $png  ${w}x${h}"
  if [ "$vec" != "-" ]; then
    # The banner also ships as a vector. It is published rather than sourced,
    # so it is copied here beside the image it was rendered from instead of
    # being edited in place: src/ is what a person changes, images/ is what
    # this script produces, and nothing is both.
    cp "$ROOT/$svg" "$ROOT/$vec"
    echo "published $vec"
  fi
done < <(python3 "$ROOT/tools/build-assets.py" --manifest --root "$ROOT")

exit "$fail"
