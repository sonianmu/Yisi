from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json


class TranslationBridge(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_POST(self):
        if self.path != "/translate":
            self.send_error(404)
            return
        if self.headers.get("Origin") or self.headers.get("Host") != "127.0.0.1:19387":
            self.send_error(403)
            return
        if self.headers.get_content_type() != "application/json":
            self.send_error(415)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 1_048_576:
                self.send_error(413)
                return
            self.connection.settimeout(5)
            request = json.loads(self.rfile.read(length))
            if not isinstance(request, dict):
                raise ValueError()
            text = request.get("text")
            source = request.get("source")
            target = request.get("target")
            languages = {"auto", "en", "zh-Hans", "zh-Hant", "ja", "ko", "fr", "de", "es", "ru", "ar", "th", "vi"}
            if not isinstance(text, str) or not text or source not in languages or target not in languages - {"auto"}:
                raise ValueError()
        except (ValueError, TypeError, TimeoutError):
            self.send_error(400)
            return
        if text != "Hello" or source != "en" or target != "zh-Hans":
            self.send_error(422, "Demo only supports Hello from en to zh-Hans")
            return
        data = json.dumps({"translation": "你好"}, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    print("Demo bridge: http://127.0.0.1:19387/translate (Hello → 你好 only)")
    ThreadingHTTPServer(("127.0.0.1", 19387), TranslationBridge).serve_forever()
