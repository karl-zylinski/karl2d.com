#!/usr/bin/env python3
"""Puts a version in the URLs of the built playground, so that the browser's
cache cannot serve half of an old build next to half of a new one.

A page or a script asks for one by writing the URL as `thing.js?version=%%`.
The marker is replaced with a checksum of that file *and* of everything it in
turn asks for, so that a change anywhere reaches every URL that leads to it: if
`compiler_worker.js` changes then the `compiler_worker.js?version=` inside
`karl2d_playground.js` changes, which changes the
`karl2d_playground.js?version=` inside `index.html`.

The packs and the example files are not written in a URL anywhere; the page
fetches them from lists, so they carry a version each in `packs/manifest.json`
and `examples/examples.json`, written by pack_root.

Usage: stamp_versions.py <built playground directory>
"""

import hashlib
import pathlib
import re
import sys

MARKER = re.compile(r"([A-Za-z0-9_./-]+)\?version=%%")

def main(out):
    # The files that can carry a marker, and so can be part of a chain
    texts = {p.name: p.read_text() for p in sorted(out.glob("*.html")) + sorted(out.glob("*.js"))}
    versions = {}

    def version_of(rel, chain):
        if rel in versions:
            return versions[rel]
        if rel in chain:
            die("%s asks for its own version, in a circle: %s" % (rel, " -> ".join(chain + (rel,))))
        path = out / rel
        if not path.is_file():
            die("%s is asked for a version by %s, but is not in %s" % (rel, chain[-1], out))
        digest = hashlib.sha256(path.read_bytes())
        for asked in sorted(set(MARKER.findall(texts.get(rel, "")))):
            digest.update(version_of(asked, chain + (rel,)).encode())
        versions[rel] = digest.hexdigest()[:12]
        return versions[rel]

    stamped = 0
    for name, text in texts.items():
        new = MARKER.sub(lambda m: m.group(1) + "?version=" + version_of(m.group(1), (name,)), text)
        if new != text:
            (out / name).write_text(new)
            stamped += len(MARKER.findall(text))
    print("%s: %d URLs given a version" % (out, stamped))

def die(message):
    sys.exit("ERROR: " + message)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        die("usage: stamp_versions.py <built playground directory>")
    main(pathlib.Path(sys.argv[1]))
