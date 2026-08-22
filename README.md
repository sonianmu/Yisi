<div align="center">
  <img src="./assets/icon.svg" width="120" height="120" alt="Yisi Icon">
  <h1>Yisi</h1>
  <p><b>Intelligent semantic conversion tool for macOS</b> -- Select, trigger, present. No chat windows, no context switching. AI completes the conversion silently within your workflow.</p>
  <p>English | <a href="./README.zh-CN.md">简体中文</a></p>
</div>

[![GitHub release](https://img.shields.io/github/v/release/MUTRO888/Yisi)](https://github.com/MUTRO888/Yisi/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)](https://github.com/MUTRO888/Yisi/releases)
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
- **Multiple AI Providers** -- Supports Gemini, OpenAI, Zhipu AI, DeepSeek, and MiniMax. Text and vision models can be configured independently
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

Download the latest `.dmg` from the [Releases](https://github.com/MUTRO888/Yisi/releases) page and drag it into the Applications folder.

### Three Steps to Convert

1. **Select** -- Highlight text in any app, or press the screenshot shortcut to capture a screen region
2. **Trigger** -- `Cmd + C + C` (text) / `Cmd + Shift + X` (screenshot)
3. **Present** -- Results appear instantly in a popup. Close to dismiss

Shortcuts are customizable in Settings > General.

### Five-Minute Setup

Yisi supports five AI providers. We recommend starting with Zhipu AI -- new users receive free tokens upon registration.

1. Go to [Zhipu AI Platform](https://open.bigmodel.cn) to register and get an API Key
2. Open Yisi > Settings > AI Services
3. Select Zhipu AI as the provider and paste the API Key
4. Models are pre-configured out of the box
5. Done. Ready to use

---

## Installation Troubleshooting

Yisi is not yet code-signed, so macOS will show security warnings on first launch.

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
git clone https://github.com/MUTRO888/Yisi.git
cd Yisi

# Open the Swift package in Xcode
xed .
# Or build via command line
swift build -c release
```

---

## Supported AI Providers

| Provider | Text Model | Vision Model | Notes |
|----------|-----------|-------------|-------|
| **Gemini** | Gemini Pro etc. | Gemini Pro Vision | Google AI |
| **OpenAI** | GPT-4o etc. | GPT-4o | Any OpenAI-compatible service |
| **Zhipu AI** | GLM-4 etc. | GLM-4V | Recommended for Chinese users, free tokens for new users |
| **DeepSeek** | DeepSeek Chat | -- | Cost-effective |
| **MiniMax** | MiniMax Chat | -- | Chinese LLM |

Text and vision models can be configured independently for the optimal combination.

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
