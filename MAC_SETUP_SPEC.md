# Mac Developer Environment Automated Setup Spec

## Overview

Automate the provisioning of a new Mac laptop for cross-platform React Native development using a shell script powered primarily by Homebrew (`brew install --cask` for GUI apps, `brew install` for CLI tools).

Sources: [React Native Environment Setup](https://reactnative.dev/docs/set-up-your-environment), [Android SDK Environment Variables](https://developer.android.com/tools/variables), [mise Getting Started](https://mise.jdx.dev/getting-started.html), [mise Java](https://mise.jdx.dev/lang/java.html)

## Prerequisites

- macOS (Apple Silicon or Intel)
- Admin privileges
- Internet connection
- Apple ID signed in (required for Xcode/App Store installs)

## ⚠️ Items Requiring Clarification

| # | Item | Issue |
|---|------|-------|
| 6 | **Google Antigravity** | Not a known product. Did you mean Google Earth, Chrome Remote Desktop, or something else? |
| 7 | **Cline** | Assuming the Cline VS Code extension (AI coding assistant). Will install via `code --install-extension`. Confirm? |

---

## Phase 1: Foundation

### 1.1 Rosetta 2 (Apple Silicon — optional)

Most tools now have native ARM64 support. Rosetta may still be needed for some older npm native modules or legacy tooling:

```bash
softwareupdate --install-rosetta --agree-to-license 2>/dev/null || true
```

### 1.2 Homebrew

```bash
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### 1.3 Set Zsh as Default Shell

```bash
# macOS defaults to zsh since Catalina, but ensure it
chsh -s /bin/zsh
```

### 1.4 Git

```bash
brew install git

# Configure global defaults
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global core.editor "code --wait"
```

Note: `user.name` and `user.email` are left to the Post-Setup Manual Steps since they are personal.

### 1.5 SSH Keys & Config

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Only generate if key doesn't already exist (safe for re-runs)
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  ssh-keygen -t ed25519 -C "your_email@example.com" -f ~/.ssh/id_ed25519 -N ""
  chmod 600 ~/.ssh/id_ed25519
  chmod 644 ~/.ssh/id_ed25519.pub
else
  echo "✅ SSH key already exists, skipping generation"
fi
```

Configure `~/.ssh/config` for macOS Keychain integration so keys persist across reboots (only written on first run — preserves manual customizations):

```bash
if [[ ! -f ~/.ssh/config ]]; then
  cat > ~/.ssh/config << 'EOF'
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519

# Example: separate key for work
# Host github.com-work
#   HostName github.com
#   User git
#   IdentityFile ~/.ssh/id_ed25519_work
EOF
  chmod 600 ~/.ssh/config
else
  echo "✅ SSH config already exists, skipping"
fi
```

Start the agent and add the key to macOS Keychain:

```bash
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/id_ed25519 2>/dev/null || \
  echo "⚠️  Could not add SSH key to keychain — add manually: ssh-add --apple-use-keychain ~/.ssh/id_ed25519"
```

### 1.6 GPG (install only)

Install GPG for optional commit signing. Key generation is interactive and must be done manually (see Post-Setup Manual Steps).

```bash
brew install gnupg pinentry-mac

# Configure GPG to use pinentry-mac (idempotent — only writes if not already configured)
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg
grep -q "pinentry-program" ~/.gnupg/gpg-agent.conf 2>/dev/null || \
  echo "pinentry-program $(brew --prefix)/bin/pinentry-mac" >> ~/.gnupg/gpg-agent.conf
```

Add to `.zshrc` so GPG can prompt for passphrase in terminal:

```bash
export GPG_TTY=$(tty)
```

### 1.7 Xcode

Per the [React Native docs](https://reactnative.dev/docs/set-up-your-environment), full Xcode is required for iOS development.

> ⚠️ Xcode is ~12GB. This step takes 30–60 minutes depending on connection speed. Consider running it early or in parallel with other tasks.

```bash
# Install Command Line Tools (skip if already installed)
xcode-select -p &>/dev/null || xcode-select --install

# mas requires App Store sign-in. Verify before proceeding.
brew install mas
mas list > /dev/null 2>&1 || echo "⚠️  Sign into the App Store before continuing"
mas install 497799835  # Xcode from Mac App Store

# Accept license and set Command Line Tools path (eliminates manual Xcode > Settings step)
sudo xcodebuild -license accept 2>/dev/null || true
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer 2>/dev/null || true
```

> 💡 If Xcode install fails (e.g., no App Store login), the script continues — `xcodebuild` commands will fail gracefully. Re-run after signing in.

### 1.8 CLI Utilities

```bash
brew install jq tree gh eza zoxide bat htop wget tldr

# Populate tldr local cache
tldr --update
```

- `gh` — GitHub CLI for PRs, issues, repo management from terminal. As of Jan 2026, Copilot is built-in (no separate extension needed).
- `eza` — Modern `ls` replacement with git integration, colors, and icons.
- `zoxide` — Smarter `cd` that learns your most-used directories.
- `bat` — `cat` with syntax highlighting and git integration.

---

## Phase 2: Oh My Zsh + Shell Configuration

### 2.1 Install Oh My Zsh

Oh My Zsh creates a default `.zshrc` on install. We will overwrite it with our custom version in step 2.6.

```bash
[[ -d ~/.oh-my-zsh ]] || \
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
```

### 2.2 Install Starship Prompt

[Starship](https://starship.rs) is a cross-shell prompt written in Rust, actively maintained, and configured via `~/.config/starship.toml`.

```bash
brew install starship
```

### 2.3 Install Nerd Font

Starship uses Nerd Font icons for git status, language indicators, etc. A Nerd Font is recommended for the best experience:

```bash
brew install --cask font-meslo-lg-nerd-font
```

### 2.4 Install Custom Zsh Plugins

These are third-party plugins not bundled with Oh My Zsh. Idempotent — skips if already cloned:

```bash
[[ -d ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions ]] || \
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

[[ -d ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-completions ]] || \
  git clone https://github.com/zsh-users/zsh-completions \
    ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-completions

[[ -d ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search ]] || \
  git clone https://github.com/zsh-users/zsh-history-substring-search \
    ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search

[[ -d ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting ]] || \
  git clone https://github.com/zsh-users/zsh-syntax-highlighting \
    ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

### 2.5 Install fzf (required by fzf plugin)

```bash
brew install fzf
```

### 2.6 Generate `.zshrc`

The setup script overwrites the default `.zshrc` created by Oh My Zsh with the following configuration. Order matters — Homebrew must be on PATH before mise and Starship activation.

#### Oh My Zsh Core

```bash
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""  # Disabled — using Starship instead

# Autocomplete
autoload bashcompinit && bashcompinit
autoload -Uz compinit && compinit

plugins=(
    git
    docker
    mise
    zsh-autosuggestions
    zsh-completions
    zsh-history-substring-search
    zsh-syntax-highlighting
    zsh-interactive-cd
    zsh-navigation-tools
    fzf
)

source $ZSH/oh-my-zsh.sh
```

Note: The `docker` plugin provides completions and aliases for Docker CLI. Docker Desktop is installed in Phase 4. The `mise` plugin provides shell completions (see 2.6.1).

#### 2.6.1 mise Shell Completions

> ⚠️ This step runs after Phase 4.5 (mise install), not during Phase 2. It's documented here because it relates to the `.zshrc` plugin list.

```bash
mkdir -p ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/mise
mise completion zsh > ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/mise/_mise
```

#### Aliases — Git

```bash
alias gitbv="git branch -vv"
alias gitd="git diff"
alias gitdo="git diff origin/mainline"
alias gitca="git commit --amend"
alias gitc="git commit -m"
alias gitcho="git checkout "
alias gitaca="git add -A && git commit --amend"
alias gitac="git add -A && git commit -m"
alias gitsync="git pull --rebase"
alias gitst="git status"
```

#### Aliases — Utility

```bash
alias tailf="tail -n 500 -f "
alias up="cd .."
alias ls="eza --icons"
alias ll="eza --icons -la"
alias lt="eza --icons --tree --level=2"
alias cat="bat --paging=never"
```

#### zoxide (smarter cd)

```bash
eval "$(zoxide init zsh)"
```

#### GPG (for signed commits)

```bash
export GPG_TTY=$(tty)
```

#### Homebrew (must come before mise)

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

#### mise Activation

Per [mise docs](https://mise.jdx.dev/getting-started.html#activate-mise), activation in `.zshrc` ensures tools and env vars (including `JAVA_HOME`) are loaded on every prompt:

```bash
command -v mise &>/dev/null && eval "$(mise activate zsh)"
```

Note: `JAVA_HOME` is managed by mise via `~/.config/mise/config.toml` (see Phase 4.5). No manual `JAVA_HOME` export is needed in `.zshrc`.

#### Android SDK Environment Variables

Per the [React Native docs](https://reactnative.dev/docs/set-up-your-environment) and [Android developer docs](https://developer.android.com/tools/variables), the following are required for building React Native apps with native code:

```bash
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin
```

Note: `ANDROID_HOME` points to the default SDK location when installed via Android Studio. The `emulator` path must come before `platform-tools` so the emulator binary is found correctly. `cmdline-tools` is needed for `sdkmanager` and `avdmanager`. The deprecated `ANDROID_SDK_ROOT` is no longer needed — `ANDROID_HOME` is the canonical variable.

#### AWS CLI Completion

```bash
complete -C '/opt/homebrew/bin/aws_completer' aws
```

#### Starship Prompt (must be at end of .zshrc)

```bash
eval "$(starship init zsh)"
```

### 2.7 Starship Config

Copy a pre-configured Starship config, or let Starship use its defaults (which are already good):

```bash
mkdir -p ~/.config
cp ./dotfiles/starship.toml ~/.config/starship.toml 2>/dev/null || true
```

If no config is provided, Starship works out of the box with sensible defaults. Customize later by editing `~/.config/starship.toml`. See [Starship configuration docs](https://starship.rs/config/).

---

## Phase 3: macOS System Preferences

Developer-friendly defaults applied via `defaults write`:

```bash
# Finder — visibility
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Finder — list view by default
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Finder — search current folder by default
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Finder — show full path in title bar
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Finder — small sidebar icons
defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 1

# Finder — spring-loaded folders (faster delay)
defaults write NSGlobalDomain com.apple.springing.enabled -bool true
defaults write NSGlobalDomain com.apple.springing.delay -float 0.3

# Keyboard
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Input — disable auto-correct, smart quotes, smart dashes, auto-capitalize, period shortcut
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# Dock
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.3
defaults write com.apple.dock tilesize -int 48
defaults write com.apple.dock minimize-to-application -bool true
defaults write com.apple.dock show-recents -bool false

# Mission Control — group windows by app, don't rearrange Spaces
defaults write com.apple.dock expose-group-apps -bool true
defaults write com.apple.dock mru-spaces -bool false

# Spaces — independent spaces per display
defaults write com.apple.spaces spans-displays -bool false

# Hot corners — bottom-left: Mission Control, bottom-right: Desktop
defaults write com.apple.dock wvous-bl-corner -int 2
defaults write com.apple.dock wvous-bl-modifier -int 0
defaults write com.apple.dock wvous-br-corner -int 4
defaults write com.apple.dock wvous-br-modifier -int 0

# Trackpad — enable tap to click
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Screenshots — save to ~/Screenshots instead of Desktop
mkdir -p ~/Screenshots
defaults write com.apple.screencapture location -string "$HOME/Screenshots"

# Disable .DS_Store on network and USB volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Battery — show percentage in menu bar
defaults write com.apple.menuextra.battery ShowPercent -string "YES"

# Security — require password immediately after sleep
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

# Security — enable firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null || true

# Dialogs — expand save and print panels by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# Disable Crash Reporter dialog (reports sent silently)
defaults write com.apple.CrashReporter DialogType -string "none"

# Restart affected services
killall Finder
killall Dock
killall SystemUIServer
```

---

## Phase 4: Development Tools

### 4.1 Editors & IDEs

```bash
brew install --cask visual-studio-code
brew install --cask cursor
brew install --cask zed
brew install --cask android-studio
```

### 4.2 VS Code CLI + Extensions

The `code` CLI is not on PATH until VS Code is launched once or the shell command is manually installed. Ensure it's available before installing extensions:

```bash
# Add VS Code CLI to PATH for this session
export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

# Configure Nerd Font for VS Code terminal
VSCODE_SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
VSCODE_SETTINGS="$VSCODE_SETTINGS_DIR/settings.json"
mkdir -p "$VSCODE_SETTINGS_DIR"
if [[ -f "$VSCODE_SETTINGS" ]]; then
  jq '. + {"terminal.integrated.fontFamily": "MesloLGS NF"}' "$VSCODE_SETTINGS" > "$VSCODE_SETTINGS.tmp" \
    && mv "$VSCODE_SETTINGS.tmp" "$VSCODE_SETTINGS"
else
  echo '{"terminal.integrated.fontFamily": "MesloLGS NF"}' > "$VSCODE_SETTINGS"
fi

# Verify code CLI is available before installing extensions
if command -v code &>/dev/null; then
  code --install-extension saoudrizwan.claude-dev       # Cline (agentic AI assistant)
  code --install-extension continue.dev.continue         # Continue (autocomplete + chat, works with local Ollama models)
  code --install-extension dbaeumer.vscode-eslint        # ESLint
  code --install-extension esbenp.prettier-vscode        # Prettier
  code --install-extension msjsdiag.vscode-react-native  # React Native Tools
else
  echo "⚠️  VS Code CLI not found — install extensions manually after launching VS Code"
fi
```

> 💡 Cursor inherits VS Code extensions automatically — no separate install needed.

### 4.3 Terminal

```bash
brew install --cask iterm2
brew install --cask ghostty
```

```bash
# Configure iTerm2 with Nerd Font (takes effect on next launch)
/usr/libexec/PlistBuddy -c "Set ':New Bookmarks:0:Normal Font' MesloLGSNF-Regular 13" \
  ~/Library/Preferences/com.googlecode.iterm2.plist 2>/dev/null || true

# Configure Ghostty with Nerd Font
mkdir -p ~/.config/ghostty
grep -q "font-family" ~/.config/ghostty/config 2>/dev/null || \
  echo "font-family = MesloLGS NF" >> ~/.config/ghostty/config
```

[Ghostty](https://ghostty.org) is a GPU-accelerated, native macOS terminal emulator that has gained rapid adoption in 2025/2026. It's fast, minimal, and configured via `~/.config/ghostty/config`. Install both and pick your preference — iTerm2 for feature richness, Ghostty for speed and simplicity.

### 4.4 Docker

```bash
brew install --cask docker
```

### 4.5 mise + Language Runtimes

Per [mise docs](https://mise.jdx.dev/getting-started.html), mise is a polyglot tool version manager that replaces asdf/nvm/pyenv. It manages installations, PATH, and environment variables from a single config file.

```bash
brew install mise

# Activate mise for the current script session so npm/node are available
eval "$(mise activate zsh)"

# Install language runtimes globally
mise use --global python@latest
mise use --global node@lts
mise use --global java@zulu-17  # Azul Zulu JDK 17, required by React Native

# Generate mise shell completions (referenced in Phase 2.6.1)
mkdir -p ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/mise
mise completion zsh > ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/mise/_mise
```

This writes `~/.config/mise/config.toml`. We then add `JAVA_HOME` to the same file so mise manages it alongside the Java installation:

```toml
# ~/.config/mise/config.toml (generated by mise use, then amended)
[tools]
python = "latest"
node = "lts"
java = "zulu-17"

[env]
JAVA_HOME = "{{env.HOME}}/.local/share/mise/installs/java/zulu-17"
```

When `mise activate zsh` runs in your shell, it sets both the tool PATH entries and `JAVA_HOME` automatically. If you switch Java versions (e.g., a project needs JDK 21), create a local `mise.toml` in that project with the override — mise will swap both the `java` binary and `JAVA_HOME` when you `cd` into that directory.

#### macOS JAVA_HOME Integration

Per the [mise Java docs](https://mise.jdx.dev/lang/java.html), some macOS apps use `/usr/libexec/java_home` to discover JDKs. To support this, create a symlink after mise installs Java:

```bash
sudo mkdir -p /Library/Java/JavaVirtualMachines/zulu-17.jdk
sudo ln -sf ~/.local/share/mise/installs/java/zulu-17/Contents \
  /Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents
```

Verify the setup:

```bash
java -version        # Should show Zulu 17.x
echo $JAVA_HOME      # Should show ~/.local/share/mise/installs/java/zulu-17
/usr/libexec/java_home  # Should resolve the symlinked JDK
```

Note: `mise use --global` writes to `~/.config/mise/config.toml`. For project-specific versions, use `mise use` (without `--global`) inside the project directory — this creates a local `mise.toml`.

---

## Phase 5: AI & LLM Development

Tools for running local LLMs, building LLM-powered apps, and agentic terminal workflows. All tools below are free (Gemini CLI has a generous free tier with a Google account).

### 5.1 Ollama — Local LLM Runtime

[Ollama](https://ollama.com) runs open-source LLMs locally with native Apple Silicon (Metal) acceleration. It exposes an OpenAI-compatible API on `localhost:11434`, making it a drop-in backend for any tool that speaks the OpenAI API format.

```bash
brew install ollama
```

After install, pull a starter model for coding assistance:

```bash
# Start Ollama service and wait for it to be ready
ollama serve &>/dev/null &
OLLAMA_PID=$!
for i in {1..10}; do
  curl -sf http://localhost:11434/api/tags &>/dev/null && break
  sleep 1
done

# Pull a coding model — Qwen 2.5 Coder 7B is a good balance of quality/speed on 16GB+ RAM
ollama pull qwen2.5-coder:7b

# Stop the background server (launchd or Docker will manage it going forward)
kill $OLLAMA_PID 2>/dev/null || true
```

> 💡 Model sizes: 7B models need ~8GB RAM, 14B models need ~16GB, 70B models need ~48GB. Choose based on your Mac's unified memory.

### 5.2 LM Studio — Local LLM GUI

[LM Studio](https://lmstudio.ai) provides a desktop GUI for browsing, downloading, and running models from Hugging Face. It uses MLX for optimized Apple Silicon inference and can also expose a local OpenAI-compatible server.

```bash
brew install --cask lm-studio
```

LM Studio complements Ollama — use LM Studio for model discovery and experimentation, Ollama for headless/CLI/API workflows.

### 5.3 Open WebUI — Chat Interface for Local Models

[Open WebUI](https://github.com/open-webui/open-webui) is a self-hosted ChatGPT-style web interface that connects to Ollama. Useful for a polished chat experience, RAG experimentation, and sharing local models with others on your network. Requires Docker (Phase 4.4).

```bash
# Wait for Docker daemon to be ready (Docker Desktop may still be starting)
for i in {1..30}; do
  docker info &>/dev/null && break
  echo "Waiting for Docker daemon..." && sleep 2
done

# Idempotent — skip if container already exists
if ! docker ps -a --format '{{.Names}}' | grep -q '^open-webui$'; then
  docker run -d -p 3000:8080 \
    --add-host=host.docker.internal:host-gateway \
    -v open-webui:/app/backend/data \
    --name open-webui \
    --restart always \
    ghcr.io/open-webui/open-webui:main
else
  # Ensure existing container is running
  docker start open-webui 2>/dev/null || true
fi
```

Access at `http://localhost:3000`. It auto-discovers models from Ollama running on the host.

### 5.4 Gemini CLI — Agentic Terminal Assistant (Free Tier)

[Gemini CLI](https://github.com/google-gemini/gemini-cli) is Google's open-source terminal agent powered by Gemini 2.5 Pro with a 1M token context window. It can read your codebase, make multi-file edits, and run commands. Free tier available with a Google account.

```bash
npm install -g @google/gemini-cli
```

On first run, authenticate with your Google account:

```bash
gemini
```

### 5.5 VS Code Extensions for AI Development

Cline and Continue.dev are installed in Phase 4.2. Configuration notes:

**Continue.dev** — Point it at your local Ollama instance for free, private autocomplete and chat. After installing the extension, open Continue settings and select "Local" setup → it auto-detects Ollama models. Recommended config:
- Chat model: `qwen2.5-coder:7b` (or larger if RAM allows)
- Autocomplete model: `qwen2.5-coder:1.5b` (fast, lightweight)

**Cline** — For agentic workflows (multi-file edits, terminal commands). Can also be pointed at Ollama for free usage: open Cline settings → API Provider → select "Ollama" → choose your model.

### 5.6 Recommended Libraries (project-level)

These are not installed globally but are the standard libraries for building LLM-powered apps in the JS/TS ecosystem:

| Library | Purpose | Install |
|---------|---------|---------|
| `ai` (Vercel AI SDK) | Provider-agnostic TypeScript toolkit — streaming, tool calling, agents, React hooks | `npm install ai @ai-sdk/openai` |
| `ollama` | Official JS client for local Ollama API | `npm install ollama` |
| `langchain` | Chains, RAG, agents, vector stores | `npm install langchain` |

For Python AI projects (using mise-managed Python):

| Library | Purpose | Install |
|---------|---------|---------|
| `huggingface-hub` | Download/manage models from Hugging Face | `pip install huggingface-hub` |

---

## Phase 6: React Native Cross-Platform Environment

> ⚠️ This phase uses `npm install -g` which requires Node to be available. Phase 4.5 activates mise and installs Node. If running phases independently, ensure `eval "$(mise activate zsh)"` has been run first.

### 6.1 Core Tools

Per the [React Native docs](https://reactnative.dev/docs/set-up-your-environment), the required dependencies for macOS targeting both Android and iOS are Node, Watchman, JDK, Android Studio, Xcode, and CocoaPods. As of React Native 0.83 / Expo SDK 55 (Jan 2026), the New Architecture (JSI, Fabric, TurboModules) is **mandatory** and cannot be disabled (frozen since RN 0.82, June 2025).

```bash
brew install watchman
brew install cocoapods
npm install -g eas-cli
```

Note: `react-native-cli` is deprecated. Use `npx react-native` instead, which uses `@react-native-community/cli` automatically. For new projects, the React Native team recommends using [Expo](https://expo.dev) as the framework:

```bash
npx create-expo-app@latest
```

### 6.2 Android SDK & Emulators

Android Studio installs the SDK by default to `~/Library/Android/sdk`. After first launch completes the setup wizard, install SDK components via command line:

**SDK Platforms tab:**
- Android 16 (Baklava) — `Android SDK Platform 36`
- For Apple Silicon: `Google APIs ARM 64 v8a System Image`
- For Intel: `Intel x86 Atom_64 System Image`

**SDK Tools tab:**
- Android SDK Build-Tools `36.0.0`
- Android SDK Command-line Tools (latest)

```bash
# Ensure ANDROID_HOME is set for this session (Android Studio must have been launched once)
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator

# Accept licenses
yes | sdkmanager --licenses

# Install required SDK components
sdkmanager "platform-tools" \
           "platforms;android-36" \
           "build-tools;36.0.0" \
           "system-images;android-36;google_apis;arm64-v8a" \
           "emulator" \
           "cmdline-tools;latest"

# Create a default AVD using the Android 16 image
avdmanager create avd -n "Pixel_8_API_36" \
  -k "system-images;android-36;google_apis;arm64-v8a" \
  -d "pixel_8"
```

Verify the setup:

```bash
echo $ANDROID_HOME          # Should show ~/Library/Android/sdk
adb --version               # Should resolve from platform-tools
emulator -list-avds         # Should show Pixel_8_API_36
```

### 6.3 iOS Simulator

Simulators ship with Xcode. Download the latest iOS runtime:

```bash
xcodebuild -downloadPlatform iOS
xcrun simctl list devices
```

### 6.4 Debugging

Flipper has been archived (2024) and removed from React Native. The official replacement is **React Native DevTools**, which is built into React Native 0.73+ and requires no separate install. Launch it by pressing `j` in the Metro terminal, or via the in-app dev menu.

For network inspection, use the built-in Network panel in React Native DevTools or [Reactotron](https://github.com/infinitered/reactotron):

```bash
brew install --cask reactotron
```

---

## Phase 7: Cloud CLI Tools

```bash
# AWS CLI v2
brew install awscli

# Cloudflare Wrangler (Workers, Pages, R2, D1, KV)
npm install -g wrangler
```

---

## Phase 8: Browsers

```bash
brew install --cask google-chrome
brew install --cask firefox
```

---

## Phase 9: Productivity & Communication Apps

```bash
# Office & Productivity
brew install --cask microsoft-office
brew install --cask notion
brew install --cask obsidian
brew install --cask zoom

# Communication
brew install --cask telegram
brew install --cask whatsapp
brew install --cask discord

# Cloud Storage
brew install --cask google-drive

# Dev Productivity
brew install --cask postman
brew install --cask raycast
brew install --cask rectangle
brew install --cask 1password

# Media
brew install --cask spotify
brew install --cask vlc
brew install --cask iina

# Utilities
brew install --cask appcleaner
brew install --cask the-unarchiver
brew install --cask keka
brew install --cask alt-tab
brew install --cask stats
brew install --cask keepingyouawake

# Security
# Moonlock (MacPaw) — not available via Homebrew, download DMG and open installer
if [[ ! -d "/Applications/Moonlock.app" ]]; then
  curl -L -o /tmp/Moonlock.dmg "https://macpaw.com/download/moonlock" && {
    MOONLOCK_VOL=$(hdiutil attach /tmp/Moonlock.dmg -nobrowse -quiet 2>/dev/null | grep "/Volumes/" | awk -F'\t' '{print $NF}')
    if [[ -n "$MOONLOCK_VOL" ]]; then
      cp -R "$MOONLOCK_VOL"/*.app /Applications/ 2>/dev/null || true
      hdiutil detach "$MOONLOCK_VOL" -quiet 2>/dev/null || true
    fi
    rm -f /tmp/Moonlock.dmg
    echo "⚠️  Moonlock installed — open it to complete setup (permissions, system extension, license activation)"
  } || echo "⚠️  Moonlock download failed — install manually from https://macpaw.com/moonlock"
else
  echo "✅ Moonlock already installed"
fi
```

---

## Phase 10: Pending / Blocked

| Item | Status | Action Needed |
|------|--------|---------------|
| Google Antigravity | ❓ Unknown product | Clarify what this refers to |

---

## Phase 11: Validation

The setup script runs a final validation to confirm all tools are installed:

```bash
echo "=== Validation ==="

# Foundation
command -v git    && git --version          || echo "❌ git missing"
command -v brew   && brew --version         || echo "❌ brew missing"
command -v gpg    && gpg --version | head -1 || echo "❌ gpg missing"

# SSH
[[ -f ~/.ssh/id_ed25519 ]]     && echo "✅ SSH key exists"       || echo "❌ SSH key missing"
[[ -f ~/.ssh/config ]]         && echo "✅ SSH config exists"     || echo "❌ SSH config missing"

# Shell
[[ -d ~/.oh-my-zsh ]] && echo "✅ Oh My Zsh" || echo "❌ Oh My Zsh missing"
command -v starship && echo "✅ Starship" || echo "❌ Starship missing"

# Languages (via mise)
command -v mise   && mise --version         || echo "❌ mise missing"
command -v node   && node --version         || echo "❌ node missing"
command -v python && python --version       || echo "❌ python missing"
command -v java   && java -version 2>&1 | head -1 || echo "❌ java missing"

# Environment variables
[[ -n "$JAVA_HOME" ]]    && echo "✅ JAVA_HOME=$JAVA_HOME"       || echo "❌ JAVA_HOME not set"
[[ -n "$ANDROID_HOME" ]] && echo "✅ ANDROID_HOME=$ANDROID_HOME" || echo "❌ ANDROID_HOME not set"

# React Native toolchain
command -v watchman  && watchman --version   || echo "❌ watchman missing"
command -v pod       && pod --version        || echo "❌ cocoapods missing"
command -v adb       && adb --version        || echo "❌ adb missing"
emulator -list-avds 2>/dev/null              || echo "❌ no AVDs found"
xcrun simctl list devices 2>/dev/null | head -5 || echo "❌ iOS simulator issue"

# Cloud CLIs
command -v aws      && aws --version         || echo "❌ aws cli missing"
command -v wrangler && wrangler --version     || echo "❌ wrangler missing"

# AI & LLM tools
command -v ollama  && ollama --version        || echo "❌ ollama missing"
command -v gemini  && echo "✅ Gemini CLI"    || echo "❌ gemini cli missing"
docker ps --filter "name=open-webui" --format '{{.Names}}' | grep -q open-webui \
  && echo "✅ Open WebUI (running)" || echo "⚠️  Open WebUI container not running"

# CLI utilities
for cmd in jq tree gh eza zoxide bat htop wget tldr; do
  command -v $cmd && echo "✅ $cmd" || echo "❌ $cmd missing"
done

# Apps (check if .app exists)
for app in "Google Chrome" "Firefox" "Visual Studio Code" "Cursor" "Zed" "Android Studio" \
           "iTerm" "Ghostty" "Docker" "LM Studio" "Moonlock" "Microsoft Word" "Telegram" "WhatsApp" "Discord" \
           "Postman" "Raycast" "Rectangle" "1Password" "Notion" "Reactotron" \
           "Spotify" "VLC" "IINA" "AppCleaner" "The Unarchiver" "Keka" \
           "AltTab" "Stats" "KeepingYouAwake" "Obsidian" "zoom.us"; do
  [[ -d "/Applications/${app}.app" ]] && echo "✅ $app" || echo "❌ $app not found"
done

echo "=== Validation Complete ==="
```

---

## Execution Strategy

1. **Single `setup.sh` script** — runs all phases sequentially
2. **Idempotent** — safe to re-run (Homebrew skips already-installed packages, git clone guarded with `[[ -d ... ]] ||`)
3. **Logging** — all output teed to `~/mac-setup.log` for troubleshooting
4. **Validation step** — Phase 11 verifies each tool and prints a summary report

### Error Handling

```bash
set -euo pipefail
```

- **Critical failures** (Homebrew, Xcode, mise) — abort the script immediately
- **Non-critical failures** (individual apps, extensions) — log the error and continue
- Each phase wrapped in a function with a trap to report which phase failed:

```bash
run_phase() {
  local phase_name="$1"
  shift
  echo "▶ Starting: $phase_name"
  # Temporarily disable set -e so failures don't abort the script
  set +e
  "$@"
  local exit_code=$?
  set -e
  if [[ $exit_code -eq 0 ]]; then
    echo "✅ Completed: $phase_name"
  else
    echo "❌ Failed: $phase_name (continuing...)" >&2
  fi
}
```

Critical phases use direct execution (will abort on failure under `set -e`). Non-critical phases use `run_phase` wrapper which temporarily disables `set -e`.

---

## Brewfile (Reference)

A `Brewfile` is generated alongside the script for documentation and as an alternative install method via `brew bundle`:

```ruby
# Brewfile — generated by mac-setup spec
# Install all: brew bundle --file=Brewfile

# CLI tools
brew "git"
brew "gh"
brew "jq"
brew "tree"
brew "fzf"
brew "htop"
brew "wget"
brew "tldr"
brew "eza"
brew "zoxide"
brew "bat"
brew "gnupg"
brew "pinentry-mac"
brew "mas"
brew "mise"
brew "watchman"
brew "cocoapods"
brew "awscli"

# Shell prompt
brew "starship"

# Fonts
cask "font-meslo-lg-nerd-font"

# Development
cask "visual-studio-code"
cask "cursor"
cask "zed"
cask "android-studio"
cask "iterm2"
cask "ghostty"
cask "docker"
cask "reactotron"
cask "postman"

# AI & LLM Development
brew "ollama"
cask "lm-studio"

# Browsers
cask "google-chrome"
cask "firefox"

# Productivity
cask "microsoft-office"
cask "notion"
cask "obsidian"
cask "zoom"
cask "raycast"
cask "rectangle"
cask "1password"

# Communication
cask "telegram"
cask "whatsapp"
cask "discord"

# Cloud Storage
cask "google-drive"

# Media
cask "spotify"
cask "vlc"
cask "iina"

# Utilities
cask "appcleaner"
cask "the-unarchiver"
cask "keka"
cask "alt-tab"
cask "stats"
cask "keepingyouawake"

# Mac App Store
mas "Xcode", id: 497799835

# Not in Homebrew (installed via DMG in setup.sh)
# Moonlock (MacPaw) — https://macpaw.com/download/moonlock
```

---

## Post-Setup Manual Steps

These cannot be fully automated:

- Optionally customize Starship prompt by editing `~/.config/starship.toml`
- Configure git identity: `git config --global user.name` / `user.email`
- Authenticate GitHub CLI: `gh auth login`
- Add SSH public key (`~/.ssh/id_ed25519.pub`) to GitHub / GitLab
- Generate GPG key and configure git signing:
  ```bash
  gpg --full-generate-key
  # Select: RSA and RSA, 4096 bits, no expiration, your name/email
  GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format=long | grep sec | awk '{print $2}' | cut -d'/' -f2)
  git config --global user.signingkey "$GPG_KEY_ID"
  git config --global commit.gpgsign true
  git config --global gpg.program $(which gpg)
  gpg --armor --export "$GPG_KEY_ID"  # Add this output to GitHub/GitLab
  ```
- Sign into Apple ID in Xcode
- Sign into Chrome / Firefox with accounts
- Sign into Microsoft Office
- Launch Android Studio and complete the first-run setup wizard
- Sign into messaging apps (Telegram, WhatsApp, Discord)
- Authorize Google Drive
- Sign into 1Password
- Launch Docker Desktop and complete onboarding
- Sign into Spotify
- Sign into Zoom
- Install browser extensions: uBlock Origin, 1Password extension
- **AI/LLM setup:**
  - Pull additional Ollama models if needed (`ollama pull <model>`)
  - Open LM Studio and download models for experimentation
  - Configure Continue.dev in VS Code: open Continue sidebar → select "Local" → verify Ollama models are detected
  - Configure Cline in VS Code: Settings → API Provider → "Ollama" → select model
  - Authenticate Gemini CLI: run `gemini` and sign in with Google account
  - Create your Open WebUI account at `http://localhost:3000`
- **Moonlock setup:**
  - Launch Moonlock and complete the guided setup wizard
  - Grant required permissions (Full Disk Access, System Extension, Network Extension)
  - Activate license
  - Enable real-time threat monitoring
