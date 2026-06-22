"""
Hermes TTS command provider for Qwen3-TTS FastAPI (port 7101).
Calls /synthesize endpoint, decodes base64 audio, writes WAV file.
"""

import argparse
import base64
import json
import os
import sys
import urllib.request
import urllib.error
from pathlib import Path

SPEAKER_MAP = {
    "serena": "serena", "vivian": "vivian", "uncle_fu": "uncle_fu",
    "ryan": "ryan", "aiden": "aiden", "ono_anna": "ono_anna",
    "sohee": "sohee", "eric": "eric", "dylan": "dylan",
}


def parse_args():
    parser = argparse.ArgumentParser(description="Hermes TTS provider for Qwen3-TTS FastAPI")
    parser.add_argument("--input", required=True, help="Input text file path")
    parser.add_argument("--output", required=True, help="Output audio file path")
    parser.add_argument("--format", default="wav", help="Output format")
    parser.add_argument("--voice", default="serena", help="Voice/speaker name")
    parser.add_argument("--model", default="", help="Model name (ignored)")
    parser.add_argument("--speed", default="", help="Speed (ignored)")
    return parser.parse_args()


def resolve_speaker(voice):
    if not voice:
        return "serena"
    return SPEAKER_MAP.get(voice.lower(), voice.lower())


def synthesize(text, speaker, tts_url):
    """Call /synthesize endpoint and return WAV bytes."""
    payload = json.dumps({
        "text": text,
        "speaker": speaker,
        "language": "auto",
    }).encode("utf-8")

    req = urllib.request.Request(
        f"{tts_url}/synthesize",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=180) as resp:
        result = json.loads(resp.read().decode("utf-8"))

    if not result.get("ok"):
        raise RuntimeError(f"Synthesis failed: {result}")

    audio_base64 = result.get("audio_base64")
    if not audio_base64:
        raise RuntimeError("No audio in response")

    return base64.b64decode(audio_base64)


def main():
    args = parse_args()
    tts_url = os.environ.get("QWEN3_TTS_URL", "http://127.0.0.1:7101").rstrip("/")
    speaker = resolve_speaker(os.environ.get("QWEN3_TTS_SPEAKER", args.voice))

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"ERROR: input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    text = input_path.read_text(encoding="utf-8").strip()
    if not text:
        print("ERROR: input text is empty", file=sys.stderr)
        sys.exit(1)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        audio_bytes = synthesize(text, speaker, tts_url)
        output_path.write_bytes(audio_bytes)
        print(f"Synthesized {len(text)} chars -> {output_path} ({len(audio_bytes)} bytes)", file=sys.stderr)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
