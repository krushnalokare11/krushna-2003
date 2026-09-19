from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from functools import partial
import os

PORT = 8000
ROOT = os.path.dirname(os.path.abspath(__file__))

CUSTOM_PATHS = {
    "/krushna-2003",
    "/krushna-2003/",
    "/krushna-lokare-2003",
    "/krushna-lokare-2003/",
}

class CustomHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        requested = self.path.split("?", 1)[0]
        if requested in CUSTOM_PATHS:
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            with open(os.path.join(ROOT, "index.html"), "rb") as f:
                self.copyfile(f, self.wfile)
            return
        return super().do_GET()

    def log_message(self, format, *args):
        pass

if __name__ == "__main__":
    handler = partial(CustomHandler, directory=ROOT)
    server = ThreadingHTTPServer(("0.0.0.0", PORT), handler)
    print(f"Serving portfolio at http://localhost:{PORT}/")
    print(f"Custom URLs: http://localhost:{PORT}/krushna-2003")
    print(f"Custom URLs: http://localhost:{PORT}/krushna-lokare-2003")
    server.serve_forever()
