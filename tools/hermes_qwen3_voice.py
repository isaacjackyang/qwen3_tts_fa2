"""
Hermes integration helper for Qwen3 ASR + TTS local services.

Import this module in execute_code scripts to call local voice services.

    from hermes_qwen3_voice import transcribe, synthesize

    # Transcribe audio file
    result = transcribe("path/to/audio.wav")
    print(result["text"])

    # Synthesize text to speech
    synthesize("Hello world", output_path="output.wav")
"""

import base64
import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, Optional


# Default service URLs
ASR_URL = os.environ.get("QWEN3_ASR_URL", "http://127.0.0.1:7201").rstrip("/")
TTS_URL = os.environ.get("QWEN3_TTS_URL", "http://127.0.0.1:7101").rstrip("/")


def http_json(method: str, url: str, payload: Optional[Dict[str, Any]] = None, timeout: int = 120) -> Dict[str, Any]:
    """Send HTTP JSON request."""
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


# --- ASR ---

def asr_health() -> Dict[str, Any]:
    """Check ASR service health."""
    return http_json("GET", f"{ASR_URL}/health")


def transcribe(
    audio_path: str,
    language: Optional[str] = None,
    context: str = "",
) -> Dict[str, Any]:
    """
    Transcribe audio file to text.

    Args:
        audio_path: Path to audio file (wav, mp3, flac, etc.)
        language: Language code (e.g. "en", "zh", "ja"). None = auto-detect.
        context: Optional context to help recognition.

    Returns:
        Dict with keys: ok, text, language, time_stamps
    """
    payload = {
        "audio_path": str(audio_path),
        "language": language,
        "context": context,
    }
    result = http_json("POST", f"{ASR_URL}/transcribe", payload)
    if not result.get("ok"):
        raise RuntimeError(f"ASR failed: {result.get('error', 'unknown')}")
    return result


# --- TTS ---

def tts_health() -> Dict[str, Any]:
    """Check TTS service health."""
    return http_json("GET", f"{TTS_URL}/health")


def tts_speakers() -> list:
    """List available speakers."""
    return http_json("GET", f"{TTS_URL}/speakers")


def tts_languages() -> list:
    """List supported languages."""
    return http_json("GET", f"{TTS_URL}/languages")


def synthesize(
    text: str,
    language: str = "auto",
    speaker: str = "",
    output_path: str = "output.wav",
    do_sample: bool = True,
    top_p: float = 0.9,
    temperature: float = 0.8,
) -> str:
    """
    Synthesize text to speech.

    Args:
        text: Text to synthesize.
        language: Language code (e.g. "auto", "chinese", "english", "japanese").
        speaker: Speaker name. Empty = first available.
        output_path: Output WAV file path.
        do_sample: Use sampling for generation.
        top_p: Nucleus sampling parameter.
        temperature: Sampling temperature.

    Returns:
        Path to the generated WAV file.
    """
    if not speaker:
        speakers = tts_speakers()
        if speakers:
            speaker = speakers[0]

    payload = {
        "text": text,
        "language": language,
        "speaker": speaker,
        "do_sample": do_sample,
        "top_p": top_p,
        "temperature": temperature,
    }
    result = http_json("POST", f"{TTS_URL}/synthesize", payload)
    if not result.get("ok"):
        raise RuntimeError(f"TTS failed: {result.get('error', 'unknown')}")

    # Decode base64 audio and write to file
    audio_data = base64.b64decode(result["audio_base64"])
    Path(output_path).write_bytes(audio_data)
    return output_path


# --- CLI mode ---

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Qwen3 ASR+TTS CLI for Hermes")
    sub = parser.add_subparsers(dest="command")

    # ASR subcommand
    asr_p = sub.add_parser("transcribe", help="Transcribe audio")
    asr_p.add_argument("audio", help="Audio file path")
    asr_p.add_argument("--language", default=None)
    asr_p.add_argument("--context", default="")

    # TTS subcommand
    tts_p = sub.add_parser("synthesize", help="Synthesize text")
    tts_p.add_argument("text", help="Text to synthesize")
    tts_p.add_argument("--language", default="auto")
    tts_p.add_argument("--speaker", default="")
    tts_p.add_argument("--output", "-o", default="output.wav")

    # Health subcommand
    sub.add_parser("health", help="Check service health")

    args = parser.parse_args()

    if args.command == "transcribe":
        result = transcribe(args.audio, args.language, args.context)
        print(result["text"])
    elif args.command == "synthesize":
        path = synthesize(args.text, args.language, args.speaker, args.output)
        print(f"Saved to: {path}")
    elif args.command == "health":
        print("ASR:", json.dumps(asr_health(), indent=2))
        print("TTS:", json.dumps(tts_health(), indent=2))
    else:
        parser.print_help()
