"""
Hermes TTS custom command provider wrapper for Qwen3-TTS HTTP API.

Usage (called by Hermes):
    python hermes_qwen3_tts.py <output_audio_path>
    (reads text from stdin)

Environment variables:
    QWEN3_TTS_URL  - TTS HTTP API URL (default: http://127.0.0.1:7101)
    QWEN3_TTS_SPEAKER - Speaker name (default: first available)
    QWEN3_TTS_LANGUAGE - Language (default: auto)
"""

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


def main() -> None:
    tts_url = os.environ.get("QWEN3_TTS_URL", "http://127.0.0.1:7101").rstrip("/")
    output_path = sys.argv[1] if len(sys.argv) > 1 else "output.wav"
    speaker = os.environ.get("QWEN3_TTS_SPEAKER", "")
    language = os.environ.get("QWEN3_TTS_LANGUAGE", "auto")

    # Read text from stdin
    text = sys.stdin.read().strip()
    if not text:
        print("ERROR: no input text", file=sys.stderr)
        sys.exit(1)

    # If no speaker specified, get the first one
    if not speaker:
        try:
            req = urllib.request.Request(f"{tts_url}/speakers")
            with urllib.request.urlopen(req, timeout=5) as resp:
                speakers = json.loads(resp.read().decode("utf-8"))
                if speakers:
                    speaker = speakers[0]
        except Exception:
            pass  # Use empty speaker and let the API handle it

    # Call synthesize endpoint
    payload = json.dumps({
        "text": text,
        "language": language,
        "speaker": speaker,
    }).encode("utf-8")

    req = urllib.request.Request(
        f"{tts_url}/synthesize",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            result = json.loads(resp.read().decode("utf-8"))

        if not result.get("ok"):
            print(f"ERROR: {result.get('error', 'unknown')}", file=sys.stderr)
            sys.exit(1)

        # Decode base64 audio and write to file
        import base64
        audio_data = base64.b64decode(result["audio_base64"])
        Path(output_path).write_bytes(audio_data)
        print(output_path)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="ignore")
        print(f"ERROR: HTTP {exc.code} {detail}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
