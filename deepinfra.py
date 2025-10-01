import os
import sys
import json
import base64
import shutil
import subprocess
import requests

# Accept either env var name (DeepInfra’s own docs/blog use *_TOKEN)
API_KEY = (
    os.getenv("DEEPINFRA_API_KEY")
    or os.getenv("DEEPINFRA_API_TOKEN")
)
if not API_KEY:
    print("Set DEEPINFRA_API_KEY or DEEPINFRA_API_TOKEN first.")
    sys.exit(1)

# Tweak as needed
TEXT    = "Oh my god dominik. I love it when you do that. Oh my god. It's so good."
VOICE   = "af_bella"   # Kokoro preset voice (see VOICES.md)
FORMAT  = "wav"        # mp3 / opus / flac / wav / pcm
OUTFILE = f"kokoro_out.{FORMAT}"

URL = "https://api.deepinfra.com/v1/inference/hexgrad/Kokoro-82M"
headers = {
    # DeepInfra examples use 'bearer' (case-insensitive per RFC)
    "Authorization": f"bearer {API_KEY}",
    "Content-Type": "application/json",
}
payload = {
    "text": TEXT,
    "voice": VOICE,
    "output_format": FORMAT,
}

def _extract_base64_audio(payload_dict: dict) -> bytes | None:
    """
    DeepInfra Kokoro returns audio as a data URL string, e.g.:
      "data:audio/wav;base64,AAA..."
    Some older/newer schemas may also put audio under ['output'][0]['audio'].
    This handles both forms and fixes missing padding.
    """
    audio_field = payload_dict.get("audio")

    # Fallback shape: { "output": [ { "audio": "..." } ] }
    if not audio_field and isinstance(payload_dict.get("output"), list):
        arr = payload_dict["output"]
        if arr and isinstance(arr[0], dict):
            audio_field = arr[0].get("audio")

    if not audio_field or not isinstance(audio_field, str):
        return None

    # Strip data URL prefix if present
    if "," in audio_field:
        audio_field = audio_field.split(",", 1)[1]

    # Fix missing padding (base64 length must be %4 == 0)
    pad = len(audio_field) % 4
    if pad:
        audio_field += "=" * (4 - pad)

    try:
        return base64.b64decode(audio_field)
    except Exception:
        return None

def main():
    try:
        resp = requests.post(URL, headers=headers, json=payload, timeout=60)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"HTTP error: {e}\nBody: {getattr(resp, 'text', '')[:500]}")
        sys.exit(1)

    try:
        data = resp.json()
    except json.JSONDecodeError:
        print("Non-JSON response:\n", resp.text[:500])
        sys.exit(1)

    audio_bytes = _extract_base64_audio(data)
    if not audio_bytes:
        print("No decodable audio in response. Full payload follows:\n",
              json.dumps(data, indent=2)[:2000])
        sys.exit(1)

    with open(OUTFILE, "wb") as f:
        f.write(audio_bytes)
    print(f"Wrote {OUTFILE}")

    # Auto-play on macOS
    if sys.platform == "darwin" and shutil.which("afplay"):
        subprocess.run(["afplay", OUTFILE], check=False)
    else:
        print(f"Open the file to listen (e.g., `open {OUTFILE}` on macOS).")

if __name__ == "__main__":
    main()
