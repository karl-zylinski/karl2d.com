#!/usr/bin/env sh
# Builds the Karl2D playground into the directory above this one, which is what
# karl2d.com serves at /playground: the Odin compiler as a WASI module, the
# packed ODIN_ROOT sources, the Karl2D examples, the Odin and Karl2D JS
# runtimes and the web pages. Everything but `_source` in that directory is
# built by this script and is not kept in git; the site's deploy workflow runs
# it and publishes the result.
#
# Usage: playground/_source/build_playground.sh
#   ODIN=dir       the wodin checkout, the fork of Odin with the wasm backend
#                  (default ../../../wodin, or ../../../Odin if that is the
#                  name the checkout has)
#   KARL2D=dir     the Karl2D checkout                   (default ../../../karl2d)
#   OUT=dir        where the built playground goes       (default ..)
#   ODIN_BIN=path  an Odin compiler to run the packer with (default $ODIN/odin,
#                  or `odin` from the PATH: any recent one will do, it only
#                  reads the sources it packs)
#   ODIN_WASM=path an already built compiler module, instead of building one
#                  (which needs wasi-sdk and takes a few minutes)
#   KARL2D_NO_UPDATE=1  do not fast-forward the Karl2D checkout first
set -eu

SRC=$(cd "$(dirname "$0")" && pwd)
if [ -z "${ODIN:-}" ]; then
	ODIN=$SRC/../../../wodin
	[ -d "$ODIN" ] || ODIN=$SRC/../../../Odin
fi
ODIN=$(cd "$ODIN" && pwd)
KARL2D=$(cd "${KARL2D:-$SRC/../../../karl2d}" && pwd)
mkdir -p "${OUT:=$SRC/..}"
OUT=$(cd "$OUT" && pwd)

# The playground ships Karl2D's sources, so it is built from origin/master and
# cannot quietly fall behind. A checkout that is dirty, on another branch or
# diverged is packed as it is (someone may be trying a change in the
# playground on purpose) but says so. KARL2D_NO_UPDATE=1 skips the fetch.
if [ -d "$KARL2D/.git" ]; then
	branch=$(git -C "$KARL2D" symbolic-ref --quiet --short HEAD || echo "(detached)")
	if [ -n "${KARL2D_NO_UPDATE:-}" ]; then
		echo "NOTE: not updating $KARL2D (KARL2D_NO_UPDATE is set)"
	elif [ -n "$(git -C "$KARL2D" status --porcelain)" ]; then
		echo "WARNING: $KARL2D has local changes: packing it as it is, not origin/master"
	elif [ "$branch" != master ]; then
		echo "WARNING: $KARL2D is on '$branch': packing it as it is, not origin/master"
	elif ! git -C "$KARL2D" fetch -q origin; then
		echo "WARNING: cannot reach $KARL2D's origin: packing what is checked out"
	elif ! git -C "$KARL2D" merge --ff-only -q origin/master; then
		echo "WARNING: $KARL2D cannot fast-forward to origin/master: packing it as it is"
	fi
	echo "Karl2D: $(git -C "$KARL2D" log --oneline -1)"
	echo "Odin:   $(git -C "$ODIN" log --oneline -1)"
fi

# An Odin compiler for the packer: the one built in the Odin checkout if it is
# there, otherwise whichever is on the PATH
if [ -z "${ODIN_BIN:-}" ]; then
	if [ -x "$ODIN/odin" ]; then
		ODIN_BIN="$ODIN/odin"
	elif ! ODIN_BIN=$(command -v odin); then
		echo "ERROR: no Odin compiler to run the packer with: build one in $ODIN or set ODIN_BIN"
		exit 1
	fi
fi

# A compiler module to reuse has to survive the cleaning of the output
if [ -n "${ODIN_WASM:-}" ]; then
	keep=$(mktemp -d)
	cp "$ODIN_WASM" "$keep/odin.wasm"
fi

# Everything in the output directory is built here, except the sources
find "$OUT" -mindepth 1 -maxdepth 1 ! -name _source -exec rm -rf {} +

if [ -n "${ODIN_WASM:-}" ]; then
	mv "$keep/odin.wasm" "$OUT/odin.wasm"
	rmdir "$keep"
else
	(cd "$ODIN" && OUT="$OUT/odin.wasm" ./build_odin_wasi.sh release)
fi

"$ODIN_BIN" run "$SRC/pack_root" -- "$ODIN" "$OUT/packs" "$KARL2D" "$OUT/examples"
# One gzipped pack per package: the worker fetches the ones a program imports.
# -n leaves out the timestamp, so that a pack whose sources did not change
# stays byte identical and caches are spared
find "$OUT/packs" -name '*.pack' -exec gzip -9 -n -f {} +

cp "$ODIN/core/sys/wasm/js/odin.js" "$SRC"/web/* "$OUT/"
cp "$KARL2D/audio_backend_web_audio.js" "$KARL2D/audio_backend_web_audio_processor.js" "$OUT/"
cp "$KARL2D/build_web/web_entry_templates/web_entry_template.odin" "$OUT/web_entry.odin"

# A URL written as `thing.js?version=%%` in a page or a script gets a checksum
# of what it points at, so that a request only misses the browser's cache when
# what it asks for has really changed. GitHub Pages serves everything with a
# ten minute lifetime and a reload does not reach the fetches the worker makes,
# which is how a new page came to be seen next to an old pack once.
python3 "$SRC/stamp_versions.py" "$OUT"

# What this was built from: the deploy workflow reads it off the live site to
# see whether Odin or Karl2D have moved since
printf '{"odin": "%s", "karl2d": "%s", "built": "%s"}\n' \
	"$(git -C "$ODIN" rev-parse HEAD)" "$(git -C "$KARL2D" rev-parse HEAD)" \
	"$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT/build.json"

echo "Playground built in $OUT. Serve it with e.g.: python3 -m http.server -d $OUT 8000"
