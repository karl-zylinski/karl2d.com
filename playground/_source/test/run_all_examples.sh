#!/usr/bin/env bash
# Runs every example the built playground lists through run_example.sh, one
# after the other, and sums up. This is the check that a new compiler module
# or a new Karl2D still compiles and runs everything the playground offers.
#
# Usage: run_all_examples.sh          (from anywhere)
#   PLAYGROUND  the built playground (default: the directory above _source)
#
# Expected: pass=24 fail=0 (as of September 2026). An example fails when the
# page reports anything but OK: a compile error, a crash, or no report at all.
set -u

here=$(cd "$(dirname "$0")" && pwd)
PLAYGROUND=${PLAYGROUND:-$here/../..}
export PLAYGROUND

examples=$(python3 -c "
import json
print(' '.join(e['dir'] for e in json.load(open('$PLAYGROUND/examples/examples.json'))))")
port=8300
pass=0; fail=0; failed=""
for example in $examples; do
	report=$("$here/run_example.sh" "$example" $port 2>&1)
	port=$((port+1))
	if echo "$report" | grep -q "^OK$"; then
		pass=$((pass+1))
		printf "ok   %-24s %s\n" "$example" "$(echo "$report" | grep -o 'Compiled in [0-9]* ms')"
	else
		fail=$((fail+1))
		failed="$failed $example"
		printf "FAIL %-24s %s\n" "$example" "$(echo "$report" | grep -v '^==' | head -3 | tr '\n' ' ')"
	fi
done
echo "== pass=$pass fail=$fail${failed:+ failed:$failed}"
[ $fail -eq 0 ]
