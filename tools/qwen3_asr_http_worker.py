import argparse
import json
import os
import sys
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, Optional


def add_windows_runtime_paths() -> None:
    env_root = Path(sys.executable).resolve().parent.parent
    torch_lib_dir = env_root / "Lib" / "site-packages" / "torch" / "lib"
    cuda_bin_dir = Path(r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin")

    for path in (torch_lib_dir, cuda_bin_dir):
        if not path.exists():
            continue
        os.environ["PATH"] = str(path) + os.pathsep + os.environ.get("PATH", "")
        if hasattr(os, "add_dll_directory"):
            try:
                os.add_dll_directory(str(path))
            except OSError:
                pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Local HTTP worker for Qwen3-ASR.")
    parser.add_argument("--checkpoint", default="Qwen/Qwen3-ASR-1.7B")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=7201)
    parser.add_argument("--gpu-id", default="1")
    parser.add_argument("--max-new-tokens", type=int, default=512)
    parser.add_argument("--disable-fa2", action="store_true")
    return parser.parse_args()


args = parse_args()
os.environ["CUDA_VISIBLE_DEVICES"] = args.gpu_id
add_windows_runtime_paths()

import torch
from transformers.utils import is_flash_attn_2_available
from qwen_asr import Qwen3ASRModel
from qwen_asr.inference.qwen3_asr import SUPPORTED_LANGUAGES


def build_model() -> Qwen3ASRModel:
    device_map = "cuda:0" if torch.cuda.is_available() else "cpu"
    model_kwargs: Dict[str, Any] = {
        "device_map": device_map,
        "dtype": torch.bfloat16 if torch.cuda.is_available() else torch.float32,
        "max_new_tokens": args.max_new_tokens,
    }
    use_fa2 = torch.cuda.is_available() and is_flash_attn_2_available() and not args.disable_fa2
    if use_fa2:
        model_kwargs["attn_implementation"] = "flash_attention_2"

    print(f"Loading Qwen3-ASR checkpoint: {args.checkpoint}", flush=True)
    print(f"CUDA available: {torch.cuda.is_available()}", flush=True)
    print(f"FA2 available : {is_flash_attn_2_available()}", flush=True)
    print(f"Using FA2     : {use_fa2}", flush=True)
    print(f"CUDA_VISIBLE_DEVICES={os.environ.get('CUDA_VISIBLE_DEVICES', '')}", flush=True)

    return Qwen3ASRModel.from_pretrained(args.checkpoint, **model_kwargs)


MODEL = build_model()


class AsrHandler(BaseHTTPRequestHandler):
    server_version = "Qwen3ASRHTTP/1.0"

    def _send_json(self, status: int, payload: Dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> Dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length > 0 else b"{}"
        if not raw:
            return {}
        return json.loads(raw.decode("utf-8"))

    def log_message(self, fmt: str, *args_in: Any) -> None:
        print(f"[{self.log_date_time_string()}] {fmt % args_in}", flush=True)

    def do_GET(self) -> None:
        if self.path != "/health":
            self._send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not found"})
            return

        self._send_json(
            HTTPStatus.OK,
            {
                "ok": True,
                "checkpoint": args.checkpoint,
                "gpu_id": args.gpu_id,
                "cuda_available": torch.cuda.is_available(),
                "fa2_available": is_flash_attn_2_available(),
                "supported_languages": SUPPORTED_LANGUAGES,
            },
        )

    def do_POST(self) -> None:
        if self.path != "/transcribe":
            self._send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not found"})
            return

        try:
            payload = self._read_json()
            audio_path = str(payload.get("audio_path", "")).strip()
            context = str(payload.get("context", "") or "")
            language = payload.get("language", None)
            language = None if language in (None, "", "Auto") else str(language)

            if not audio_path:
                raise ValueError("audio_path is required")

            audio_file = Path(audio_path)
            if not audio_file.exists():
                raise FileNotFoundError(f"audio file not found: {audio_file}")

            result = MODEL.transcribe(
                audio=str(audio_file),
                context=context,
                language=language,
                return_time_stamps=False,
            )[0]

            self._send_json(
                HTTPStatus.OK,
                {
                    "ok": True,
                    "language": result.language,
                    "text": result.text,
                    "time_stamps": result.time_stamps,
                },
            )
        except Exception as exc:
            self._send_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {
                    "ok": False,
                    "error": str(exc),
                },
            )


def main() -> None:
    server = ThreadingHTTPServer((args.host, args.port), AsrHandler)
    print(f"Qwen3-ASR worker listening on http://{args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
