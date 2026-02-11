#!/usr/bin/env bash
# =============================================================================
# Mac Developer Environment Setup Script
# Automates provisioning for React Native + AI/LLM development
# Idempotent — safe to re-run
# =============================================================================
set -euo pipefail

LOG_FILE="$HOME/mac-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Mac Setup started at $(date) ==="

# ---------------------------------------------------------------------------
# Load user config
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/setup.conf"
if [[ -f "$CONF_FILE" ]]; then
  echo "📄 Loading config from $CONF_FILE"
  source "$CONF_FILE"
else
  echo "ℹ️  No setup.conf found — using defaults (manual steps will remain)"
fi
GIT_USER_NAME="${GIT_USER_NAME:-}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
ENABLE_GPG_SIGNING="${ENABLE_GPG_SIGNING:-false}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5-coder:7b}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
run_phase() {
  local phase_name="$1"; shift
  echo ""
  echo "▶ Starting: $phase_name"
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

# =============================================================================
# Phase 1: Foundation
# =============================================================================

phase_1_rosetta() {
  softwareupdate --install-rosetta --agree-to-license 2>/dev/null || true
}

phase_1_homebrew() {
  if ! command -v brew &>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  eval "$(/opt/homebrew/bin/brew shellenv)"
}

phase_1_zsh() {
  chsh -s /bin/zsh 2>/dev/null || true
}

phase_1_git() {
  brew install git
  git config --global init.defaultBranch main
  git config --global pull.rebase true
  git config --global core.editor "code --wait"
  if [[ -n "$GIT_USER_NAME" ]]; then
    git config --global user.name "$GIT_USER_NAME"
    echo "✅ Git user.name set to: $GIT_USER_NAME"
  fi
  if [[ -n "$GIT_USER_EMAIL" ]]; then
    git config --global user.email "$GIT_USER_EMAIL"
    echo "✅ Git user.email set to: $GIT_USER_EMAIL"
  fi
}

phase_1_ssh() {
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh

  if [[ ! -f ~/.ssh/id_ed25519 ]]; then
    ssh-keygen -t ed25519 -C "${GIT_USER_EMAIL:-mac-setup}" -f ~/.ssh/id_ed25519 -N ""
    chmod 600 ~/.ssh/id_ed25519
    chmod 644 ~/.ssh/id_ed25519.pub
  else
    echo "✅ SSH key already exists, skipping generation"
  fi

  if [[ ! -f ~/.ssh/config ]]; then
    cat > ~/.ssh/config << 'EOF'
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
EOF
    chmod 600 ~/.ssh/config
  else
    echo "✅ SSH config already exists, skipping"
  fi

  eval "$(ssh-agent -s)"
  ssh-add --apple-use-keychain ~/.ssh/id_ed25519 2>/dev/null || \
    echo "⚠️  Could not add SSH key to keychain — add manually: ssh-add --apple-use-keychain ~/.ssh/id_ed25519"
}

phase_1_gpg() {
  brew install gnupg pinentry-mac
  mkdir -p ~/.gnupg
  chmod 700 ~/.gnupg
  grep -q "pinentry-program" ~/.gnupg/gpg-agent.conf 2>/dev/null || \
    echo "pinentry-program $(brew --prefix)/bin/pinentry-mac" >> ~/.gnupg/gpg-agent.conf

  # Auto-generate GPG key and enable signing if configured
  if [[ "$ENABLE_GPG_SIGNING" == "true" && -n "$GIT_USER_NAME" && -n "$GIT_USER_EMAIL" ]]; then
    if ! gpg --list-secret-keys "$GIT_USER_EMAIL" &>/dev/null; then
      gpg --batch --gen-key <<GPGEOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $GIT_USER_NAME
Name-Email: $GIT_USER_EMAIL
Expire-Date: 0
GPGEOF
      echo "✅ GPG key generated for $GIT_USER_EMAIL"
    else
      echo "✅ GPG key already exists for $GIT_USER_EMAIL"
    fi
    GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format=long "$GIT_USER_EMAIL" 2>/dev/null | grep sec | head -1 | awk '{print $2}' | cut -d'/' -f2)
    if [[ -n "$GPG_KEY_ID" ]]; then
      git config --global user.signingkey "$GPG_KEY_ID"
      git config --global commit.gpgsign true
      git config --global gpg.program "$(which gpg)"
      echo "✅ Git commit signing enabled with key $GPG_KEY_ID"
      echo ""
      echo "📋 Add this GPG public key to GitHub (https://github.com/settings/keys):"
      echo "---"
      gpg --armor --export "$GPG_KEY_ID"
      echo "---"
    fi
  fi
}

phase_1_xcode() {
  xcode-select -p &>/dev/null || xcode-select --install
  brew install mas
  mas list > /dev/null 2>&1 || echo "⚠️  Sign into the App Store before continuing"
  mas install 497799835 || echo "⚠️  Xcode install failed — sign into App Store and re-run"
  sudo xcodebuild -license accept 2>/dev/null || true
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer 2>/dev/null || true
}

phase_1_cli_utils() {
  brew install jq tree gh eza zoxide bat htop wget tldr
  tldr --update 2>/dev/null || true

  # Authenticate GitHub CLI if token provided
  if [[ -n "$GITHUB_TOKEN" ]]; then
    echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null \
      && echo "✅ GitHub CLI authenticated" \
      || echo "⚠️  GitHub CLI auth failed — run 'gh auth login' manually"
  fi
}

phase_1() {
  # Critical — abort on failure
  phase_1_rosetta
  phase_1_homebrew
  phase_1_zsh
  phase_1_git
  phase_1_ssh
  phase_1_gpg
  phase_1_xcode
  phase_1_cli_utils
}

# =============================================================================
# Phase 2: Oh My Zsh + Shell Configuration
# =============================================================================

phase_2() {
  # 2.1 Oh My Zsh
  [[ -d ~/.oh-my-zsh ]] || \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

  # 2.2 Starship
  brew install starship

  # 2.3 Nerd Font
  brew install --cask font-meslo-lg-nerd-font

  # 2.4 Custom Zsh Plugins
  local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  for plugin in zsh-autosuggestions zsh-completions zsh-history-substring-search zsh-syntax-highlighting; do
    [[ -d "$ZSH_CUSTOM/plugins/$plugin" ]] || \
      git clone "https://github.com/zsh-users/$plugin" "$ZSH_CUSTOM/plugins/$plugin"
  done

  # 2.5 fzf
  brew install fzf

  # 2.6 Generate .zshrc
  cat > ~/.zshrc << 'ZSHRC'
# =============================================================================
# .zshrc — generated by setup.sh
# =============================================================================

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""  # Disabled — using Starship

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

# --- Aliases: Git ---
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

# --- Aliases: Utility ---
alias tailf="tail -n 500 -f "
alias up="cd .."
alias ls="eza --icons"
alias ll="eza --icons -la"
alias lt="eza --icons --tree --level=2"
alias cat="bat --paging=never"

# --- zoxide ---
eval "$(zoxide init zsh)"

# --- GPG ---
export GPG_TTY=$(tty)

# --- Homebrew (must come before mise) ---
eval "$(/opt/homebrew/bin/brew shellenv)"

# --- mise ---
command -v mise &>/dev/null && eval "$(mise activate zsh)"

# --- Android SDK ---
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin

# --- AWS CLI completion ---
complete -C '/opt/homebrew/bin/aws_completer' aws

# --- Starship (must be last) ---
eval "$(starship init zsh)"
ZSHRC

  # 2.7 Starship config
  mkdir -p ~/.config
  cp ./dotfiles/starship.toml ~/.config/starship.toml 2>/dev/null || true
}

# =============================================================================
# Phase 3: macOS System Preferences
# =============================================================================

phase_3() {
  # Finder
  defaults write com.apple.finder AppleShowAllFiles -bool true
  defaults write com.apple.finder ShowPathbar -bool true
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true

  # Keyboard
  defaults write NSGlobalDomain KeyRepeat -int 2
  defaults write NSGlobalDomain InitialKeyRepeat -int 15

  # Dock
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.dock autohide-delay -float 0
  defaults write com.apple.dock autohide-time-modifier -float 0.3

  # Trackpad — tap to click
  defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
  defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

  # Screenshots
  mkdir -p ~/Screenshots
  defaults write com.apple.screencapture location -string "$HOME/Screenshots"

  # Disable .DS_Store on network/USB
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

  # Battery percentage
  defaults write com.apple.menuextra.battery ShowPercent -string "YES"

  # Restart affected services
  killall Finder 2>/dev/null || true
  killall Dock 2>/dev/null || true
  killall SystemUIServer 2>/dev/null || true
}

# =============================================================================
# Phase 4: Development Tools
# =============================================================================

phase_4_editors() {
  brew install --cask visual-studio-code
  brew install --cask cursor
  brew install --cask zed
  brew install --cask android-studio
}

phase_4_vscode() {
  export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

  # Configure Nerd Font for VS Code terminal
  local VSCODE_SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
  local VSCODE_SETTINGS="$VSCODE_SETTINGS_DIR/settings.json"
  mkdir -p "$VSCODE_SETTINGS_DIR"
  if [[ -f "$VSCODE_SETTINGS" ]]; then
    jq '. + {"terminal.integrated.fontFamily": "MesloLGS NF"}' "$VSCODE_SETTINGS" > "$VSCODE_SETTINGS.tmp" \
      && mv "$VSCODE_SETTINGS.tmp" "$VSCODE_SETTINGS"
  else
    echo '{"terminal.integrated.fontFamily": "MesloLGS NF"}' > "$VSCODE_SETTINGS"
  fi

  if command -v code &>/dev/null; then
    code --install-extension saoudrizwan.claude-dev
    code --install-extension continue.dev.continue
    code --install-extension dbaeumer.vscode-eslint
    code --install-extension esbenp.prettier-vscode
    code --install-extension msjsdiag.vscode-react-native
  else
    echo "⚠️  VS Code CLI not found — install extensions manually after launching VS Code"
  fi
}

phase_4_terminals() {
  brew install --cask iterm2
  brew install --cask ghostty

  # iTerm2 Nerd Font
  /usr/libexec/PlistBuddy -c "Set ':New Bookmarks:0:Normal Font' MesloLGSNF-Regular 13" \
    ~/Library/Preferences/com.googlecode.iterm2.plist 2>/dev/null || true

  # Ghostty Nerd Font
  mkdir -p ~/.config/ghostty
  grep -q "font-family" ~/.config/ghostty/config 2>/dev/null || \
    echo "font-family = MesloLGS NF" >> ~/.config/ghostty/config
}

phase_4_docker() {
  brew install --cask docker
}

phase_4_mise() {
  brew install mise
  eval "$(mise activate zsh)"

  mise use --global python@latest
  mise use --global node@lts
  mise use --global java@zulu-17

  # mise shell completions
  local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$ZSH_CUSTOM/plugins/mise"
  mise completion zsh > "$ZSH_CUSTOM/plugins/mise/_mise"

  # JAVA_HOME in mise config
  local MISE_CONFIG="$HOME/.config/mise/config.toml"
  if ! grep -q "JAVA_HOME" "$MISE_CONFIG" 2>/dev/null; then
    cat >> "$MISE_CONFIG" << 'EOF'

[env]
JAVA_HOME = "{{env.HOME}}/.local/share/mise/installs/java/zulu-17"
EOF
  fi

  # macOS JAVA_HOME symlink
  sudo mkdir -p /Library/Java/JavaVirtualMachines/zulu-17.jdk
  sudo ln -sf ~/.local/share/mise/installs/java/zulu-17/Contents \
    /Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents
}

phase_4() {
  phase_4_editors
  phase_4_vscode
  phase_4_terminals
  phase_4_docker
  phase_4_mise
}

# =============================================================================
# Phase 5: AI & LLM Development
# =============================================================================

phase_5_ollama() {
  brew install ollama

  if [[ -z "$OLLAMA_MODEL" ]]; then
    echo "ℹ️  OLLAMA_MODEL is empty — skipping model download"
    return
  fi

  # Start Ollama and wait for readiness
  ollama serve &>/dev/null &
  local OLLAMA_PID=$!
  for i in {1..10}; do
    curl -sf http://localhost:11434/api/tags &>/dev/null && break
    sleep 1
  done

  ollama pull "$OLLAMA_MODEL" || echo "⚠️  Ollama model pull failed — pull manually: ollama pull $OLLAMA_MODEL"

  kill $OLLAMA_PID 2>/dev/null || true
}

phase_5_lm_studio() {
  brew install --cask lm-studio
}

phase_5_open_webui() {
  # Wait for Docker daemon
  for i in {1..30}; do
    docker info &>/dev/null && break
    echo "Waiting for Docker daemon..." && sleep 2
  done

  if ! docker ps -a --format '{{.Names}}' | grep -q '^open-webui$'; then
    docker run -d -p 3000:8080 \
      --add-host=host.docker.internal:host-gateway \
      -v open-webui:/app/backend/data \
      --name open-webui \
      --restart always \
      ghcr.io/open-webui/open-webui:main
  else
    docker start open-webui 2>/dev/null || true
  fi
}

phase_5_gemini_cli() {
  npm install -g @google/gemini-cli
}

phase_5() {
  phase_5_ollama
  phase_5_lm_studio
  phase_5_open_webui
  phase_5_gemini_cli
}

# =============================================================================
# Phase 6: React Native Cross-Platform Environment
# =============================================================================

phase_6_core() {
  brew install watchman
  brew install cocoapods
  npm install -g eas-cli
}

phase_6_android_sdk() {
  export ANDROID_HOME=$HOME/Library/Android/sdk
  export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator

  yes | sdkmanager --licenses 2>/dev/null || true

  sdkmanager "platform-tools" \
             "platforms;android-36" \
             "build-tools;36.0.0" \
             "system-images;android-36;google_apis;arm64-v8a" \
             "emulator" \
             "cmdline-tools;latest"

  echo "no" | avdmanager create avd -n "Pixel_8_API_36" \
    -k "system-images;android-36;google_apis;arm64-v8a" \
    -d "pixel_8" 2>/dev/null || echo "⚠️  AVD creation failed — create manually in Android Studio"
}

phase_6_ios() {
  xcodebuild -downloadPlatform iOS 2>/dev/null || true
}

phase_6_debugging() {
  brew install --cask reactotron
}

phase_6() {
  phase_6_core
  phase_6_android_sdk
  phase_6_ios
  phase_6_debugging
}

# =============================================================================
# Phase 7: Cloud CLI Tools
# =============================================================================

phase_7() {
  brew install awscli
  npm install -g wrangler
}

# =============================================================================
# Phase 8: Browsers
# =============================================================================

phase_8() {
  brew install --cask google-chrome
  brew install --cask firefox
}

# =============================================================================
# Phase 9: Productivity & Communication Apps
# =============================================================================

phase_9() {
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

  # Security — Moonlock (not in Homebrew)
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
}

# =============================================================================
# Phase 11: Validation
# =============================================================================

phase_11() {
  echo ""
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

  # Languages
  command -v mise   && mise --version         || echo "❌ mise missing"
  command -v node   && node --version         || echo "❌ node missing"
  command -v python && python --version       || echo "❌ python missing"
  command -v java   && java -version 2>&1 | head -1 || echo "❌ java missing"

  # Environment variables
  [[ -n "${JAVA_HOME:-}" ]]    && echo "✅ JAVA_HOME=$JAVA_HOME"       || echo "❌ JAVA_HOME not set"
  [[ -n "${ANDROID_HOME:-}" ]] && echo "✅ ANDROID_HOME=$ANDROID_HOME" || echo "❌ ANDROID_HOME not set"

  # React Native
  command -v watchman  && watchman --version   || echo "❌ watchman missing"
  command -v pod       && pod --version        || echo "❌ cocoapods missing"
  command -v adb       && adb --version        || echo "❌ adb missing"
  emulator -list-avds 2>/dev/null              || echo "❌ no AVDs found"
  xcrun simctl list devices 2>/dev/null | head -5 || echo "❌ iOS simulator issue"

  # Cloud CLIs
  command -v aws      && aws --version         || echo "❌ aws cli missing"
  command -v wrangler && wrangler --version     || echo "❌ wrangler missing"

  # AI & LLM
  command -v ollama  && ollama --version        || echo "❌ ollama missing"
  command -v gemini  && echo "✅ Gemini CLI"    || echo "❌ gemini cli missing"
  docker ps --filter "name=open-webui" --format '{{.Names}}' 2>/dev/null | grep -q open-webui \
    && echo "✅ Open WebUI (running)" || echo "⚠️  Open WebUI container not running"

  # CLI utilities
  for cmd in jq tree gh eza zoxide bat htop wget tldr; do
    command -v "$cmd" &>/dev/null && echo "✅ $cmd" || echo "❌ $cmd missing"
  done

  # Apps
  for app in "Google Chrome" "Firefox" "Visual Studio Code" "Cursor" "Zed" "Android Studio" \
             "iTerm" "Ghostty" "Docker" "LM Studio" "Moonlock" "Microsoft Word" "Telegram" "WhatsApp" "Discord" \
             "Postman" "Raycast" "Rectangle" "1Password" "Notion" "Reactotron" \
             "Spotify" "VLC" "IINA" "AppCleaner" "The Unarchiver" "Keka" \
             "AltTab" "Stats" "KeepingYouAwake" "Obsidian" "zoom.us"; do
    [[ -d "/Applications/${app}.app" ]] && echo "✅ $app" || echo "❌ $app not found"
  done

  echo "=== Validation Complete ==="
}

# =============================================================================
# Main — Execute all phases
# =============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          Mac Developer Environment Setup                    ║"
echo "║          Log: ~/mac-setup.log                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Phase 1 — Critical (abort on failure)
echo "━━━ Phase 1: Foundation ━━━"
phase_1

# Phases 2-9 — Non-critical (continue on failure)
run_phase "Phase 2: Shell Configuration" phase_2
run_phase "Phase 3: macOS System Preferences" phase_3
run_phase "Phase 4: Development Tools" phase_4
run_phase "Phase 5: AI & LLM Development" phase_5
run_phase "Phase 6: React Native Environment" phase_6
run_phase "Phase 7: Cloud CLI Tools" phase_7
run_phase "Phase 8: Browsers" phase_8
run_phase "Phase 9: Productivity & Communication Apps" phase_9

# Phase 11 — Validation
phase_11

echo ""
echo "=== Setup complete at $(date) ==="
echo "=== Log saved to $LOG_FILE ==="
echo ""
echo "📋 Post-setup manual steps:"
[[ -z "$GIT_USER_NAME" ]] && echo "   • git config --global user.name / user.email"
[[ -z "$GITHUB_TOKEN" ]] && echo "   • gh auth login"
echo "   • Add SSH key to GitHub: cat ~/.ssh/id_ed25519.pub"
[[ "$ENABLE_GPG_SIGNING" != "true" ]] && echo "   • Generate GPG key: gpg --full-generate-key"
echo "   • Launch Android Studio → complete setup wizard"
echo "   • Configure Continue.dev + Cline → Ollama in VS Code"
echo "   • Authenticate Gemini CLI: gemini"
echo "   • Create Open WebUI account: http://localhost:3000"
echo "   • Launch Moonlock → grant permissions → activate license"
echo "   • Sign into apps (Chrome, Office, 1Password, Spotify, etc.)"
