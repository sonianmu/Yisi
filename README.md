<div align="center">
  <img src="./assets/icon.svg" width="120" height="120" alt="Yisi Icon">
  <h1>Yisi</h1>
  <p><b>Intelligent semantic conversion tool for macOS</b> -- Select, trigger, present. No chat windows, no context switching. AI completes the conversion silently within your workflow.</p>
  <p>English | <a href="./README.zh-CN.md">简体中文</a></p>
</div>

[![GitHub release](https://img.shields.io/github/v/release/sonianmu/Yisi)](https://github.com/sonianmu/Yisi/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)](https://github.com/sonianmu/Yisi/releases)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

---

## Screenshot

![Yisi](assets/promo-desktop.jpg)

---

## Features

- **Instant Translation** -- Select text, press a shortcut, and the translation appears in place. Built-in finely-tuned prompts produce natural, authentic output instead of mechanical word-for-word conversion
- **Learned Rules** -- Correct a term or adjust an expression, and Yisi remembers your preference and applies it automatically in future translations
- **Offline Translation** -- Integrated with macOS native System Translation. Works entirely offline with all data processed locally
- **Preset Mode** -- Pre-define input perception and output instructions once, valid forever. Select to trigger, trigger to complete, zero extra steps
- **Custom Mode** -- For one-off needs without pre-configuration. Fill in "What is this" and "What to do" at the moment of triggering
- **Screenshot Recognition** -- Capture any screen region via shortcut and send the image directly to AI for analysis. Design mockups, error dialogs, data charts all supported
- **Configurable AI Services** -- Built-in Gemini, OpenAI, Zhipu AI, DeepSeek, and MiniMax connection templates, plus custom OpenAI-compatible Chat Completions, Gemini native, and Anthropic Messages endpoints. Enter the model ID you want to use; text and vision services can be configured independently
- **Translation History** -- All conversion results persist locally for future reference
- **Menu Bar Resident** -- Lives in the macOS menu bar without occupying a Dock slot
- **Dark / Light Theme** -- Follows system appearance or manual toggle
- **Auto Update** -- Check and download new versions from within the app
- **Launch at Login** -- Automatically registers as a login item on first launch

---

## Design Philosophy

> Yisi has no chatbox.

It's not "select content -> open chat -> describe request -> wait for reply." It's "select -> present."

No back-and-forth, no chat history, no AI name or avatar. Your selected content on the left, its new form on the right. Close the window and everything is as it was -- except the task is already done.

AI is not a conversational partner you visit. It's a silent link in your workflow.

---

## Requirements

| Requirement | Minimum |
|-------------|---------|
| **macOS** | 14.0+ (Sonoma) |
| **Chip** | Apple Silicon / Intel |

> **Note**: Yisi requires Accessibility permission to capture selected text. The system will prompt for authorization on first use. Grant access in **System Settings > Privacy & Security > Accessibility**.

---

## Quick Start

### Installation

Download the latest `.dmg` from the [Releases](https://github.com/sonianmu/Yisi/releases) page and drag it into the Applications folder.

### Three Steps to Convert

1. **Select** -- Highlight text in any app, or press the screenshot shortcut to capture a screen region
2. **Trigger** -- `Cmd + C + C` (text) / `Cmd + Shift + X` (screenshot)
3. **Present** -- Results appear instantly in a popup. Close to dismiss

Shortcuts are customizable in Settings > General.

### Five-Minute Setup

1. Obtain an API key and a model ID from your provider.
2. Open **Settings > AI Services**, select a provider, and enter both fields. Model IDs are initially blank; existing saved models are retained.
3. For another endpoint, choose **Custom Service** and enter its protocol and base URL. Expand **Advanced Adaptation** only if the model needs specific reasoning or request settings.
4. Click **Test and Save**. A successful response saves the configuration and selects AI Translation. A failed test shows the error and keeps the previous configuration.
5. For screenshots, choose system OCR or configure an AI vision service in the same way. Reusing the text service requires an image-capable model.

AI Translation is the default for new configurations. To use macOS translation instead, select **System Translation** in **Settings > Translation**. Without a saved AI key and model, Yisi prompts you to configure the service or switch engines. Existing users' engine selections are retained until a successful service save.

---

## Installation Troubleshooting

Yisi uses ad-hoc signing and is not notarized by Apple, so macOS may show security warnings on first launch.

**Option 1 -- Right-click to Open**

1. Right-click (or Control-click) `Yisi.app` in Finder
2. Select **Open** from the context menu
3. Click **Open** in the confirmation dialog

**Option 2 -- System Settings**

1. Open **System Settings** > **Privacy & Security**
2. Scroll to the **Security** section and click **Open Anyway**

**Option 3 -- Terminal**

```bash
xattr -cr /Applications/Yisi.app
```

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 5.9 |
| UI Framework | SwiftUI |
| Minimum OS | macOS 14 (Sonoma) |
| Text Capture | Accessibility API + Clipboard fallback |
| Screen Capture | ScreenCaptureKit |
| Offline Translation | macOS System Translation |
| AI Integration | Gemini / OpenAI / Zhipu / DeepSeek / MiniMax REST API |
| Learning Engine | Local rule storage + automatic prompt injection |
| Distribution | DMG (manual build) |

---

## Project Structure

```
Yisi/
├── .github/workflows/       # CI/CD
├── docs/                    # Design docs
├── assets/                   # App icon and static assets
├── scripts/                  # Build and utility scripts
├── web/                      # Website (yisi.pages.dev)
├── Yisi/
│   ├── YisiApp.swift         # App entry, menu bar, shortcut registration
│   ├── Core/
│   │   ├── AI/               # AI service layer
│   │   │   ├── AIService.swift       # Unified AI call interface
│   │   │   ├── Models.swift          # Model definitions
│   │   │   ├── Prompts/             # Translation and conversion prompts
│   │   │   └── Providers/           # Gemini / OpenAI / Zhipu / DeepSeek / MiniMax
│   │   ├── Capture/          # Text capture (Accessibility + Clipboard)
│   │   ├── Design/           # Design system (themes, colors, visual effects)
│   │   ├── History/          # Translation history persistence
│   │   ├── Learning/         # Learned Rules engine
│   │   ├── Localization/     # Multi-language support
│   │   ├── Shared/           # Shared constants and configuration
│   │   ├── Shortcut/         # Global shortcut management
│   │   ├── SystemTranslation/# macOS native offline translation
│   │   └── Utils/            # Utilities
│   └── UI/
│       ├── Components/       # Reusable UI components
│       ├── Layout/           # Layout containers
│       ├── ScreenCapture/    # Screenshot overlay
│       ├── Settings/         # Settings panel + Welcome guide
│       ├── Translation/      # Translation result popup
│       └── Window/           # Window management
├── Package.swift
└── LICENSE                   # GPL-3.0
```

---

## Build from Source

```bash
# Clone the repository
git clone https://github.com/sonianmu/Yisi.git
cd Yisi

# Open the Swift package in Xcode
xed .
# Or build via command line
swift build -c release
```

To create a universal installer for Apple Silicon and Intel:

```bash
VERSION=1.3.0 ./scripts/build_dmg.sh
```

The script outputs `Yisi.dmg` and `build-app/Release/Yisi.app`. It does not publish a GitHub release or change user data.

For local development, use `./scripts/fresh-start.sh --close`, `--start`, or `--new`. Closing and starting preserve data; `--new` builds and registers the app, resets Yisi's permissions, then clears preferences, history, history images, learned rules, and API keys before launching. If macOS cannot yet resolve the bundle ID on first use, permission reset is skipped with a warning; other permission errors stop before data is cleared. Add `--keep-keys --keep-permissions` to retain credentials and permissions, or `--dry-run` to preview operations. The development app is built at `build-app/Debug/Yisi.app`; logs are saved in `~/Library/Logs/Yisi/`. Automatic update checks are disabled for the development session without changing saved preferences.

First launch shows onboarding before Settings. The screen recording step requests system authorization and offers “Show App in Finder” so you can select the exact `Yisi.app` with the permission page's `+` button if needed. The app restarts when authorization is detected. Development builds use ad-hoc signing, so rebuilding may require authorization again.

---

## Supported AI Services

| Connection template | Text | Vision |
|---------------------|------|--------|
| Gemini | Yes | With an image-capable model |
| OpenAI | Yes | With an image-capable model |
| Zhipu AI | Yes | With an image-capable model |
| DeepSeek | Yes | Not offered as a built-in vision template |
| MiniMax | Yes | Not offered as a built-in vision template |
| Custom Service | Yes | With an image-capable model and endpoint |

Models are entered by the user rather than tied to a fixed model list. Availability and supported features depend on your provider, account, model, and protocol. The thinking toggle uses the model's configured reasoning adapter; expand Advanced Adaptation when necessary. New custom API keys are stored in Keychain. See [model service configuration](docs/model-services.md) (Chinese).

## Updates and Permissions

On the first launch after an update, Yisi checks the version and signing identity. An ad-hoc signature change, including the initial migration from an older version, automatically refreshes Yisi's Accessibility and Screen Recording permission entries and resumes at the required authorization step. Users do not need to click Software Repair first. API keys, service settings, and history are retained; recorded attempts prevent repeated resets on ordinary restarts.

macOS may still require users to confirm permission. Migration cannot grant authorization silently. Valid permissions are retained when a stable signing identity remains unchanged. Automatic processing failures are reported with a GitHub Issues option.

## Software Repair

If Yisi stops working, choose **Software Repair** in **Settings > General** or the menu bar icon's context menu. Repair preserves API keys, service settings, translation history, history images, presets, and learned rules. It backs up caches and the preferences it resets, restores appearance, shortcuts, and window placement, and attempts to reset failed Accessibility or Screen Recording permissions before restarting. macOS may still require you to grant permission.

The confirmation explains that some temporary data or personalization may be lost. Backups are stored in `~/Library/Application Support/com.sonianmu.yisi/RepairBackups/`. If repair does not help, report the problem through [GitHub Issues](https://github.com/sonianmu/Yisi/issues).

---

## Contributing

Contributions are welcome. Before you start:

1. Fork this repository and create a feature branch
2. Open the project in Xcode and test locally
3. Ensure consistent code style
4. Submit a PR to the `main` branch with a clear description of changes

Keep PRs focused -- one feature or fix per PR.

---

## License

[GPL-3.0](LICENSE) -- Copyright (C) 2026 Sonian Mu
