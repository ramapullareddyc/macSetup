# Mac Developer Environment Setup

Automated provisioning of a Mac laptop for cross-platform React Native development and AI/LLM-powered app development.

## Quick Start

```bash
git clone https://github.com/ramapullareddyc/macSetup.git
cd macSetup
cp setup.conf.example setup.conf   # edit with your details
chmod +x setup.sh
./setup.sh
```

### Interactive Mode

Pick only the phases you want:

```bash
./setup.sh --interactive
```

This shows a menu:

```
  [✅] 1. Foundation (Homebrew, Git, SSH, GPG, Xcode, CLI) (required)
  [✅] 2. Shell Configuration (Oh My Zsh, Starship, plugins, .zshrc)
  [✅] 3. macOS System Preferences
  [✅] 4. Development Tools (editors, terminals, Docker, mise)
  [✅] 5. AI & LLM Development (Ollama, LM Studio, Open WebUI, Gemini)
  [✅] 6. React Native Environment (SDK, emulators, CocoaPods)
  [✅] 7. Cloud CLI Tools (AWS, Wrangler)
  [✅] 8. Browsers (Chrome, Firefox)
  [✅] 9. Productivity & Communication Apps (30+ apps)

  Commands:  <number> toggle   |   A select all   |   N unselect all   |   Enter confirm
```

- Type a number (e.g. `3`) to toggle it on/off
- Type multiple numbers (e.g. `7 8 9`) to toggle several at once
- `A` selects all, `N` unselects all (then toggle individual ones back)
- Press Enter to confirm and start

Phase 1 always runs (everything else depends on it). Validation always runs at the end.

### Configuration (optional)

Edit `setup.conf` before running to automate manual steps:

```bash
# setup.conf
GIT_USER_NAME="Your Name"
GIT_USER_EMAIL="you@example.com"
GITHUB_TOKEN="ghp_xxxx"           # auto-authenticates gh CLI
ENABLE_GPG_SIGNING="true"         # generates GPG key + enables signed commits
OLLAMA_MODEL="qwen2.5-coder:7b"  # set to "" to skip model download
```

Any value left blank becomes a manual post-setup task. The file is gitignored (contains secrets) — `setup.conf.example` is the committed template.

The script is **idempotent** — safe to re-run at any time. All output is logged to `~/mac-setup.log`.

## Requirements

- macOS (Apple Silicon or Intel)
- Admin privileges (sudo password will be prompted)
- Internet connection
- Apple ID signed in to the Mac App Store (required for Xcode)

## What Gets Installed

### Phase 1: Foundation

Sets up the core toolchain everything else depends on.

| Tool | Purpose |
|------|---------|
| [Rosetta 2](https://support.apple.com/en-us/102527) | Translates Intel binaries on Apple Silicon (some npm native modules still need it) |
| [Homebrew](https://brew.sh) | macOS package manager — installs everything else |
| Git | Version control with sensible defaults (`main` branch, rebase on pull) |
| SSH key (Ed25519) | Generated automatically, added to macOS Keychain |
| GPG + pinentry-mac | Installed for optional commit signing (key generation is manual) |
| [Xcode](https://developer.apple.com/xcode/) | Full IDE required for iOS builds — installed via Mac App Store |
| CLI utilities | `jq`, `tree`, `gh`, `eza`, `zoxide`, `bat`, `htop`, `wget`, `tldr` |

**SSH details:** Generates `~/.ssh/id_ed25519` with an empty passphrase and writes `~/.ssh/config` for Keychain integration. Skips both if they already exist (won't overwrite your keys).

**Xcode note:** ~12 GB download. If the App Store isn't signed in, the script logs a warning and continues — re-run after signing in.

### Phase 2: Shell Configuration

Builds a complete Zsh environment from scratch.

| Component | What it does |
|-----------|-------------|
| [Oh My Zsh](https://ohmyz.sh) | Zsh framework for plugins and themes |
| [Starship](https://starship.rs) | Cross-shell prompt (Rust-based, fast, minimal config) |
| [MesloLGS Nerd Font](https://github.com/ryanoasis/nerd-fonts) | Patched font with icons for Starship, eza, and git status |
| Zsh plugins | autosuggestions, completions, history-substring-search, syntax-highlighting, fzf |

**`.zshrc` is fully generated** with this ordering (order matters):

1. Oh My Zsh core (`ZSH_THEME=""` — Starship handles the prompt)
2. Git aliases (`gitac`, `gitsync`, `gitst`, etc.)
3. Utility aliases (`ls` → `eza`, `cat` → `bat`, `ll`, `lt`)
4. `zoxide init` (smarter `cd`)
5. `GPG_TTY` export
6. Homebrew shellenv (must come before mise)
7. `mise activate` (guarded — skips if mise isn't installed yet)
8. Android SDK environment variables
9. AWS CLI completion
10. `starship init` (must be last)

**Starship config:** If `dotfiles/starship.toml` exists in the repo, it's copied to `~/.config/starship.toml`. Otherwise Starship uses its built-in defaults. Customize anytime by editing that file.

### Phase 3: macOS System Preferences

Applies developer-friendly defaults via `defaults write`:

| Setting | Value |
|---------|-------|
| Finder: show hidden files | ✅ |
| Finder: show path bar | ✅ |
| Finder: show all extensions | ✅ |
| Finder: default to list view | ✅ |
| Finder: search current folder | ✅ (not entire Mac) |
| Finder: full path in title bar | ✅ |
| Finder: small sidebar icons | ✅ |
| Finder: spring-loaded folders | ✅ (fast delay) |
| Keyboard: key repeat speed | Fast (2) |
| Keyboard: initial repeat delay | Short (15) |
| Input: auto-correct | ❌ Off |
| Input: smart quotes | ❌ Off |
| Input: smart dashes | ❌ Off |
| Input: auto-capitalize | ❌ Off |
| Input: period with double-space | ❌ Off |
| Dock: auto-hide | ✅ (no delay) |
| Dock: icon size | 48px |
| Dock: minimize to app icon | ✅ |
| Dock: show recent apps | ❌ Off |
| Mission Control: group by app | ✅ |
| Mission Control: rearrange Spaces | ❌ Off |
| Spaces: span displays | ❌ Off (independent per display) |
| Hot corners | Bottom-left: Mission Control, Bottom-right: Desktop |
| Trackpad: tap to click | ✅ |
| Screenshots | Saved to `~/Screenshots` instead of Desktop |
| .DS_Store | Disabled on network and USB volumes |
| Battery percentage | Shown in menu bar |
| Password after sleep | Immediately |
| Firewall | ✅ On |
| Save/Print dialogs | Expanded by default |
| Crash Reporter | ❌ Off (no dialog, no submission) |

Restarts Finder, Dock, and SystemUIServer to apply changes immediately.

### Phase 4: Development Tools

#### Editors & IDEs

| App | Notes |
|-----|-------|
| [VS Code](https://code.visualstudio.com) | Primary editor — extensions installed automatically |
| [Cursor](https://cursor.sh) | AI-native editor (inherits VS Code extensions) |
| [Zed](https://zed.dev) | GPU-accelerated editor written in Rust |
| [Android Studio](https://developer.android.com/studio) | Required for React Native Android builds |

**VS Code extensions installed:**
- Cline (agentic AI assistant)
- Continue.dev (autocomplete + chat with local models)
- ESLint
- Prettier
- React Native Tools

**VS Code settings:** Terminal font set to MesloLGS NF automatically via `jq` merge (preserves existing settings).

#### Terminals

| App | Notes |
|-----|-------|
| [iTerm2](https://iterm2.com) | Feature-rich terminal (font configured via PlistBuddy) |
| [Ghostty](https://ghostty.org) | GPU-accelerated, minimal terminal (font configured via config file) |

Both get Nerd Font configured automatically. Use whichever you prefer.

#### Docker

[Docker Desktop](https://www.docker.com/products/docker-desktop/) — required for Open WebUI and general container workflows.

#### mise + Language Runtimes

[mise](https://mise.jdx.dev) is a polyglot version manager replacing asdf/nvm/pyenv. It manages installations, PATH, and environment variables from a single config.

| Runtime | Version | Notes |
|---------|---------|-------|
| Node.js | LTS | For React Native, Expo, npm packages |
| Python | Latest | For AI/ML libraries, scripting |
| Java | Zulu 17 | Azul Zulu JDK — required by React Native/Android |

**JAVA_HOME** is managed by mise via `~/.config/mise/config.toml`. A symlink is also created at `/Library/Java/JavaVirtualMachines/zulu-17.jdk` so `/usr/libexec/java_home` can discover it.

**Project-level overrides:** Run `mise use node@20` inside any project directory to pin a different version — mise swaps automatically when you `cd` in.

### Phase 5: AI & LLM Development

All tools are free or have generous free tiers.

| Tool | What it does |
|------|-------------|
| [Ollama](https://ollama.com) | Runs open-source LLMs locally with Apple Silicon Metal acceleration. Exposes OpenAI-compatible API on `localhost:11434` |
| [LM Studio](https://lmstudio.ai) | Desktop GUI for browsing/downloading/running Hugging Face models via MLX |
| [Open WebUI](https://github.com/open-webui/open-webui) | Self-hosted ChatGPT-style web interface connected to Ollama (Docker container on `localhost:3000`) |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | Google's terminal agent — Gemini 2.5 Pro with 1M token context, free tier with Google account |
| [Continue.dev](https://continue.dev) | VS Code extension — autocomplete + chat backed by local Ollama models |
| [Cline](https://github.com/cline/cline) | VS Code extension — agentic multi-file editing, can use Ollama as backend |

**Ollama:** The script starts Ollama, waits for readiness (health check loop), pulls `qwen2.5-coder:7b` as a starter coding model, then stops the server. Model sizes: 7B ≈ 8GB RAM, 14B ≈ 16GB, 70B ≈ 48GB.

**Open WebUI:** Runs as a Docker container with `--restart always`. Auto-discovers Ollama models. Create your account at `http://localhost:3000` after setup.

**Recommended project-level libraries** (not installed globally):

| Library | Purpose |
|---------|---------|
| `ai` (Vercel AI SDK) | Provider-agnostic TypeScript toolkit for streaming, tool calling, agents |
| `ollama` | Official JS client for local Ollama API |
| `langchain` | Chains, RAG, agents, vector stores |
| `huggingface-hub` (Python) | Download/manage models from Hugging Face |

### Phase 6: React Native

Targets React Native 0.83 / Expo SDK 55 (2026). The New Architecture (JSI, Fabric, TurboModules) is mandatory.

| Tool | Purpose |
|------|---------|
| [Watchman](https://facebook.github.io/watchman/) | File watcher for Metro bundler |
| [CocoaPods](https://cocoapods.org) | iOS dependency manager |
| [EAS CLI](https://docs.expo.dev/eas/) | Expo Application Services — build, submit, update |

**Android SDK:** Installs platform-tools, Android 16 (API 36), build-tools, ARM64 system image, emulator, and command-line tools. Creates a `Pixel_8_API_36` AVD.

**iOS Simulator:** Downloads the latest iOS runtime via `xcodebuild -downloadPlatform iOS`.

**Debugging:** [Reactotron](https://github.com/infinitered/reactotron) for network inspection. React Native DevTools (built-in since RN 0.73) replaces the archived Flipper — press `j` in Metro to launch.

### Phase 7: Cloud CLI Tools

| Tool | Purpose |
|------|---------|
| [AWS CLI v2](https://aws.amazon.com/cli/) | AWS resource management |
| [Wrangler](https://developers.cloudflare.com/workers/wrangler/) | Cloudflare Workers, Pages, R2, D1, KV |

### Phase 8: Browsers

Google Chrome and Firefox.

### Phase 9: Productivity & Communication Apps

**Office & Productivity:** Microsoft Office, Notion, Obsidian, Zoom
**Communication:** Telegram, WhatsApp, Discord
**Cloud Storage:** Google Drive
**Dev Productivity:** Postman, Raycast, Rectangle, 1Password
**Media:** Spotify, VLC, IINA
**Utilities:** AppCleaner, The Unarchiver, Keka, AltTab, Stats, KeepingYouAwake
**Security:** [AdGuard](https://adguard.com) (ad/tracker blocker), [AdGuard VPN](https://adguard-vpn.com), [VPN Unlimited](https://www.vpnunlimitedapp.com) (KeepSolid), [KeepSolid SmartDNS](https://www.keepsolid.com/smartdns/), [Deeper Network DPN](https://deeper.network) (decentralized VPN — installed via DMG), [Moonlock](https://macpaw.com/moonlock) (MacPaw) — Moonlock installed via DMG (not in Homebrew)

### Phase 11: Validation

Runs automatically at the end. Checks every tool, environment variable, and app with pass/fail output. Review `~/mac-setup.log` for the full report.

## Design Principles

**Idempotent** — Every operation is guarded. SSH keys aren't regenerated if they exist. Git clones are skipped if the directory exists. Homebrew skips already-installed packages. Docker containers are checked before creation. Safe to re-run after a partial failure or to pick up new additions.

**Error handling** — Phase 1 (Foundation) is critical and aborts on failure since everything depends on it. Phases 2–9 are wrapped in `run_phase` which catches failures, logs them, and continues to the next phase. You won't lose progress on 25 app installs because one cask failed.

**Logging** — All stdout and stderr are teed to `~/mac-setup.log`. Check this file to diagnose any failures.

## Customization

**Skip a phase:** Comment out the corresponding `run_phase` line at the bottom of `setup.sh`.

**Change runtimes:** Edit the `mise use --global` lines in `phase_4_mise`. For example, `mise use --global node@20` instead of `node@lts`.

**Change Ollama model:** Edit the `ollama pull` line in `phase_5_ollama`. Popular options: `llama3.1:8b`, `codellama:13b`, `deepseek-coder-v2:16b`.

**Add/remove apps:** Edit the `brew install --cask` lines in the relevant phase function.

**Customize Starship:** Edit `dotfiles/starship.toml` before running, or edit `~/.config/starship.toml` after.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Xcode install fails | Sign into the Mac App Store first, then re-run the script |
| `sdkmanager` not found | Launch Android Studio once to complete the setup wizard, then re-run |
| Docker commands fail | Docker Desktop needs to be launched once after install; the script waits up to 60s |
| Ollama model pull fails | Run `ollama serve` then `ollama pull qwen2.5-coder:7b` manually |
| Open WebUI won't start | Ensure Docker is running: `docker start open-webui` |
| VS Code extensions not installed | Launch VS Code once, then run `code --install-extension <id>` manually |
| `mise` not activating | Ensure `eval "$(mise activate zsh)"` is in your `.zshrc` and restart terminal |

## Post-Setup Manual Steps

After the script completes, it prints a checklist. The full list:

- [ ] `git config --global user.name "<name>"` and `user.email`
- [ ] `gh auth login` — authenticate GitHub CLI
- [ ] Add SSH key to GitHub: `cat ~/.ssh/id_ed25519.pub` → [GitHub SSH settings](https://github.com/settings/keys)
- [ ] Generate GPG key: `gpg --full-generate-key` → add to GitHub for signed commits
- [ ] Launch Android Studio → complete first-run setup wizard
- [ ] Configure Continue.dev in VS Code → select "Local" → verify Ollama models detected
- [ ] Configure Cline in VS Code → API Provider → "Ollama" → select model
- [ ] Authenticate Gemini CLI: run `gemini` and sign in with Google
- [ ] Create Open WebUI account at `http://localhost:3000`
- [ ] Launch Moonlock → grant permissions (Full Disk Access, System Extension) → activate license
- [ ] Sign into apps: Chrome, Office, 1Password, Spotify, Zoom, Telegram, WhatsApp, Discord
- [ ] Install browser extensions: uBlock Origin, 1Password
- [ ] Authorize Google Drive

## Files

| File | Purpose |
|------|---------|
| `setup.sh` | Main setup script (629 lines) |
| `setup.conf.example` | Configuration template — copy to `setup.conf` and edit |
| `Brewfile` | Standalone `brew bundle --file=Brewfile` alternative |
| `MAC_SETUP_SPEC.md` | Detailed spec with rationale, links, and implementation notes |
| `dotfiles/starship.toml` | Starship prompt configuration |

## License

MIT
