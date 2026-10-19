"""Tiny deterministic stdio LSP fixture, not a production language server."""

import json
import sys


def send(message):
    data = json.dumps(message).encode()
    sys.stdout.buffer.write(f"Content-Length: {len(data)}\r\n\r\n".encode() + data)
    sys.stdout.buffer.flush()


uri = None
while True:
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            sys.exit(0)
        if line in (b"\r\n", b"\n"):
            break
        key, value = line.decode().split(":", 1)
        headers[key.lower()] = value.strip()
    message = json.loads(sys.stdin.buffer.read(int(headers["content-length"])))
    method = message.get("method")
    result = None
    if method == "initialize":
        result = {"capabilities": {
            "textDocumentSync": 1,
            "completionProvider": {},
            "definitionProvider": True,
            "documentFormattingProvider": True,
        }}
    elif method == "textDocument/didOpen":
        uri = message["params"]["textDocument"]["uri"]
        send({"jsonrpc": "2.0", "method": "textDocument/publishDiagnostics", "params": {
            "uri": uri, "diagnostics": [{
                "range": {"start": {"line": 0, "character": 0},
                          "end": {"line": 0, "character": 3}},
                "severity": 1, "message": "Fixture diagnostic", "source": "fixture",
            }],
        }})
    elif method == "textDocument/completion":
        result = [{"label": "answer", "kind": 6, "insertText": "answer"}]
    elif method == "textDocument/definition":
        result = [{"uri": uri, "range": {
            "start": {"line": 0, "character": 0},
            "end": {"line": 0, "character": 3},
        }}]
    elif method == "textDocument/formatting":
        result = [{"range": {"start": {"line": 0, "character": 0},
                             "end": {"line": 1, "character": 0}},
                   "newText": "answer = 42\n"}]
    elif method == "exit":
        sys.exit(0)
    if "id" in message:
        send({"jsonrpc": "2.0", "id": message["id"], "result": result})
