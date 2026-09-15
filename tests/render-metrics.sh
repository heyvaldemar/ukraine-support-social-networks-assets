#!/usr/bin/env bash
# render-metrics.sh - ask the renderer whether the numbers this repository is
# built on are still the numbers it produces.
#
# Every line of type in these images is placed by arithmetic over three advance
# widths measured inside the pinned container. Nothing about that arithmetic is
# self-checking: if the widths stop being true, the generator keeps producing
# well-formed SVG, the renderer keeps producing PNGs of exactly the right size,
# CI keeps passing, and the text walks off the edge of the image.
#
# The way they stop being true is not exotic. This container has no Helvetica
# and no Arial. Ask for either and fontconfig answers with WenQuanYi Zen Hei, a
# Chinese face that also covers Latin, and it answers silently. Move the pin to
# a rebuilt image that drops Open Sans and every asset in this repository is
# quietly set in a different typeface at different widths.
#
# So this measures. And it ends by measuring Helvetica too, which must NOT come
# back with Open Sans's numbers: if that assertion ever passes, the fallback it
# is here to detect has already happened and the rest of this file is measuring
# the wrong font against itself.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

# shellcheck disable=SC2016  # a sed pattern matching a literal ${...} in another file
IMAGE="$(sed -n 's/^IMAGE="\${RENDER_IMAGE:-\(.*\)}"$/\1/p' tools/render.sh)"
[ -n "$IMAGE" ] || { echo "could not read the pinned renderer out of tools/render.sh"; exit 1; }

TOLERANCE=0.02   # ems. The measurement is deterministic for a given image, so
                 # this is room for a Chromium point release rounding
                 # differently, not room for a different typeface: the gap
                 # between Open Sans and the fallback is 1.5 ems.

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# mktemp -d gives mode 700, and the container runs as its own unprivileged
# user rather than as whoever started it. On Linux it therefore cannot enter
# the directory it was handed. Docker Desktop on macOS does not carry
# ownership through and hides this entirely, so the first run that saw it was
# a CI run.
chmod 0777 "$WORK"

python3 - "$WORK/measure.html" <<'PY'
import json
import subprocess
import sys

rows = subprocess.run([sys.executable, "tools/build-assets.py", "--metrics"],
                      capture_output=True, text=True, check=True).stdout.strip().split("\n")
jobs = []
for row in rows:
    key, text, weight, _advance = row.split("\t")
    jobs.append([key, text, int(weight), "Open Sans"])
# The negative control, described at the top of the shell script: the same
# string, the same weight, a family this container does not have.
jobs.append(["control-helvetica", rows[0].split("\t")[1], 800, "Helvetica"])

with open(sys.argv[1], "w") as f:
    f.write("<!doctype html><meta charset=\"utf-8\"><body><pre id=\"out\"></pre><script>\n")
    f.write("const JOBS = %s;\n" % json.dumps(jobs))
    f.write("""
const c = document.createElement("canvas").getContext("2d");
document.getElementById("out").textContent = JOBS.map(([key, text, weight, family]) => {
  c.font = weight + " 100px '" + family + "'";
  return key + " " + (c.measureText(text).width / 100).toFixed(4);
}).join("\\n");
</script></body>""")
PY

chmod 0644 "$WORK/measure.html"
# The renderer's own output is kept rather than discarded. Sent to /dev/null,
# every possible failure here arrives as the same empty string, and an empty
# string cannot say which one happened.
docker run --rm -v "$WORK:/w" "$IMAGE" \
  --no-sandbox --headless --disable-gpu --virtual-time-budget=4000 \
  --dump-dom file:///w/measure.html >"$WORK/dom" 2>"$WORK/err"
measured="$(sed -n '/<pre/,/<\/pre>/p' "$WORK/dom" | sed 's/<[^>]*>//g')"

if [ -z "$measured" ]; then
  echo "the renderer measured nothing. It said:"
  sed 's/^/    /' "$WORK/err"
  echo "  and returned $(wc -c <"$WORK/dom") bytes of document."
  exit 1
fi

pass=0
fail=0
get() { printf '%s\n' "$measured" | awk -v k="$1" '$1==k{print $2}'; }

while IFS=$'\t' read -r key text weight recorded; do
  got="$(get "$key")"
  if [ -z "$got" ]; then
    printf '  FAIL  %s was not measured at all\n' "$key"
    fail=$((fail + 1))
    continue
  fi
  if awk -v a="$got" -v b="$recorded" -v t="$TOLERANCE" 'BEGIN{exit !((a-b<t)&&(b-a<t))}'; then
    printf '  ok    %-9s %-20s weight %s: %s em, as recorded\n' "$key" "$text" "$weight" "$got"
    pass=$((pass + 1))
  else
    printf '  FAIL  %s: tools/build-assets.py records %s em, the renderer says %s em\n' "$key" "$recorded" "$got"
    printf '        every image in this repository is laid out on that number\n'
    fail=$((fail + 1))
  fi
done < <(python3 tools/build-assets.py --metrics)

# The check on the check.
headline="$(get headline)"
control="$(get control-helvetica)"
if awk -v a="$headline" -v b="$control" -v t="$TOLERANCE" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d>t)}'; then
  printf '  ok    Helvetica is still absent and still substituted (%s em, not %s)\n' "$control" "$headline"
  pass=$((pass + 1))
else
  printf '  FAIL  Helvetica now measures the same as Open Sans (%s em)\n' "$control"
  printf '        either the image gained Helvetica or Open Sans is gone and both\n'
  printf '        names now resolve to the same substitute; the measurements above\n'
  printf '        compared that substitute against itself and proved nothing\n'
  fail=$((fail + 1))
fi

printf '\n%d passed, %d failed  (renderer %s)\n' "$pass" "$fail" "${IMAGE##*@}"
[ "$fail" -eq 0 ]
