# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.0] - 2026-09-15

The whole set redrawn, pointed at UNITED24, and put under checks. Every file
name under `images/` is the name it had before, because other people's READMEs
point at those raw URLs and renaming a file to tidy up its spelling would break
every one of them.

### Added

- **The address is on the artwork.** Every image now carries `u24.gov.ua` in
  the picture itself. A LinkedIn cover is not a link, an Instagram story is not
  a link, and a screenshot of either is not a link, so the previous set asked
  for the donation in the one place a reader could not act on it: the images
  carried no call to action and no address at all, and the only way to reach
  anything was to hover over a banner in a README.
- **Every image is generated.** [`tools/build-assets.py`](tools/build-assets.py)
  draws all eight vector sources from one description; `tools/render.sh` turns
  each into its PNG. The wording, the colours and the destination are three
  constants at the top of one file instead of pixels in eight, so a correction
  is an edit and a re-render rather than a search for whoever still has the
  originals. `src/` is what a person edits, `images/` is what the scripts
  produce, and nothing is both.
- **The type is fitted to measured widths, not guessed.** Three advance widths
  measured with `measureText` inside the renderer, and every line placed by
  arithmetic over them. The layout holds a headline to 74 percent of the frame
  and clamps both lines to the flag's centre line, which is what makes a
  240-pixel banner and a 1920-pixel story one design instead of two that share
  a palette.
- **A renderer pinned by digest.** `zenika/alpine-chrome@sha256:eb3378c1ed00…`,
  in a container, because a local Chrome, a local Inkscape and a local
  `rsvg-convert` disagree about font substitution and the disagreement is
  invisible until two files that should match do not. Both scripts that drive
  it widen the temporary directory they hand it and keep its stderr: the
  container runs as its own unprivileged user, `mktemp -d` gives mode 700, and
  on Linux the renderer therefore cannot enter the directory it was given.
  Docker Desktop does not carry ownership through and hides this completely,
  so the first run that saw it was a CI run, and all it could say was that
  nothing came back.
- **[`tests/assets-are-what-they-claim.sh`](tests/assets-are-what-they-claim.sh)**:
  130 assertions, no dependencies beyond `bash` and `python3`. It decodes every
  published PNG and checks the dimensions against the README table, that the
  flag's blue and yellow each cover their half, and that white and dark ink are
  present, because a render that failed silently is a valid PNG of the right
  size and only what is drawn on it tells the two apart. It also checks the
  palette, the font stack, the screen-reader labelling, that no source reaches
  outside itself, that the published files are what the generator makes, that
  the README lists every file that exists and none that does not, that the
  contrast ratios it states are the ones the colours give, and that both suites
  are wired into CI. Every one of these was shown a real violation and failed
  on it.
- **[`tests/render-metrics.sh`](tests/render-metrics.sh)**: re-measures the
  three advance widths inside the pinned renderer. Nothing about the layout
  arithmetic is self-checking: if the widths stop being true the generator
  still emits well-formed SVG, the renderer still emits PNGs of exactly the
  right size, and the text walks off the edge of an image CI has called green.
  It ends by measuring Helvetica, which must **not** return Open Sans's
  numbers; if that ever passes, the substitution it exists to detect has
  already happened and every measurement above it compared one font against
  itself.
- **`tools/png-size.py` and `tools/png-ink.py`** read PNG headers and pixels
  with nothing but the standard library. A dependency that has to be installed
  is the one that will be missing on the machine where it matters.
- **`tools/contrast.py`**, run over every ratio the README states. A stated
  accessibility number that nothing recomputes outlives the colour it
  described.
- **A CHANGELOG**, and the first tagged release. The set had been edited in
  place since 2021 with no version anyone could point at.

### Changed

- **One destination, and it is UNITED24.** `u24.gov.ua` is the Ukrainian
  government's own fundraising platform, on a `.gov.ua` domain, publishing
  where the money went.
- **LinkedIn cover 1584x387 to 1584x396**, nine pixels short of the ratio
  LinkedIn crops to, and **Facebook cover 820x360 to 1640x624**. The new sizes
  are the ones each platform has used for years; they are not quoted from a
  vendor page, because those pages move and the sizes this set shipped with
  matched no current spec at all.
- **The banner ships as both a vector and a PNG.** It is the one image that
  gets embedded in somebody else's README, at a column width nobody can
  predict.
- **The font stack names Open Sans first** and ends in a generic family. The
  images are fitted to Open Sans metrics, and every other face in the stack is
  narrower, so a browser that substitutes draws a shorter line than the space
  reserved for it and cannot overflow.

### Removed

- **Two third-party domains.** The banner sent people to one and the README
  link beside it sent them to another. Neither is an address this repository
  controls, both were reachable only by hovering, and nothing here could have
  noticed they disagreed. The check that now guards this is the direct result.
- **A `@media (max-width: 770px)` block inside the old banner.** An SVG
  embedded as an image has no page to measure, so the rule could never fire.
  It read as responsive behaviour and was decoration.
- **`Helvetica, Arial, sans-serif` as the first thing asked for.** The render
  container has neither, and fontconfig answers with WenQuanYi Zen Hei, a
  Chinese face that also covers Latin. It substitutes silently, at different
  widths, and the image still renders.

[Unreleased]: https://github.com/heyvaldemar/ukraine-support-social-networks-assets/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/ukraine-support-social-networks-assets/releases/tag/v1.0.0
