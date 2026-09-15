#!/usr/bin/env bash
# assets-are-what-they-claim.sh - check the published images against the
# README, against the generator, and against each other.
#
# The failure this repository actually had was not an ugly picture. It was a
# banner that sent people to one third-party domain while the README link
# beside it sent them to a different one, for as long as nobody happened to
# hover over both. Nothing here could have caught that, because nothing here
# compared anything to anything.
#
# So every claim this repository makes out loud has a check underneath it: the
# sizes in the README table, the contrast ratios, the destination, the palette,
# and whether a PNG of exactly the right size has anything drawn on it at all.
# Each of these has been shown a real violation and failed on it. A check that
# cannot fail is not a check.
#
# Needs bash and python3. Nothing here renders, so it costs a second.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

DEST="https://u24.gov.ua/"
SVG_NS="http://www.w3.org/2000/svg"
COLOURS="#0057B7 #111111 #FFD700 #FFFFFF"
# The two destinations this set used to send people to, written with a bracket
# around one dot so that this line is not itself a hit. Without the bracket the
# check reads its own source, finds both names in it, and reports that a tree
# it has just cleaned is still dirty. The same shape as a pgrep pattern that
# matches the shell running the pgrep: a probe whose first result is itself.
RETIRED="stand-with-ukraine.pp[.]ua standforukraine[.]com"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }
nothing_wrong() { # label  detail-prefix  what-was-found (empty means fine)
  if [ -z "$3" ]; then ok "$1"; else no "$1: $2$3"; fi
}
same() { # label expected actual
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    no "$1"$'\n'"          expected: $2"$'\n'"          actual:   $3"
  fi
}
atleast() { # label minimum actual
  if awk -v a="$3" -v b="$2" 'BEGIN{exit !(a>=b)}'; then
    ok "$1 ($3)"
  else
    no "$1: $3 is below $2"
  fi
}
exists() { # path label
  if [ -f "$1" ]; then ok "$2 $1 exists"; else no "$2 $1 is missing"; fi
}

MANIFEST="$(python3 tools/build-assets.py --manifest --root .)"
[ -n "$MANIFEST" ] || { echo "the generator printed no manifest"; exit 1; }

echo "== the files the generator plans are the files that exist"
declared=""
while IFS=$'\t' read -r _name src png vec w h _use; do
  exists "$src" source
  exists "$png" image
  declared="$declared$png	${w}x${h}
"
  if [ "$vec" != "-" ]; then
    exists "$vec" vector
    if cmp -s "$src" "$vec"; then
      ok "$vec is byte-identical to $src"
    else
      no "$vec has drifted from $src; run tools/render.sh"
    fi
    declared="$declared$vec	${w}x${h}
"
  fi
done <<< "$MANIFEST"

echo "== no file under images/ is left over from a rename"
for f in images/*; do
  case "$declared" in
    *"$f"*) ok "$f is declared" ;;
    *) no "$f is under images/ but nothing declares it" ;;
  esac
done

echo "== every image is the size it is published as, and has something on it"
while IFS=$'\t' read -r _name _src png _vec w h _use; do
  same "$png is ${w}x${h}" "${w}x${h}" "$(python3 tools/png-size.py "$png")"
  ink="$(python3 tools/png-ink.py "$png" 0057B7 FFD700 FFFFFF 111111)"
  blue=$(printf '%s\n' "$ink" | awk '/^0057B7/{print $2}')
  yellow=$(printf '%s\n' "$ink" | awk '/^FFD700/{print $2}')
  white=$(printf '%s\n' "$ink" | awk '/^FFFFFF/{print $2}')
  dark=$(printf '%s\n' "$ink" | awk '/^111111/{print $2}')
  # A screenshot that failed silently is a valid PNG of the right size. Only
  # what is drawn on it separates the two, so this is the check that the render
  # happened rather than merely returned.
  atleast "$png blue half" 0.40 "$blue"
  atleast "$png yellow half" 0.40 "$yellow"
  atleast "$png white headline drew" 0.005 "$white"
  atleast "$png dark call to action drew" 0.001 "$dark"
  total=$(awk -v a="$blue" -v b="$yellow" -v c="$white" -v d="$dark" \
    'BEGIN{printf "%.6f", a+b+c+d}')
  atleast "$png is only the four declared colours" 0.95 "$total"
done <<< "$MANIFEST"

echo "== every source is self-contained"
for f in src/*.svg images/*.svg; do
  bad=""
  grep -qE '<image|<script|<style|xlink:href|@import' "$f" && bad="$bad reaches-outside"
  grep -qE 'url\(' "$f" && bad="$bad url()"
  while read -r u; do
    [ -n "$u" ] || continue
    case "$u" in
      "$SVG_NS" | "$DEST") ;;
      *) bad="$bad $u" ;;
    esac
  done < <(grep -oE 'https?://[^"'"'"'<> ]+' "$f" | sort -u)
  nothing_wrong "$f pulls in nothing external" "it reaches" "$bad"
done

echo "== every source is described to a screen reader"
for f in src/*.svg images/*.svg; do
  miss=""
  grep -q 'role="img"' "$f" || miss="$miss role"
  grep -q 'aria-label="Stand with Ukraine' "$f" || miss="$miss aria-label"
  grep -q '<title>Stand with Ukraine' "$f" || miss="$miss title"
  nothing_wrong "$f is labelled" "it is missing" "$miss"
done

echo "== every colour in every source is one of the four"
for f in src/*.svg images/*.svg; do
  stray=""
  while read -r c; do
    [ -n "$c" ] || continue
    case " $COLOURS " in *" $c "*) ;; *) stray="$stray $c" ;; esac
  done < <(grep -oE '#[0-9A-Fa-f]{6}' "$f" | tr 'a-f' 'A-F' | sort -u)
  nothing_wrong "$f uses only the declared palette" "it has" "$stray"
done

echo "== the type is asked for by a name the renderer has"
for f in src/*.svg images/*.svg; do
  # Open Sans must come first, because the images are fitted to its metrics,
  # and the stack must end in a generic family so a browser that has none of
  # them still draws the text.
  if grep -q "font-family=\"'Open Sans'," "$f" && grep -q 'sans-serif"' "$f"; then
    ok "$f asks for Open Sans first and a generic family last"
  else
    no "$f has the wrong font stack"
  fi
done

echo "== one destination, and it is UNITED24"
found="$(grep -rhoE 'https?://[a-z0-9.-]*u24[a-z0-9.-]*[^"'"'"')< ]*' . \
  --include='*.svg' --include='*.md' --include='*.py' --include='*.sh' --include='*.yml' \
  --exclude-dir=.git | sort -u)"
same "every u24 address is spelled the same way" "$DEST" "$found"
for d in $RETIRED; do
  plain="$(printf '%s' "$d" | tr -d '[]')"
  # -e, not "--": ending option parsing sends --exclude-dir=.git to grep as a
  # path, and grep then answers about a file that does not exist. That form was
  # here first, and it reported both retired domains as still present in a tree
  # that contained neither.
  if grep -rIq --exclude-dir=.git -e "$d" .; then
    no "the retired destination $plain is still somewhere in this repository"
  else
    ok "the retired destination $plain is gone"
  fi
done

echo "== the README lists exactly the files that exist, at their real sizes"
# shellcheck disable=SC2016  # the backticks below are markdown, matched literally
claimed="$(grep -E '^\| \[`images/' README.md \
  | sed -E 's/^\| \[`([^`]+)`\][^|]*\| *([0-9]+x[0-9]+) *\|.*/\1\t\2/' | sort)"
same "the README table matches the build plan" \
  "$(printf '%s' "$declared" | grep -v '^$' | sort)" "$claimed"

echo "== every image the README shows is in the repository"
while read -r p; do
  [ -n "$p" ] || continue
  if [ -f "$p" ]; then
    ok "README shows $p, which exists"
  else
    no "README shows $p, which does not exist"
  fi
done < <(grep -oE '\(images/[a-z0-9.-]+\)|src="images/[a-z0-9.-]+"' README.md \
  | sed -E 's/^\(|\)$|^src="|"$//g' | sort -u)

echo "== the contrast ratios the README states are the ones the colours give"
# shellcheck disable=SC2016  # the backticks below are markdown, matched literally
ratios="$(grep -E '^\| `#' README.md \
  | sed -E 's/^\| `(#[0-9A-Fa-f]{6})`[^|]*\| `(#[0-9A-Fa-f]{6})` *\| *([0-9.]+):1 *\|.*/\1 \2 \3/')"
while read -r fg bg stated; do
  [ -n "$fg" ] || continue
  same "$fg on $bg" "$stated" "$(python3 tools/contrast.py "$fg" "$bg")"
done <<< "$ratios"

echo "== the published files are what the generator produces"
if out="$(python3 tools/build-assets.py --check --root . 2>&1)"; then
  ok "no drift between src/ and tools/build-assets.py"
else
  no "the sources have drifted from the generator: $out"
fi

echo "== this suite is wired into CI"
for t in tests/assets-are-what-they-claim.sh tests/render-metrics.sh; do
  if grep -q "$t" .github/workflows/verify.yml; then
    ok "$t runs in CI"
  else
    no "$t exists but CI never runs it"
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
