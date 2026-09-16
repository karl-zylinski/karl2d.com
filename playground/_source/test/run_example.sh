#!/usr/bin/env bash
# Opens the built playground in a headless Firefox, has it compile and run one
# example, and reports what the page reported: the status line, the console,
# and a capture of the game canvas.
#
# The page does the work: `index.html?test=1&example=<name>` compiles and runs
# the example as soon as the compiler is ready, then posts the status and the
# console to /log and the canvas to /png (see testHook in karl2d_playground.js).
# serve.py, alongside, receives them.
#
# Usage: run_example.sh <example> [port] [extra query, e.g. '&src=...']
#   PLAYGROUND  the built playground to serve (default: the directory above
#               _source, which is where build_playground.sh puts it)
#   OUT         where the report and the capture go (default: /tmp/k2dpg)
#
# Prints the report; the capture is $OUT/<example>.png. Needs firefox and
# python3; the pixel count needs Pillow and is skipped without it.
set -u

example=$1
port=${2:-8300}
extra=${3:-}
here=$(cd "$(dirname "$0")" && pwd)
PLAYGROUND=${PLAYGROUND:-$here/../..}
OUT=${OUT:-/tmp/k2dpg}
mkdir -p "$OUT"
name=$(echo "$example" | tr / _)
log="$OUT/$name.log"
rm -f "$log" "$log.png" "$log.404"

LOGFILE="$log" STRICT=1 python3 "$here/serve.py" "$port" "$PLAYGROUND" &
server=$!
sleep 0.3
profile=$(mktemp -d)
timeout 60 firefox --headless --no-remote --profile "$profile" --window-size=1280,720 \
	"http://127.0.0.1:$port/index.html?test=1&example=$example$extra" >/dev/null 2>&1 &
browser=$!
for _ in $(seq 1 110); do
	[ -f "$log.png" ] && break
	sleep 0.5
done
sleep 1
kill $browser $server 2>/dev/null
wait $browser $server 2>/dev/null
rm -rf "$profile"

echo "== $example"
if [ -f "$log" ]; then cat "$log"; else echo "NO REPORT (the page never posted to /log)"; fi
if [ -f "$log.404" ]; then echo "404s: $(sort -u "$log.404" | tr '\n' ' ')"; fi
if [ -f "$log.png" ]; then
	mv "$log.png" "$OUT/$name.png"
	echo "png: $OUT/$name.png $(python3 -c "
from PIL import Image
im = Image.open('$OUT/$name.png')
print(im.size, len(set(im.convert('RGB').getdata())), 'distinct colours')" 2>/dev/null)"
fi
