"""
Lightweight HTTP API server for Qwen3-TTS.
Runs alongside the Gradio UI on a separate port (default 7101).
Provides a clean JSON API for programmatic TTS synthesis.

Usage:
    # In qwen3-tts-fa2-test conda env:
    python qwen3_tts_http_api.py
    python qwen3_tts_http_api.py --port 7101 --gpu-id 1
    python qwen3_tts_http_api.py --disable-fa2
"""

import argparse
import io
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

def add_windows_runtime_paths() -> None:
    env_root = Path(sys.executable).resolve().parent.parent
    torch_lib_dir = env_root / "Lib" / "site-packages" / "torch" / "lib"
    cuda_bin_dir = Path(r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin")
    sox_dir = Path(
        r"C:\Users\JackYang\AppData\Local\Microsoft\WinGet\Packages\ChrisBagwell.SoX_Microsoft.Winget.Source_8wekyb3d8bbwe\sox-14.4.2"
    )

    for path in (torch_lib_dir, cuda_bin_dir, sox_dir):
        if not path.exists():
            continue
        os.environ["PATH"] = str(path) + os.pathsep + os.environ.get("PATH", "")
        if hasattr(os, "add_dll_directory") and path != sox_dir:
            try:
                os.add_dll_directory(str(path))
            except OSError:
                pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="HTTP API server for Qwen3-TTS.")
    parser.add_argument("--checkpoint", default="Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=7101)
    parser.add_argument("--gpu-id", default="1")
    parser.add_argument("--disable-fa2", action="store_true")
    return parser.parse_args()


args = parse_args()
os.environ["CUDA_VISIBLE_DEVICES"] = args.gpu_id
add_windows_runtime_paths()

import numpy as np
import torch
import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from transformers.utils import is_flash_attn_2_available
from qwen_tts.inference.qwen3_tts_model import Qwen3TTSModel


# --- Pydantic models ---

class SynthesisRequest(BaseModel):
    text: str
    language: str = "auto"
    speaker: str = ""
    do_sample: bool = True
    top_p: float = 0.9
    temperature: float = 0.8


class SpeakerInfo(BaseModel):
    name: str
    languages: List[str]


class HealthResponse(BaseModel):
    ok: bool
    checkpoint: str
    gpu_id: str
    cuda_available: bool
    fa2_available: bool
    using_fa2: bool
    speakers: List[str]
    languages: List[str]


# --- Model loading ---

def load_model() -> Qwen3TTSModel:
    model_kwargs: Dict[str, Any] = {
        "device_map": "cuda:0" if torch.cuda.is_available() else "cpu",
        "dtype": torch.bfloat16 if torch.cuda.is_available() else torch.float32,
    }
    use_fa2 = torch.cuda.is_available() and is_flash_attn_2_available() and not args.disable_fa2
    if use_fa2:
        model_kwargs["attn_implementation"] = "flash_attention_2"

    print(f"[TTS-API] Loading checkpoint: {args.checkpoint}", flush=True)
    print(f"[TTS-API] CUDA: {torch.cuda.is_available()}, FA2 available: {is_flash_attn_2_available()}, Using FA2: {use_fa2}", flush=True)

    model = Qwen3TTSModel.from_pretrained(args.checkpoint, **model_kwargs)

    attn = getattr(model.model.config, "_attn_implementation", None)
    print(f"[TTS-API] model_attn= {attn}", flush=True)
    return model


MODEL = load_model()
SPEAKERS = MODEL.get_supported_speakers() or []
LANGUAGES = [lang.lower() for lang in (MODEL.get_supported_languages() or ["auto"])]

# --- FastAPI app ---

app = FastAPI(title="Qwen3-TTS HTTP API", version="1.0.0")


@app.get("/health")
async def health() -> HealthResponse:
    attn = getattr(MODEL.model.config, "_attn_implementation", None)
    return HealthResponse(
        ok=True,
        checkpoint=args.checkpoint,
        gpu_id=args.gpu_id,
        cuda_available=torch.cuda.is_available(),
        fa2_available=is_flash_attn_2_available(),
        using_fa2=attn == "flash_attention_2",
        speakers=SPEAKERS,
        languages=LANGUAGES,
    )


@app.post("/synthesize")
async def synthesize(req: SynthesisRequest) -> Dict[str, Any]:
    if not req.text.strip():
        raise HTTPException(status_code=400, detail="text is required")
    if not req.speaker and SPEAKERS:
        raise HTTPException(status_code=400, detail=f"speaker is required. Available: {SPEAKERS}")

    try:
        wavs, sample_rate = MODEL.generate_custom_voice(
            text=req.text.strip(),
            language=req.language or "auto",
            speaker=req.speaker,
            do_sample=req.do_sample,
            top_p=req.top_p,
            temperature=req.temperature,
        )
        wav = np.asarray(wavs[0], dtype=np.float32)

        # Encode as WAV in memory
        buf = io.BytesIO()
        from scipy.io import wavfile
        wavfile.write(buf, sample_rate, (wav * 32767).astype(np.int16))
        buf.seek(0)
        wav_bytes = buf.read()

        import base64
        return {
            "ok": True,
            "sample_rate": sample_rate,
            "duration_sec": len(wav) / sample_rate,
            "audio_base64": base64.b64encode(wav_bytes).decode("ascii"),
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.get("/speakers")
async def list_speakers() -> List[str]:
    return SPEAKERS


@app.get("/languages")
async def list_languages() -> List[str]:
    return LANGUAGES


def main() -> None:
    print(f"[TTS-API] Starting on http://{args.host}:{args.port}", flush=True)
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
