# Karl2D Playground

Runs the Odin compiler in the browser so that the [Karl2D](https://github.com/karl-zylinski/karl2d) examples can be edited, compiled and run on a web page: an example is picked from a dropdown, its source is shown in the editor, and Run compiles it and runs it in the pane next to it. It is what karl2d.com/playground serves.

The compiler is built as a WebAssembly (WASI) module with `build_odin_wasi.sh` from [wodin](https://github.com/karl-zylinski/wodin), the fork of Odin that has the wasm backend, and generates code with the direct wasm backend (`-backend:wasm`), so no LLVM or linker is involved. Programs are compiled for `js_wasm32` and run with the normal Odin JS runtime (`core/sys/wasm/js/odin.js`) plus Karl2D's web audio backend.

This directory is the source. The built playground goes in the directory above it, which is the one that is served; nothing of it is kept in git, `.github/workflows/deploy.yml` builds it when the site is deployed. A directory whose name begins with an underscore is never published, so the sources are not on the site.

## Building

Needs a checkout of [wodin](https://github.com/karl-zylinski/wodin) (default `../../../wodin`, or `../../../Odin`, i.e. next to this repository), a Karl2D checkout (default `../../../karl2d`), [wasi-sdk](https://github.com/WebAssembly/wasi-sdk) (default `~/wasi-sdk`, override with `WASI_SDK=...`) and an Odin compiler to run the packer with (the one in the Odin checkout, or any recent `odin` on the `PATH`):

```
./playground/_source/build_playground.sh
python3 -m http.server -d playground 8000
```

`ODIN=`, `KARL2D=` and `OUT=` say where those are if they are somewhere else. Set `ODIN_WASM=path/to/odin.wasm` to reuse an already built compiler module instead of building one (which takes a few minutes). The Karl2D checkout is fast-forwarded to `origin/master` first, so the playground cannot quietly ship stale Karl2D sources; `KARL2D_NO_UPDATE=1` leaves it alone.

`playground/` then contains:

- `odin.wasm`: the compiler (3.8 MB, 1.1 MB gzipped by the server)
- `packs/`: the sources the compiler reads, packed by `pack_root`, one gzipped pack per package plus `manifest.json`. All of `base` and `core` except what can never be used in the browser (files whose name suffix or `#+build` tags exclude `js`/`wasm32`, the machine code library `core:rexcode`, the `core:sys` packages of other operating systems), the `vendor` packages Karl2D and `vendor:box2d` need together with their wasm objects, and the Karl2D library itself under `karl2d/`. The manifest lists every package with its files and imports, so the compiler can look around the file system, and a pack is fetched when a program's imports say it is needed: a program that imports nothing from `core:crypto` never downloads it. The compiler reads them from an in-memory file system, `ODIN_ROOT` is `/odin`.
- `examples/`: the web capable Karl2D examples, one directory each, listed in `examples.json`. They are fetched when selected, so only the assets of the chosen example are downloaded.
- `web_entry.odin`: Karl2D's web entry point (`build_web/web_entry_templates/web_entry_template.odin`), compiled together with the example.
- `odin.js`, `audio_backend_web_audio.js`, `audio_backend_web_audio_processor.js`: the JS runtimes.
- `index.html`, `karl2d_playground.js`, `editor.js`, `game.html`, `compiler_worker.js`, `wasi.js`: the page. `editor.js` is the code editor (a transparent textarea over a syntax highlighted `<pre>`, no dependencies). `generic.html` + `playground.js` is a plain Odin playground (one source file, no Karl2D) on top of the same compiler worker.
- `build.json`: the Odin and Karl2D commits this was built from. The deploy workflow reads it off the live site to see whether either has moved since.

## How it works

`compiler_worker.js` runs the compiler in a web worker. `wasi.js` implements the WASI preview 1 system calls the compiler uses (files, directories, arguments, environment, clocks, exit) over an in-memory file system. Every compile is a fresh instance of the compiler module with its own memory; the file system with the packed sources is shared.

For a run, the page writes the example's files (with the editor contents as the main file) to `/odin/karl2d/examples/<name>/` and the web entry point to `/odin/karl2d/examples/<name>/build/web/entry.odin`, so that the example's import of the library and the entry's `import ex "../.."` resolve as they do in the Karl2D repository. The compiler is run as `odin build /odin/karl2d/examples/<name>/build/web -out:/out/main.wasm -backend:wasm -target:js_wasm32`. The result is posted to a fresh `game.html` iframe, which instantiates it the way Karl2D's own web template does (`odin.setupDefaultImports` plus `karl2dAudioJsImports`, `_start`, then `step` every frame until it returns false). A new iframe per run means nothing from the previous program lingers.

The examples shown here say `import k2 "karl2d"`, not the `import k2 "../.."` of the repository, where an example really does sit two directories below the library: on a page showing one example the relative path is noise. `pack_root` rewrites that line when it copies the examples (the Karl2D repository itself is left alone), and the page puts the relative form back before handing the sources to the compiler, since Odin resolves an import with no collection in it relative to the file it appears in. `karl2d/log` and the like work the same way, only the path inside the quotes is touched so reported line numbers still match the editor, and a source that says `../..` — pasted in from a checkout, say — still compiles.

Every URL the page and the worker fetch carries a `?version=`, because GitHub Pages serves everything with a ten minute lifetime and a reload does not reach the fetches a worker makes: without it a deploy can be seen half-old, a new example next to the previous library. A page or a script writes the URL as `thing.js?version=%%`, and `stamp_versions.py` replaces the marker with a checksum of that file and of everything it in turn asks for, so a change anywhere reaches every URL that leads to it. The packs and the example files are not written in a URL anywhere — the page fetches them from lists — so they carry a version each in `packs/manifest.json` and `examples/examples.json`, one per pack and one per example: a build in which only Karl2D changed leaves every other pack's URL, and so every other pack in the browser's cache, alone. `index.html` itself is the one thing that cannot be versioned this way, and it is the only thing a visitor can hold a stale copy of, for at most those ten minutes; everything it then asks for matches it.

Opening `index.html?test=1&example=<name>` compiles and runs the example automatically, then posts the status and console text to `/log` and a capture of the game canvas to `/png`, which is what the headless browser test uses.
