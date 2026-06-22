import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, Optional, Tuple


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
    parser = argparse.ArgumentParser(description="Unified Qwen3 ASR + TTS local UI.")
    parser.add_argument("--tts-checkpoint", default="Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice")
    parser.add_argument("--asr-url", default="http://127.0.0.1:7201")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=7200)
    parser.add_argument("--gpu-id", default="1")
    parser.add_argument("--disable-fa2", action="store_true")
    return parser.parse_args()


args = parse_args()
os.environ["CUDA_VISIBLE_DEVICES"] = args.gpu_id
add_windows_runtime_paths()

import gradio as gr
import numpy as np
import torch
from transformers.utils import is_flash_attn_2_available
from qwen_tts.inference.qwen3_tts_model import Qwen3TTSModel


ASR_TO_TTS_LANGUAGE = {
    "Arabic": "auto",
    "Cantonese": "chinese",
    "Chinese": "chinese",
    "English": "english",
    "French": "french",
    "German": "german",
    "Italian": "italian",
    "Japanese": "japanese",
    "Korean": "korean",
    "Portuguese": "portuguese",
    "Russian": "russian",
    "Spanish": "spanish",
}


def http_json(method: str, url: str, payload: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.loads(response.read().decode("utf-8"))


def wait_for_asr_worker() -> Dict[str, Any]:
    health_url = args.asr_url.rstrip("/") + "/health"
    last_error = "unknown"
    for _ in range(120):
        try:
            payload = http_json("GET", health_url)
            if payload.get("ok"):
                return payload
            last_error = payload.get("error", "worker returned not ok")
        except Exception as exc:  # pragma: no cover - startup polling path
            last_error = str(exc)
        time.sleep(1)
    raise RuntimeError(f"ASR worker did not become ready: {last_error}")


def load_tts_model() -> Qwen3TTSModel:
    model_kwargs: Dict[str, Any] = {
        "device_map": "cuda:0" if torch.cuda.is_available() else "cpu",
        "dtype": torch.bfloat16 if torch.cuda.is_available() else torch.float32,
    }
    use_fa2 = torch.cuda.is_available() and is_flash_attn_2_available() and not args.disable_fa2
    if use_fa2:
        model_kwargs["attn_implementation"] = "flash_attention_2"

    print(f"Loading Qwen3-TTS checkpoint: {args.tts_checkpoint}", flush=True)
    print(f"CUDA available: {torch.cuda.is_available()}", flush=True)
    print(f"FA2 available : {is_flash_attn_2_available()}", flush=True)
    print(f"Using FA2     : {use_fa2}", flush=True)
    print(f"CUDA_VISIBLE_DEVICES={os.environ.get('CUDA_VISIBLE_DEVICES', '')}", flush=True)

    model = Qwen3TTSModel.from_pretrained(args.tts_checkpoint, **model_kwargs)
    print("model_attn=", getattr(model.model.config, "_attn_implementation", None), flush=True)
    print(
        "layer0_attn=",
        getattr(model.model.talker.model.layers[0].self_attn.config, "_attn_implementation", None),
        flush=True,
    )
    return model


ASR_HEALTH = wait_for_asr_worker()
TTS_MODEL = load_tts_model()
TTS_LANGUAGES = [lang.lower() for lang in (TTS_MODEL.get_supported_languages() or ["auto"])]
TTS_SPEAKERS = TTS_MODEL.get_supported_speakers() or []
ASR_LANGUAGES = ["Auto"] + list(ASR_HEALTH.get("supported_languages", []))


def map_asr_language_to_tts(language: str) -> str:
    return ASR_TO_TTS_LANGUAGE.get(language, "auto")


def transcribe_audio(audio_path: Optional[str], language: str, context: str) -> Tuple[str, str, str, str]:
    if not audio_path:
        return "", "auto", "", "Please provide an audio file."

    try:
        payload = http_json(
            "POST",
            args.asr_url.rstrip("/") + "/transcribe",
            {
                "audio_path": audio_path,
                "language": None if language == "Auto" else language,
                "context": context or "",
            },
        )
        if not payload.get("ok"):
            return "", "auto", "", f"ASR failed: {payload.get('error', 'unknown error')}"

        detected_language = payload.get("language", "")
        transcript = payload.get("text", "")
        suggested_tts_language = map_asr_language_to_tts(detected_language)
        status = f"ASR complete. Detected language: {detected_language or 'unknown'}"
        return detected_language, suggested_tts_language, transcript, status
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="ignore")
        return "", "auto", "", f"ASR failed: HTTP {exc.code} {detail}"
    except Exception as exc:
        return "", "auto", "", f"ASR failed: {exc}"


def synthesize_text(text: str, language: str, speaker: str) -> Tuple[Optional[Tuple[int, np.ndarray]], str]:
    text = (text or "").strip()
    if not text:
        return None, "Please enter text to synthesize."
    if not speaker:
        return None, "Please select a speaker."

    try:
        wavs, sample_rate = TTS_MODEL.generate_custom_voice(
            text=text,
            language=(language or "auto"),
            speaker=speaker,
            do_sample=True,
            top_p=0.9,
            temperature=0.8,
        )
        wav = np.asarray(wavs[0], dtype=np.float32)
        return (sample_rate, wav), "TTS complete."
    except Exception as exc:
        return None, f"TTS failed: {exc}"


def transcribe_and_speak(
    audio_path: Optional[str],
    asr_language: str,
    context: str,
    tts_language: str,
    speaker: str,
) -> Tuple[str, str, str, Optional[Tuple[int, np.ndarray]], str]:
    detected_language, suggested_tts_language, transcript, asr_status = transcribe_audio(audio_path, asr_language, context)
    if not transcript:
        return detected_language, suggested_tts_language, transcript, None, asr_status

    effective_tts_language = tts_language or "auto"
    if effective_tts_language == "auto":
        effective_tts_language = suggested_tts_language

    audio_out, tts_status = synthesize_text(transcript, effective_tts_language, speaker)
    status = f"{asr_status} {tts_status}".strip()
    return detected_language, effective_tts_language, transcript, audio_out, status


def build_demo() -> gr.Blocks:
    with gr.Blocks(title="Qwen3 ASR + TTS Suite") as demo:
        gr.Markdown(
            "\n".join(
                [
                    "# Qwen3 ASR + TTS Suite",
                    "",
                    "- ASR worker runs in `qwen3-asr`.",
                    "- TTS runs in `qwen3-tts-fa2-test` with FA2 when available.",
                    f"- UI: `http://{args.host}:{args.port}`",
                    f"- ASR worker: `{args.asr_url}`",
                ]
            )
        )

        with gr.Tab("ASR"):
            asr_audio = gr.Audio(label="Input Audio", type="filepath", sources=["upload", "microphone"])
            asr_language = gr.Dropdown(choices=ASR_LANGUAGES, value="Auto", label="ASR Language")
            asr_context = gr.Textbox(label="Context", lines=2, placeholder="Optional recognition context")
            asr_button = gr.Button("Transcribe", variant="primary")
            asr_detected_language = gr.Textbox(label="Detected Language")
            asr_suggested_tts_language = gr.Textbox(label="Suggested TTS Language")
            asr_text = gr.Textbox(label="Transcript", lines=8)
            asr_status = gr.Textbox(label="Status")

            asr_button.click(
                fn=transcribe_audio,
                inputs=[asr_audio, asr_language, asr_context],
                outputs=[asr_detected_language, asr_suggested_tts_language, asr_text, asr_status],
            )

        with gr.Tab("TTS"):
            tts_text = gr.Textbox(label="Text", lines=8, placeholder="Enter text to synthesize")
            tts_language = gr.Dropdown(choices=TTS_LANGUAGES, value="auto", label="TTS Language")
            tts_speaker = gr.Dropdown(choices=TTS_SPEAKERS, value=TTS_SPEAKERS[0] if TTS_SPEAKERS else None, label="Speaker")
            tts_button = gr.Button("Synthesize", variant="primary")
            tts_audio = gr.Audio(label="Generated Audio")
            tts_status = gr.Textbox(label="Status")

            tts_button.click(
                fn=synthesize_text,
                inputs=[tts_text, tts_language, tts_speaker],
                outputs=[tts_audio, tts_status],
            )

        with gr.Tab("ASR -> TTS"):
            chain_audio = gr.Audio(label="Input Audio", type="filepath", sources=["upload", "microphone"])
            chain_asr_language = gr.Dropdown(choices=ASR_LANGUAGES, value="Auto", label="ASR Language")
            chain_context = gr.Textbox(label="Context", lines=2, placeholder="Optional recognition context")
            chain_button = gr.Button("Transcribe And Speak", variant="primary")
            chain_detected_language = gr.Textbox(label="Detected Language")
            chain_tts_language = gr.Dropdown(choices=TTS_LANGUAGES, value="auto", label="TTS Language")
            chain_speaker = gr.Dropdown(choices=TTS_SPEAKERS, value=TTS_SPEAKERS[0] if TTS_SPEAKERS else None, label="Speaker")
            chain_text = gr.Textbox(label="Transcript", lines=8)
            chain_audio_out = gr.Audio(label="Generated Audio")
            chain_status = gr.Textbox(label="Status")

            chain_button.click(
                fn=transcribe_and_speak,
                inputs=[chain_audio, chain_asr_language, chain_context, chain_tts_language, chain_speaker],
                outputs=[chain_detected_language, chain_tts_language, chain_text, chain_audio_out, chain_status],
            )

    return demo


def main() -> None:
    demo = build_demo()
    demo.queue(default_concurrency_limit=1)
    demo.launch(server_name=args.host, server_port=args.port, share=False)


if __name__ == "__main__":
    main()
