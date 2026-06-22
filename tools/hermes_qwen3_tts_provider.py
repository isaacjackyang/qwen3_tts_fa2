"""
Hermes TTS command provider for Qwen3-TTS Gradio API.
"""

import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

SPEAKER_MAP = {
    "serena": "Serena", "vivian": "Vivian", "uncle_fu": "Uncle Fu",
    "ryan": "Ryan", "aiden": "Aiden", "ono_anna": "Ono Anna",
    "sohee": "Sohee", "eric": "Eric", "dylan": "Dylan",
}

LANG_MAP = {
    "auto": "Auto", "zh": "Chinese", "chinese": "Chinese",
    "en": "English", "english": "English", "de": "German",
    "german": "German", "it": "Italian", "italian": "Italian",
    "pt": "Portuguese", "portuguese": "Portuguese", "es": "Spanish",
    "spanish": "Spanish", "ja": "Japanese", "japanese": "Japanese",
    "ko": "Korean", "korean": "Korean", "fr": "French",
    "french": "French", "ru": "Russian", "russian": "Russian",
}


def parse_args():
    parser = argparse.ArgumentParser(description="Hermes TTS provider for Qwen3-TTS")
    parser.add_argument("--input", required=True, help="Input text file path")
    parser.add_argument("--output", required=True, help="Output audio file path")
    parser.add_argument("--format", default="wav", help="Output format")
    parser.add_argument("--voice", default="", help="Voice/speaker name")
    parser.add_argument("--model", default="", help="Model name (ignored)")
    parser.add_argument("--speed", default="", help="Speed (ignored)")
    return parser.parse_args()


def resolve_speaker(voice):
    if not voice:
        return "Vivian"
    if voice in SPEAKER_MAP.values():
        return voice
    return SPEAKER_MAP.get(voice.lower(), voice)


def resolve_language(lang):
    if not lang or lang == "auto":
        return "Auto"
    return LANG_MAP.get(lang.lower(), "Auto")


def synthesize(text, speaker, language, tts_url):
    """Call Gradio API and return audio bytes."""
    # Submit
    payload = json.dumps({"data": [text, language, speaker, ""]}).encode("utf-8")
    req = urllib.request.Request(
        f"{tts_url}/gradio_api/call/run_instruct",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        result = json.loads(resp.read().decode("utf-8"))

    event_id = result.get("event_id")
    if not event_id:
        raise RuntimeError(f"No event_id: {result}")

    # Poll for result
    poll_url = f"{tts_url}/gradio_api/call/run_instruct/{event_id}"
    for attempt in range(60):
        time.sleep(1)
        try:
            with urllib.request.urlopen(poll_url, timeout=30) as resp:
                content = resp.read().decode("utf-8")
                # Parse SSE: look for "event: complete" followed by "data: [...]"
                lines = content.strip().split("\n")
                for i, line in enumerate(lines):
                    if line.startswith("event: complete"):
                        # Next line should be data
                        if i + 1 < len(lines) and lines[i + 1].startswith("data: "):
                            data_str = lines[i + 1][6:]
                            data = json.loads(data_str)
                            # data is a list: [{audio_info}, "status message"]
                            if isinstance(data, list) and len(data) > 0:
                                audio_info = data[0]
                                if isinstance(audio_info, dict):
                                    audio_url = audio_info.get("url", "")
                                    if audio_url:
                                        with urllib.request.urlopen(audio_url, timeout=30) as ar:
                                            return ar.read()
                            raise RuntimeError(f"No audio in response: {data}")
        except urllib.error.URLError:
            continue

    raise RuntimeError("Timed out waiting for TTS result")


def main():
    args = parse_args()
    tts_url = os.environ.get("QWEN3_TTS_URL", "http://127.0.0.1:7100").rstrip("/")
    speaker = resolve_speaker(os.environ.get("QWEN3_TTS_SPEAKER", args.voice))
    language = resolve_language(os.environ.get("QWEN3_TTS_LANG", "auto"))

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
        audio_bytes = synthesize(text, speaker, language, tts_url)
        output_path.write_bytes(audio_bytes)
        print(f"Synthesized {len(text)} chars -> {output_path} ({len(audio_bytes)} bytes)", file=sys.stderr)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
