"""
Hermes STT local_command provider for Qwen3-ASR HTTP API.

Hermes calls this with template placeholders:
    python hermes_qwen3_asr_provider.py --input {input_path} --output_dir {output_dir} --language {language} --model {model}

The script calls the local ASR HTTP API (port 7201), transcribes the audio,
and writes the result to {output_dir}/transcript.txt.

Environment variables:
    QWEN3_ASR_URL - ASR API URL (default: http://127.0.0.1:7201)
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="Hermes STT provider for Qwen3-ASR")
    parser.add_argument("--input", required=True, help="Input audio file path")
    parser.add_argument("--output_dir", required=True, help="Output directory for transcript")
    parser.add_argument("--language", default=None, help="Language code (e.g. en, zh, ja)")
    parser.add_argument("--model", default="", help="Model name (ignored, for Hermes compat)")
    return parser.parse_args()


# ISO 639-1/639-3 code -> Qwen3-ASR language name mapping
_LANG_MAP = {
    "zh": "Chinese", "zh-tw": "Chinese", "zh-hant": "Chinese", "zh-hans": "Chinese",
    "en": "English",
    "yue": "Cantonese", "yue-hant": "Cantonese",
    "ar": "Arabic",
    "de": "German",
    "fr": "French",
    "es": "Spanish",
    "pt": "Portuguese",
    "id": "Indonesian",
    "it": "Italian",
    "ko": "Korean",
    "ru": "Russian",
    "th": "Thai",
    "vi": "Vietnamese",
    "ja": "Japanese",
    "tr": "Turkish",
    "hi": "Hindi",
    "ms": "Malay",
    "nl": "Dutch",
    "sv": "Swedish",
    "da": "Danish",
    "fi": "Finnish",
    "pl": "Polish",
    "cs": "Czech",
    "fil": "Filipino", "tl": "Filipino",
    "fa": "Persian",
    "el": "Greek",
    "ro": "Romanian",
    "hu": "Hungarian",
    "mk": "Macedonian",
}

def _resolve_language(language: str | None) -> str | None:
    """Convert ISO language code to Qwen3-ASR language name."""
    if not language or language == "auto":
        return None
    supported = ["Chinese", "English", "Cantonese", "Arabic", "German", "French",
                 "Spanish", "Portuguese", "Indonesian", "Italian", "Korean", "Russian",
                 "Thai", "Vietnamese", "Japanese", "Turkish", "Hindi", "Malay",
                 "Dutch", "Swedish", "Danish", "Finnish", "Polish", "Czech",
                 "Filipino", "Persian", "Greek", "Romanian", "Hungarian", "Macedonian"]
    if language in supported:
        return language
    return _LANG_MAP.get(language.lower())


def transcribe(audio_path: str, language: str | None, asr_url: str) -> str:
    """Call Qwen3-ASR HTTP API and return transcribed text."""
    resolved_lang = _resolve_language(language)
    payload = {
        "audio_path": audio_path,
        "language": resolved_lang,
    }
    # Remove None values
    payload = {k: v for k, v in payload.items() if v is not None}

    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{asr_url}/transcribe",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            result = json.loads(response.read().decode("utf-8"))

        if not result.get("ok"):
            raise RuntimeError(f"ASR failed: {result.get('error', 'unknown')}")

        return result["text"]
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"ASR HTTP error {exc.code}: {detail}")


def main():
    args = parse_args()
    asr_url = os.environ.get("QWEN3_ASR_URL", "http://127.0.0.1:7201").rstrip("/")

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"ERROR: input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        text = transcribe(str(input_path), args.language, asr_url)
        transcript_path = output_dir / "transcript.txt"
        transcript_path.write_text(text, encoding="utf-8")
        print(f"Transcribed {input_path.name} -> {transcript_path}", file=sys.stderr)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
