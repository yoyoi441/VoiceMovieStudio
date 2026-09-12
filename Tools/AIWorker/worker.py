#!/usr/bin/env python3
"""Private remote video-analysis worker. Bind this only to a trusted private network."""

import json
import os
import platform
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.request
import uuid
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST = os.environ.get("VIDEO_AI_HOST", "127.0.0.1")
PORT = int(os.environ.get("VIDEO_AI_PORT", "8765"))
DATA_DIR = Path(os.environ.get("VIDEO_AI_DATA", str(Path.home() / "Library/Application Support/VoiceMovieStudioAIWorker")))
TOKEN_FILE = Path(os.environ.get("VIDEO_AI_TOKEN_FILE", str(DATA_DIR / "token")))
MAX_UPLOAD = int(os.environ.get("VIDEO_AI_MAX_UPLOAD", str(8 * 1024 * 1024 * 1024)))
JOBS = {}
LOCK = threading.Lock()


def token():
    try:
        return TOKEN_FILE.read_text().strip()
    except OSError:
        return ""


def ollama_models():
    try:
        data = json.loads(urllib.request.urlopen("http://127.0.0.1:11434/api/tags", timeout=2).read())
        models = [item.get("name", "") for item in data.get("models", []) if item.get("name")]
        preferred = os.environ.get("VIDEO_AI_TEXT_MODEL", "")
        if preferred in models:
            models.remove(preferred)
            models.insert(0, preferred)
        return models
    except Exception:
        return []


def memory_gb():
    try:
        value = subprocess.check_output(["/usr/sbin/sysctl", "-n", "hw.memsize"], text=True).strip()
        return round(int(value) / 1024 ** 3)
    except Exception:
        return 0


def has_transcriber():
    return bool(mlx_whisper_command() or shutil.which("whisper-cli"))


def mlx_whisper_command():
    bundled = Path(sys.executable).parent / "mlx_whisper"
    return str(bundled) if bundled.exists() else shutil.which("mlx_whisper")


def public_job(job):
    return {key: value for key, value in job.items() if key not in {"input_path", "cancel"}}


def update(job_id, **values):
    with LOCK:
        if job_id in JOBS:
            if JOBS[job_id].get("state") == "cancelled" and values.get("state") != "cancelled":
                return
            JOBS[job_id].update(values)


def run_transcription(job_id, input_path, language):
    update(job_id, state="running", progress=0.08, message="音声を解析しています")
    try:
        if not has_transcriber():
            raise RuntimeError("文字起こしエンジンが未導入です。ワーカー端末で install.sh を再実行してください。")
        command = mlx_whisper_command()
        if command:
            model = os.environ.get("VIDEO_AI_WHISPER_MODEL", "mlx-community/whisper-large-v3-turbo")
            from mlx_whisper import transcribe
            arguments = {"path_or_hf_repo": model}
            if language and language != "auto":
                arguments["language"] = language
            result = transcribe(input_path, **arguments)
        else:
            output_dir = Path(tempfile.mkdtemp(prefix="transcript-", dir=DATA_DIR / "jobs"))
            model = os.environ.get("VIDEO_AI_WHISPER_MODEL_PATH", str(DATA_DIR / "models/ggml-large-v3-turbo.bin"))
            process = subprocess.run([shutil.which("whisper-cli"), "-m", model, "-f", input_path, "-l", language, "-oj", "-of", str(output_dir / "result")], capture_output=True, text=True)
            if process.returncode != 0:
                raise RuntimeError((process.stderr or process.stdout)[-1200:])
            json_files = list(output_dir.glob("*.json"))
            if not json_files:
                raise RuntimeError("文字起こし結果が生成されませんでした。")
            result = json.loads(json_files[0].read_text())
        segments = []
        for segment in result.get("segments", result.get("transcription", [])):
            timestamps = segment.get("timestamps", {})
            start = segment.get("start", timestamps.get("from", 0))
            end = segment.get("end", timestamps.get("to", start))
            if isinstance(start, str): start = 0
            if isinstance(end, str): end = start
            segments.append({"id": str(uuid.uuid4()), "start": float(start), "end": float(end), "text": segment.get("text", "").strip(), "speaker": None, "confidence": None})
        update(job_id, state="completed", progress=1, message="文字起こしが完了しました", transcript=segments)
    except Exception as exc:
        update(job_id, state="failed", progress=1, message="失敗", error=str(exc))
    finally:
        try: Path(input_path).unlink(missing_ok=True)
        except OSError: pass


def run_highlights(job_id, payload):
    update(job_id, state="running", progress=0.15, message="重要箇所を分析しています")
    try:
        models = ollama_models()
        if not models:
            raise RuntimeError("ローカル言語モデルへ接続できません。")
        model = payload.get("model") or os.environ.get("VIDEO_AI_TEXT_MODEL") or models[0]
        transcript = payload.get("transcript", [])
        transcript_text = "\n".join(f"[{s.get('start',0):.2f}-{s.get('end',0):.2f}] {s.get('text','')}" for s in transcript)
        instruction = payload.get("instruction", "重要な場面を抽出してください")
        prompt = f"""あなたは動画編集者です。次の文字起こしから重要な区間を最大10件選びます。
指示: {instruction}
各区間は文字起こしの時刻内に限定し、scoreは0から1です。短いsummaryも作成してください。
summary、title、reasonは日本語で記述してください。

{transcript_text[:120000]}"""
        schema = {"type":"object","properties":{"summary":{"type":"string"},"highlights":{"type":"array","items":{"type":"object","properties":{"start":{"type":"number"},"end":{"type":"number"},"title":{"type":"string"},"reason":{"type":"string"},"score":{"type":"number"}},"required":["start","end","title","reason","score"]}}},"required":["summary","highlights"]}
        request = urllib.request.Request("http://127.0.0.1:11434/api/chat", data=json.dumps({"model": model, "stream": False, "format": schema, "messages": [{"role":"user","content":prompt}]}).encode(), headers={"Content-Type":"application/json"})
        response = json.loads(urllib.request.urlopen(request, timeout=1800).read())
        parsed = json.loads(response["message"]["content"])
        highlights = []
        for item in parsed.get("highlights", []):
            highlights.append({"id":str(uuid.uuid4()), "start":max(0,float(item["start"])), "end":max(0,float(item["end"])), "title":item["title"], "reason":item["reason"], "score":max(0,min(1,float(item["score"]))), "isSelected":True})
        update(job_id, state="completed", progress=1, message="重要箇所の分析が完了しました", highlights=highlights, summary=parsed.get("summary", ""))
    except Exception as exc:
        update(job_id, state="failed", progress=1, message="失敗", error=str(exc))


def run_storyboard_planning(job_id, payload):
    update(job_id, state="running", progress=0.15, message="シナリオの配置を考えています")
    try:
        models = ollama_models()
        if not models:
            raise RuntimeError("ローカル言語モデルへ接続できません。")
        model = payload.get("model") or os.environ.get("VIDEO_AI_TEXT_MODEL") or models[0]
        lines = payload.get("lines", [])
        characters = [str(value).strip() for value in payload.get("characters", []) if str(value).strip()]
        if not lines or len(lines) > 300:
            raise RuntimeError("シナリオは1件以上300件以下にしてください。")
        instruction = str(payload.get("instruction") or "自然な会話になるように配置してください")[:4000]
        source = []
        for index, line in enumerate(lines):
            dialogue = str(line.get("dialogue", "")).strip()[:10000]
            if not dialogue:
                raise RuntimeError(f"{index + 1}件目のセリフが空です。")
            source.append({
                "lineIndex": index,
                "currentSpeaker": str(line.get("speakerName") or ""),
                "dialogue": dialogue,
            })
        prompt = f"""あなたは動画編集の補助者です。シナリオの各セリフについて、話者、表示時間、立ち絵の配置を提案してください。
利用できる話者名: {json.dumps(characters, ensure_ascii=False)}
追加指示: {instruction}

厳守事項:
- lineIndexとセリフの順番を変更しない。
- セリフ本文を書き換えない。
- speakerNameは利用できる話者名の完全一致、または空文字だけにする。
- durationSecondsは0.5から30秒。読み上げられる自然な長さにする。
- placementはinherit、left、right、centerのいずれか。前の配置を変える必要がなければinheritにする。
- reasonとsummaryは日本語にする。

シナリオ:
{json.dumps(source, ensure_ascii=False)}"""
        schema = {
            "type": "object",
            "properties": {
                "summary": {"type": "string"},
                "suggestions": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "lineIndex": {"type": "integer"},
                            "speakerName": {"type": "string"},
                            "durationSeconds": {"type": "number"},
                            "placement": {"type": "string", "enum": ["inherit", "left", "right", "center"]},
                            "reason": {"type": "string"},
                        },
                        "required": ["lineIndex", "speakerName", "durationSeconds", "placement", "reason"],
                    },
                },
            },
            "required": ["summary", "suggestions"],
        }
        request = urllib.request.Request(
            "http://127.0.0.1:11434/api/chat",
            data=json.dumps({
                "model": model,
                "stream": False,
                "think": False,
                "format": schema,
                "options": {"temperature": 0.2, "num_predict": min(16384, max(1024, len(source) * 96))},
                "messages": [{"role": "user", "content": prompt}],
            }).encode(),
            headers={"Content-Type": "application/json"},
        )
        response = json.loads(urllib.request.urlopen(request, timeout=1800).read())
        parsed = json.loads(response["message"]["content"])
        allowed_names = set(characters)
        suggestions = []
        seen = set()
        for item in parsed.get("suggestions", []):
            index = int(item.get("lineIndex", -1))
            if index < 0 or index >= len(source) or index in seen:
                continue
            seen.add(index)
            speaker = str(item.get("speakerName") or "").strip()
            if speaker not in allowed_names:
                speaker = None
            duration = min(30, max(0.5, float(item.get("durationSeconds", 3))))
            placement = str(item.get("placement") or "inherit")
            if placement not in {"inherit", "left", "right", "center"}:
                placement = "inherit"
            suggestions.append({
                "lineIndex": index,
                "speakerName": speaker,
                "durationSeconds": duration,
                "placement": placement,
                "reason": str(item.get("reason") or "")[:1000],
            })
        plan = {"summary": str(parsed.get("summary") or "")[:4000], "suggestions": suggestions}
        update(job_id, state="completed", progress=1, message="おすすめ配置を作成しました", storyboardPlan=plan)
    except Exception as exc:
        update(job_id, state="failed", progress=1, message="失敗", error=str(exc))


class Handler(BaseHTTPRequestHandler):
    server_version = "VideoAIWorker/0.1"

    def log_message(self, fmt, *args):
        print(time.strftime("%Y-%m-%d %H:%M:%S"), self.address_string(), fmt % args, flush=True)

    def authorized(self):
        expected = token()
        return bool(expected) and self.headers.get("Authorization", "") == "Bearer " + expected

    def json_response(self, status, value):
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not self.authorized(): return self.json_response(401, {"error":"unauthorized"})
        if self.path == "/v1/health":
            capabilities = ["highlights", "clipPlanning"]
            if has_transcriber(): capabilities.insert(0, "transcription")
            models = ollama_models()
            return self.json_response(200, {"name":platform.node(), "version":"0.1", "capabilities":capabilities, "models":models, "processor":platform.processor() or platform.machine(), "memoryGB":memory_gb()})
        if self.path.startswith("/v1/jobs/"):
            job_id = self.path.rsplit("/", 1)[-1]
            with LOCK: job = JOBS.get(job_id)
            return self.json_response(200, public_job(job)) if job else self.json_response(404, {"error":"not found"})
        return self.json_response(404, {"error":"not found"})

    def do_POST(self):
        if not self.authorized(): return self.json_response(401, {"error":"unauthorized"})
        if self.path != "/v1/jobs": return self.json_response(404, {"error":"not found"})
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_UPLOAD: return self.json_response(413, {"error":"invalid size"})
        job_type = self.headers.get("X-Job-Type", "")
        job_id = str(uuid.uuid4())
        job = {"id":job_id, "state":"queued", "progress":0, "message":"待機中", "transcript":None, "highlights":None, "summary":None, "storyboardPlan":None, "error":None}
        with LOCK: JOBS[job_id] = job
        if job_type == "transcription":
            suffix = Path(self.headers.get("X-Filename", "input.m4a")).suffix or ".m4a"
            path = DATA_DIR / "jobs" / (job_id + suffix)
            with path.open("wb") as output:
                remaining = length
                while remaining:
                    chunk = self.rfile.read(min(1024 * 1024, remaining))
                    if not chunk: break
                    output.write(chunk); remaining -= len(chunk)
            threading.Thread(target=run_transcription, args=(job_id, str(path), self.headers.get("X-Language", "ja")), daemon=True).start()
        elif job_type == "highlights":
            payload = json.loads(self.rfile.read(length))
            threading.Thread(target=run_highlights, args=(job_id, payload), daemon=True).start()
        elif job_type == "storyboardPlanning":
            payload = json.loads(self.rfile.read(length))
            threading.Thread(target=run_storyboard_planning, args=(job_id, payload), daemon=True).start()
        else:
            update(job_id, state="failed", progress=1, error="unknown job type")
        return self.json_response(202, job)

    def do_DELETE(self):
        if not self.authorized(): return self.json_response(401, {"error":"unauthorized"})
        if not self.path.startswith("/v1/jobs/"): return self.json_response(404, {"error":"not found"})
        job_id = self.path.rsplit("/", 1)[-1]
        with LOCK:
            if job_id not in JOBS: return self.json_response(404, {"error":"not found"})
            JOBS[job_id].update(state="cancelled", progress=1, message="キャンセルしました")
        return self.json_response(200, public_job(JOBS[job_id]))


if __name__ == "__main__":
    (DATA_DIR / "jobs").mkdir(parents=True, exist_ok=True)
    print(f"Video AI Worker listening on {HOST}:{PORT}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
