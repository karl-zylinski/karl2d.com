#!/usr/bin/env python3
"""Serves a built playground for the headless test, the way GitHub Pages does.

Usage: serve.py <port> <directory>

Environment:
  LOGFILE  where the page's report goes: a POST to /log is written there, a
           POST to /png (the canvas as a data URL) to LOGFILE.png, and every
           404 is appended to LOGFILE.404
  STRICT   when set, files whose name starts with a dot are refused with a
           404, as nginx and GitHub Pages refuse them; an example that lists
           a .gitignore among its files fails here instead of on the site
"""

import base64
import http.server
import os
import sys

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=sys.argv[2], **kwargs)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode()
        log = os.environ.get("LOGFILE")
        if log:
            if self.path == "/png":
                if body.startswith("data:image/png;base64,"):
                    with open(log + ".png", "wb") as f:
                        f.write(base64.b64decode(body.split(",", 1)[1]))
            else:
                with open(log, "w") as f:
                    f.write(body)
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        if os.environ.get("STRICT") and any(part.startswith(".") for part in self.path.split("?")[0].split("/")):
            self.send_error(404, "dotfiles are not served")
            return
        super().do_GET()

    def send_error(self, code, message=None, explain=None):
        log = os.environ.get("LOGFILE")
        if code == 404 and log:
            with open(log + ".404", "a") as f:
                f.write(self.path + "\n")
        super().send_error(code, message, explain)

    def log_message(self, *args):
        pass

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: serve.py <port> <directory>")
    http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
