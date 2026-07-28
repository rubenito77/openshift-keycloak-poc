import html
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


APP_VARIANT = os.getenv("APP_VARIANT", "unknown")
BIND_ADDRESS = os.getenv("BIND_ADDRESS", "0.0.0.0")
PORT = int(os.getenv("PORT", "8080"))


class Handler(BaseHTTPRequestHandler):
    def _identity(self):
        return {
            "variant": APP_VARIANT,
            "authenticated": bool(self.headers.get("X-Forwarded-User")),
            "user": self.headers.get("X-Forwarded-User", "anonymous"),
            "email": self.headers.get("X-Forwarded-Email", ""),
            "preferred_username": self.headers.get(
                "X-Forwarded-Preferred-Username", ""
            ),
            "access_token_forwarded": bool(
                self.headers.get("X-Forwarded-Access-Token")
            ),
        }

    def _write(self, status, content_type, body):
        payload = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/healthz":
            self._write(200, "application/json", '{"status":"ok"}')
            return

        identity = self._identity()
        if self.path == "/api/whoami":
            self._write(
                200,
                "application/json",
                json.dumps(identity, ensure_ascii=False, indent=2),
            )
            return

        title = (
            "Aplicación protegida por Keycloak"
            if APP_VARIANT == "protected"
            else "Aplicación pública sin Keycloak"
        )
        rows = "".join(
            "<tr><th>{}</th><td>{}</td></tr>".format(
                html.escape(str(key)), html.escape(str(value))
            )
            for key, value in identity.items()
        )
        body = f"""<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <style>
    body {{ font-family: system-ui, sans-serif; margin: 3rem; background: #f5f7fa; }}
    main {{ max-width: 760px; margin: auto; background: white; padding: 2rem;
            border-radius: 12px; box-shadow: 0 8px 30px #0001; }}
    h1 {{ color: #17365d; }}
    table {{ border-collapse: collapse; width: 100%; }}
    th, td {{ text-align: left; padding: .7rem; border-bottom: 1px solid #ddd; }}
    th {{ width: 38%; }}
    code {{ background: #eef2f7; padding: .2rem .4rem; }}
  </style>
</head>
<body><main>
  <h1>{html.escape(title)}</h1>
  <p>Mismo backend, variante <code>{html.escape(APP_VARIANT)}</code>.</p>
  <table>{rows}</table>
  <p><a href="/api/whoami">Ver identidad como JSON</a></p>
</main></body></html>"""
        self._write(200, "text/html; charset=utf-8", body)

    def log_message(self, fmt, *args):
        print(
            json.dumps(
                {
                    "client": self.client_address[0],
                    "request": fmt % args,
                    "variant": APP_VARIANT,
                }
            ),
            flush=True,
        )


if __name__ == "__main__":
    print(
        f"Starting POC backend variant={APP_VARIANT} "
        f"address={BIND_ADDRESS}:{PORT}",
        flush=True,
    )
    ThreadingHTTPServer((BIND_ADDRESS, PORT), Handler).serve_forever()

