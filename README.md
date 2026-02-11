# Mac Developer Environment Setup

Automated provisioning of a Mac laptop for cross-platform React Native development and AI/LLM-powered app development.

## What's Included

- **Foundation** — Homebrew, Git, SSH, GPG, Xcode, modern CLI tools (eza, bat, zoxide, gh)
- **Shell** — Oh My Zsh + Starship prompt + Nerd Font + plugins
- **macOS Preferences** — Dock, Finder, keyboard, trackpad, screenshots
- **Editors** — VS Code, Cursor, Zed, Android Studio
- **Terminals** — iTerm2, Ghostty
- **Runtimes** — Node (LTS), Python, Java (Zulu 17) via mise
- **AI/LLM** — Ollama, LM Studio, Open WebUI, Gemini CLI, Continue.dev, Cline
- **React Native** — Watchman, CocoaPods, EAS CLI, Android SDK 36, iOS Simulator, Reactotron
- **Cloud** — AWS CLI, Cloudflare Wrangler
- **Apps** — 30+ productivity, communication, media, and utility apps

## Quick Start

```bash
chmod +x setup.sh
./setup.sh
```

The script is **idempotent** — safe to re-run. All output is logged to `~/mac-setup.log`.

## Files

| File | Purpose |
|------|---------|
| `setup.sh` | Main setup script |
| `Brewfile` | Standalone `brew bundle` alternative |
| `MAC_SETUP_SPEC.md` | Detailed spec document |
| `dotfiles/starship.toml` | Optional Starship prompt config |

## Requirements

- macOS (Apple Silicon or Intel)
- Admin privileges
- Internet connection
- Apple ID signed in (for Xcode / App Store installs)

## Post-Setup

After running the script, see the printed checklist or refer to the "Post-Setup Manual Steps" section in `MAC_SETUP_SPEC.md`.
