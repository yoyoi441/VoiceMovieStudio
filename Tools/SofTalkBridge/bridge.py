#!/usr/bin/env python3
"""Token-authenticated, loopback-only bridge from VMS to a user-installed SofTalk."""

from __future__ import annotations

import argparse
import hmac
import json
import os
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

BRIDGE_VERSION = 1
MAX_REQUEST_BYTES = 64 * 1024
MAX_TEXT_LENGTH = 10_000
SYNTHESIS_LOCK = threading.Lock()


class BridgeError(Exception):
    pass


def load_config(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BridgeError(f"設定ファイルを読み込めません: {error}") from error
    if not isinstance(value, dict):
        raise BridgeError("設定ファイルの最上位はオブジェクトにしてください。")
    return value


def profile_list(config: dict[str, Any]) -> list[dict[str, Any]]:
    result = []
    signatures: dict[tuple[str, ...], list[int]] = {}
    profiles = config.get("profiles", {})
    if not isinstance(profiles, dict):
        return result
    for profile_id, profile in profiles.items():
        if not isinstance(profile_id, str) or not isinstance(profile, dict):
            continue
        arguments = profile.get("arguments", [])
        configured = (
            profile.get("enabled") is True
            and isinstance(arguments, list)
            and bool(arguments)
            and all(isinstance(value, str) and value for value in arguments)
        )
        result.append({
            "id": profile_id,
            "displayName": str(profile.get("displayName", profile_id)),
            "isConfigured": configured,
        })
        if configured:
            signatures.setdefault(tuple(arguments), []).append(len(result) - 1)
    # Two named presets must not silently resolve to the exact same voice selection.
    for indices in signatures.values():
        if len(indices) > 1:
            for index in indices:
                result[index]["isConfigured"] = False
    return result


def percent(value: Any, minimum: float, maximum: float, fallback: float) -> int:
    try:
        number = float(value)
    except (TypeError, ValueError):
        number = fallback
    if number != number or number in (float("inf"), float("-inf")):
        number = fallback
    return round(max(minimum, min(maximum, number)) * 100)


def build_synthesis_arguments(
    config: dict[str, Any], profile_id: str, text: str, output: Path
) -> list[str]:
    profiles = config.get("profiles", {})
    profile = profiles.get(profile_id) if isinstance(profiles, dict) else None
    if not isinstance(profile, dict):
        raise BridgeError("指定された話者プリセットはありません。")
    listed = next((item for item in profile_list(config) if item["id"] == profile_id), None)
    if listed is None or not listed["isConfigured"]:
        raise BridgeError(f"{profile.get('displayName', profile_id)}の声が未設定です。")
    arguments = [str(value) for value in config.get("globalArguments", [])]
    if config.get("hideWindow", True):
        arguments.append("/X:1")
    arguments.extend(str(value) for value in profile["arguments"])
    settings = config.get("_requestSettings", {})
    mappings = config.get("parameterArguments", {})
    values = {
        "volume": percent(settings.get("volume"), 0, 2, 1),
        "speed": percent(settings.get("speed"), 0.5, 2, 1),
        "pitch": percent(settings.get("pitch"), 0.5, 2, 1),
    }
    if isinstance(mappings, dict):
        for name in ("volume", "speed", "pitch"):
            template = mappings.get(name)
            if isinstance(template, str) and "{percent}" in template:
                arguments.append(template.replace("{percent}", str(values[name])))
    # /W must be last: every following token is treated as speech text by SofTalk.
    arguments.extend([f"/R:{output}", f"/W:{text}"])
    return arguments


def executable(config: dict[str, Any]) -> Path:
    value = config.get("executable")
    if not isinstance(value, str) or not value:
        raise BridgeError("SofTalk.exeの場所を設定してください。")
    path = Path(value)
    if not path.is_file() or path.name.lower() != "softalk.exe":
        raise BridgeError("設定されたSofTalk.exeが見つかりません。")
    return path


def launch(config: dict[str, Any], arguments: list[str]) -> None:
    flags = 0
    if os.name == "nt" and config.get("hideWindow", True):
        flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    subprocess.Popen(
        [str(executable(config)), *arguments],
        cwd=str(executable(config).parent),
        creationflags=flags,
        close_fds=True,
    )


def synthesize(config: dict[str, Any], payload: dict[str, Any]) -> bytes:
    text = payload.get("text")
    profile_id = payload.get("profileID")
    settings = payload.get("settings", {})
    if not isinstance(text, str) or not text.strip() or len(text) > MAX_TEXT_LENGTH:
        raise BridgeError("セリフは1～10000文字で指定してください。")
    if not isinstance(profile_id, str):
        raise BridgeError("話者プリセットを指定してください。")
    if not isinstance(settings, dict):
        raise BridgeError("音声設定が正しくありません。")

    timeout = max(5, min(300, int(config.get("timeoutSeconds", 120))))
    with SYNTHESIS_LOCK, tempfile.TemporaryDirectory(prefix="vms-softalk-") as directory:
        output = Path(directory) / "voice.wav"
        request_config = dict(config)
        request_config["_requestSettings"] = settings
        launch(request_config, build_synthesis_arguments(request_config, profile_id, text, output))
        deadline = time.monotonic() + timeout
        previous_size = -1
        stable_count = 0
        while time.monotonic() < deadline:
            if output.is_file():
                size = output.stat().st_size
                stable_count = stable_count + 1 if size > 12 and size == previous_size else 0
                previous_size = size
                if stable_count >= 3:
                    data = output.read_bytes()
                    if data[:4] == b"RIFF" and data[8:12] == b"WAVE":
                        return data
                    raise BridgeError("出力されたファイルは有効なWAVではありません。")
            time.sleep(0.2)
    raise BridgeError("WAVの生成が時間内に完了しませんでした。SofTalkの画面と設定を確認してください。")


class Handler(BaseHTTPRequestHandler):
    server_version = "VMS-SofTalk-Bridge/1"

    def log_message(self, fmt: str, *args: Any) -> None:
        # Do not write tokens or spoken text to logs.
        print(f"{self.client_address[0]} {self.command} {self.path}")

    @property
    def config(self) -> dict[str, Any]:
        return self.server.config  # type: ignore[attr-defined]

    @property
    def token(self) -> str:
        return self.server.token  # type: ignore[attr-defined]

    def authorized(self) -> bool:
        supplied = self.headers.get("Authorization", "")
        expected = f"Bearer {self.token}"
        return hmac.compare_digest(supplied.encode(), expected.encode())

    def json_response(self, status: int, value: dict[str, Any]) -> None:
        data = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authenticate(self) -> bool:
        if self.authorized():
            return True
        self.json_response(401, {"error": "接続トークンが正しくありません。"})
        return False

    def do_GET(self) -> None:
        if not self.authenticate():
            return
        if self.path != "/v1/health":
            self.json_response(404, {"error": "未対応の操作です。"})
            return
        try:
            executable(self.config)
            self.json_response(200, {
                "status": "ok",
                "product": "SofTalk",
                "bridgeVersion": BRIDGE_VERSION,
                "profiles": profile_list(self.config),
            })
        except BridgeError as error:
            self.json_response(503, {"error": str(error)})

    def do_POST(self) -> None:
        if not self.authenticate():
            return
        if self.path == "/v1/launch":
            try:
                launch(self.config, [])
                self.json_response(200, {"status": "ok"})
            except (BridgeError, OSError) as error:
                self.json_response(503, {"error": str(error)})
            return
        if self.path != "/v1/synthesize":
            self.json_response(404, {"error": "未対応の操作です。"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > MAX_REQUEST_BYTES:
                raise BridgeError("リクエストの大きさが不正です。")
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise BridgeError("リクエスト形式が正しくありません。")
            data = synthesize(self.config, payload)
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except (BridgeError, OSError, ValueError, json.JSONDecodeError) as error:
            self.json_response(400, {"error": str(error)})


def self_test() -> None:
    config = {
        "hideWindow": True,
        "profiles": {
            "reimu": {"displayName": "ゆっくり霊夢", "enabled": True, "arguments": ["/T:TEST"]}
        },
        "parameterArguments": {"volume": "/V:{percent}", "speed": "/S:{percent}", "pitch": None},
        "_requestSettings": {"volume": 1.2, "speed": 0.8, "pitch": 1},
    }
    args = build_synthesis_arguments(config, "reimu", "テスト", Path("C:/Temp/test.wav"))
    assert args[-1] == "/W:テスト"
    assert "/V:120" in args and "/S:80" in args
    assert profile_list(config)[0]["isConfigured"] is True
    print("SofTalk bridge self-test: OK")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=Path("bridge-config.json"))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    token = os.environ.get("SOFTALK_BRIDGE_TOKEN", "")
    if len(token) < 24:
        raise SystemExit("SOFTALK_BRIDGE_TOKENに24文字以上のランダムなトークンを設定してください。")
    config = load_config(args.config)
    host = str(config.get("host", "127.0.0.1"))
    if host not in {"127.0.0.1", "localhost", "::1"}:
        raise SystemExit("ブリッジはループバックだけで待ち受けてください。外部公開にはHTTPSプロキシを使用します。")
    port = int(config.get("port", 18881))
    server = ThreadingHTTPServer((host, port), Handler)
    server.config = config  # type: ignore[attr-defined]
    server.token = token  # type: ignore[attr-defined]
    print(f"VMS SofTalk bridge listening on {host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
