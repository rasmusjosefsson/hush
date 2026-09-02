# /// script
# requires-python = "==3.11.*"
# dependencies = [
#   "chatterbox-tts @ git+https://github.com/resemble-ai/chatterbox.git@5de7a54aa4e5e2baadb0182dde554908b48b85c2",
# ]
# ///

import contextlib
import json
import sys
from pathlib import Path

import torchaudio
from chatterbox.tts_turbo import ChatterboxTurboTTS

model = None


def send(event):
    print(json.dumps(event, separators=(",", ":")), flush=True)


for raw_line in sys.stdin:
    request = {}
    try:
        request = json.loads(raw_line)
        operation = request.get("op")

        if operation == "load":
            reference = Path(request["reference_wav"]).expanduser().resolve()
            if not reference.is_file():
                raise ValueError("Reference WAV does not exist")
            with contextlib.redirect_stdout(sys.stderr):
                model = ChatterboxTurboTTS.from_pretrained(device="cpu", nano=True)
                model.prepare_conditionals(str(reference))
            send({"event": "ready", "sample_rate": model.sr})
        elif operation == "synthesize":
            if model is None:
                raise ValueError("Worker is not loaded")
            text = request["text"].strip()
            if not text or len(text) > 500:
                raise ValueError("Reply must contain 1 to 500 characters")
            output = Path(request["output_wav"]).expanduser().resolve()
            output.parent.mkdir(parents=True, exist_ok=True)
            with contextlib.redirect_stdout(sys.stderr):
                audio = model.generate(text)
            torchaudio.save(str(output), audio.cpu(), model.sr)
            send({"event": "completed", "id": request["id"], "output_wav": str(output)})
        elif operation == "shutdown":
            send({"event": "stopped"})
            break
        else:
            raise ValueError("Unknown operation")
    except Exception as error:
        send({"event": "error", "id": request.get("id") if isinstance(request, dict) else None, "message": str(error)})
