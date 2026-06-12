# Hush

Local, private dictation and meeting recording for macOS. Push-to-talk speech-to-text that pastes into any app, plus full meeting capture (mic + system audio) with on-device transcription and speaker diarization. Nothing leaves your machine.

<p align="center">
  <img src="Assets/menubar-icon-preview.png" alt="Hush menubar icon" width="120" />
</p>

## Features

- **Push-to-talk dictation** — hold a hotkey, speak, release; the text is pasted at your cursor in any app.
- **Meeting recording** — capture microphone + system audio simultaneously, with software AEC and per-speaker diarization.
- **On-device STT** — runs on Apple Neural Engine via [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Whisper) or [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet). No cloud, no API keys.
- **Custom vocabulary & snippets** — bias the model toward your jargon; expand short triggers into longer text.
- **History & library** — every dictation and meeting is saved locally in SQLite (GRDB), searchable and re-processable.
- **CLI companion** (`hush-cli`) — headless transcription, model management, and scripting hooks.
- **Menu-bar app** with notch-aware overlay, idle pill, and SwiftUI settings.

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon recommended
- Xcode 15+ / Swift 5.9 toolchain
- Permissions Hush will request on first run:
  - Accessibility (to paste into other apps)
  - Microphone
  - Screen Recording (required to capture system audio for meetings)

## Install

### Download the prebuilt DMG

Grab the latest `Hush-<version>.dmg` from the [Releases page](https://github.com/rasmusjosefsson/hush/releases/latest) and drag `Hush.app` into `/Applications`.

Builds are **ad-hoc signed**, not notarized (no Apple Developer ID). On first launch macOS will refuse to open the app. To allow it:

- Right-click `Hush.app` → **Open** → **Open** in the dialog, **or**
- Run once in Terminal:
  ```bash
  xattr -dr com.apple.quarantine /Applications/Hush.app
  ```

Apple Silicon only (arm64, macOS 14+).

### Run the GUI app from source

```bash
./scripts/dev/run_app.sh
```

Builds a signed debug bundle via `xcodebuild` and launches it. Logs stream to `$TMPDIR/hush-dev.log`.

### Build and install to /Applications

```bash
./scripts/dev/install.sh
```

Builds a release bundle, quits any running Hush, and copies it to `/Applications`.

### Distribution build (signed + notarized DMG)

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
SKIP_NOTARIZE=0 \
  ./scripts/dist/build_and_sign.sh
```

Outputs to `dist/`. See `scripts/dist/sign_notarize.sh` for the full env-var contract.

## CLI

```bash
swift build -c release
.build/release/hush-cli --help
```

Available commands:

| Command | What it does |
| --- | --- |
| `transcribe <file>` | Transcribe an audio file with the configured engine |
| `models` | List, download, and switch STT models |
| `history` | Browse dictation history |
| `flow process` | Run the text-processing pipeline on stdin |
| `flow words` / `flow snippets` | Manage custom vocabulary and snippets |
| `health` | Diagnose permissions, models, and audio devices |

## Architecture

Five SwiftPM targets keep concerns separated and previewable:

```
Hush            ← AppKit/SwiftUI entrypoint, controllers, AppDelegate
 ├─ HushUI         ← SwiftUI views (no AppKit, previewable)
 ├─ HushViewModels ← @MainActor view models, testable
 └─ HushCore       ← Audio, STT, DB, services. No UI deps.
    └─ HushObjCShims ← NSException bridge for Swift
CLI             ← hush-cli, depends on HushCore only
```

Key subsystems live in `Sources/HushCore`:

- `Audio/` — capture (mic + system tap), chunking, format conversion
- `STT/` — WhisperKit + FluidAudio dispatchers, model registry, scheduler
- `Services/` — dictation flow, meeting recording, clipboard, permissions, crash reporting
- `Database/` — GRDB repositories for dictations, transcriptions, custom words, snippets
- `DictationFlow/` & `MeetingRecordingFlow/` — explicit state machines for each user-facing flow

## Development

```bash
# Run the full test suite + format/lint locally
./scripts/dev/ci_local.sh

# Or just the tests
swift test
```

Tests cover state machines, services, repositories, view models, and end-to-end dictation/transcription flows with mocked STT.

## License

[MIT](LICENSE) © Rasmus Josefsson
