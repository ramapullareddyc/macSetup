#!/usr/bin/env bash
# =============================================================================
# Mac Developer Environment Setup Script
# Automates provisioning for React Native + AI/LLM development
# Idempotent — safe to re-run
# Requires Bash 4+ (associative arrays). Auto-installs via Homebrew if needed.
# =============================================================================

# Bootstrap: ensure Bash 4+ is available, re-exec if running old system Bash
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  # Check if Homebrew Bash exists
  if [[ -x /opt/homebrew/bin/bash ]]; then
    exec /opt/homebrew/bin/bash "$0" "$@"
  elif [[ -x /usr/local/bin/bash ]]; then
    exec /usr/local/bin/bash "$0" "$@"
  else
    echo "⚠️  Bash ${BASH_VERSION} is too old (need 4+). Installing modern Bash via Homebrew..."
    if ! command -v brew &>/dev/null; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
    fi
    brew install bash
    exec "$(brew --prefix)/bin/bash" "$0" "$@"
  fi
fi
set -eo pipefail

LOG_FILE="$HOME/mac-setup.log"

# ---------------------------------------------------------------------------
# Sudo keepalive — ask once BEFORE tee redirect (needs real tty)
# ---------------------------------------------------------------------------
echo "🔐 Admin privileges required. Enter your password once:"
sudo -v || { echo "❌ sudo failed — run with admin privileges"; exit 1; }
(while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 10; done) &>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

# Now redirect stdout/stderr through tee for logging
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

# Default all app toggles to "true" (install everything unless overridden by config)
: "${INSTALL_VSCODE:=true}" "${INSTALL_CURSOR:=true}" "${INSTALL_ZED:=true}" "${INSTALL_ANDROID_STUDIO:=true}"
: "${INSTALL_ITERM2:=true}" "${INSTALL_GHOSTTY:=true}" "${INSTALL_MISE:=true}"
: "${CONTAINER_RUNTIME:=docker}"  # docker | colima | none
: "${INSTALL_OLLAMA:=true}" "${INSTALL_LM_STUDIO:=true}" "${INSTALL_OPEN_WEBUI:=true}" "${INSTALL_GEMINI_CLI:=true}"
: "${INSTALL_WATCHMAN:=true}" "${INSTALL_COCOAPODS:=true}" "${INSTALL_EAS_CLI:=true}"
: "${INSTALL_ANDROID_SDK:=true}" "${INSTALL_IOS_SIMULATOR:=true}" "${INSTALL_REACTOTRON:=true}"
: "${INSTALL_AWSCLI:=true}" "${INSTALL_WRANGLER:=true}"
: "${INSTALL_CHROME:=true}" "${INSTALL_FIREFOX:=true}"
: "${INSTALL_MICROSOFT_OFFICE:=true}" "${INSTALL_NOTION:=true}" "${INSTALL_OBSIDIAN:=true}" "${INSTALL_ZOOM:=true}"
: "${INSTALL_TELEGRAM:=true}" "${INSTALL_WHATSAPP:=true}" "${INSTALL_DISCORD:=true}"
: "${INSTALL_GOOGLE_DRIVE:=true}" "${INSTALL_POSTMAN:=true}" "${INSTALL_RAYCAST:=true}"
: "${INSTALL_RECTANGLE:=true}" "${INSTALL_1PASSWORD:=true}"
: "${INSTALL_SPOTIFY:=true}" "${INSTALL_VLC:=true}" "${INSTALL_IINA:=true}"
: "${INSTALL_APPCLEANER:=true}" "${INSTALL_THE_UNARCHIVER:=true}" "${INSTALL_KEKA:=true}"
: "${INSTALL_ALTTAB:=true}" "${INSTALL_STATS:=true}" "${INSTALL_KEEPINGYOUAWAKE:=true}"
: "${INSTALL_ADGUARD:=true}" "${INSTALL_ADGUARD_VPN:=true}" "${INSTALL_VPN_UNLIMITED:=true}"
: "${INSTALL_KEEPSOLID_SMARTDNS:=true}" "${INSTALL_DPN:=true}" "${INSTALL_MOONLOCK:=true}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
SETUP_START_TIME=$(date +%s)
PASS_COUNT=0
FAIL_COUNT=0

# Determine Homebrew prefix (Apple Silicon vs Intel)
if [[ "$(uname -m)" == "arm64" ]]; then
  BREW_PREFIX="/opt/homebrew"
else
  BREW_PREFIX="/usr/local"
fi

# Wait for network connectivity. Retries automatically, prompts user after timeout.
wait_for_network() {
  local attempt=0 max_auto=5
  while ! curl -sfm 3 https://github.com &>/dev/null; do
    ((attempt++))
    if [[ $attempt -le $max_auto ]]; then
      echo "⏳ No network connection (attempt $attempt/$max_auto) — retrying in 5s..."
      sleep 5
    else
      echo ""
      echo "❌ Network still unavailable after $max_auto attempts."
      read -rp "   Press Enter to retry, or type 'skip' to continue offline: " choice
      [[ "${choice,,}" == "skip" ]] && echo "⚠️  Continuing without network — some installs will fail" && return 1
      attempt=0
    fi
  done
  return 0
}

run_phase() {
  local phase_name="$1"; shift
  echo ""
  echo "▶ Starting: $phase_name"
  # Check network before network-dependent phases
  wait_for_network || true
  set +e
  "$@"
  local exit_code=$?
  set -e
  if [[ $exit_code -eq 0 ]]; then
    echo "✅ Completed: $phase_name"
  else
    echo "❌ Failed: $phase_name (continuing...)" >&2
  fi
  return 0
}

# Run each sub-function independently so one failure doesn't skip the rest
run_sub_phases() {
  for fn in "$@"; do
    set +e
    "$fn"
    local rc=$?
    set -e
    [[ $rc -ne 0 ]] && echo "⚠️  $fn had errors (continuing...)" >&2
  done
  return 0
}

# Install a cask/formula only if its toggle is "true", with retry on failure
install_if() {
  local toggle="$1"; shift
  [[ "$toggle" == "true" ]] || { echo "⏭  Skipping: $*"; return 0; }
  local attempt
  for attempt in 1 2 3; do
    "$@" && return 0
    echo "⚠️  Attempt $attempt failed: $*"
    if [[ $attempt -lt 3 ]]; then
      wait_for_network || return 1
      echo "🔄 Retrying..."
    fi
  done
  echo "❌ Failed after 3 attempts: $*"
  return 1
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
  eval "$($BREW_PREFIX/bin/brew shellenv)"
}

phase_1_zsh() {
  chsh -s /bin/zsh 2>/dev/null || true
}

phase_1_git() {
  command -v git &>/dev/null || brew install git
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
  command -v gpg &>/dev/null || brew install gnupg
  command -v pinentry-mac &>/dev/null || brew install pinentry-mac
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
  # Install Command Line Tools (async dialog — wait for completion)
  if ! xcode-select -p &>/dev/null; then
    xcode-select --install 2>/dev/null || true
    echo "⏳ Waiting for Command Line Tools installation..."
    until xcode-select -p &>/dev/null; do sleep 5; done
  else
    echo "✅ Xcode Command Line Tools already installed"
  fi

  if ! command -v mas &>/dev/null; then
    brew install mas
  fi
  if [[ ! -d "/Applications/Xcode.app" ]]; then
    mas install 497799835 2>/dev/null || echo "⚠️  Xcode install failed — sign into App Store and re-run"
  else
    echo "✅ Xcode already installed"
  fi
  sudo xcodebuild -license accept 2>/dev/null || true
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer 2>/dev/null || true
}

phase_1_cli_utils() {
  local cli_tools=(bash jq tree gh eza zoxide bat htop wget tldr)
  for tool in "${cli_tools[@]}"; do
    command -v "$tool" &>/dev/null && echo "✅ $tool already installed" || brew install "$tool"
  done
  tldr --update 2>/dev/null || true

  # Authenticate GitHub CLI if token provided
  if [[ -n "$GITHUB_TOKEN" ]]; then
    if gh auth status &>/dev/null; then
      echo "✅ GitHub CLI already authenticated"
    else
      echo "$GITHUB_TOKEN" | gh auth login --with-token && echo "✅ GitHub CLI authenticated" || echo "⚠️  GitHub CLI auth failed — run 'gh auth login' manually"
    fi
  fi
}

phase_1() {
  # Homebrew is truly critical — abort if it fails
  phase_1_rosetta
  phase_1_homebrew
  phase_1_zsh
  # Remaining Phase 1 steps run independently
  run_sub_phases phase_1_git phase_1_ssh phase_1_gpg phase_1_xcode phase_1_cli_utils
  return 0  # Always succeed — sub-phase errors are logged but not fatal
}

# =============================================================================
# Phase 2: Oh My Zsh + Shell Configuration
# =============================================================================

phase_2() {
  # 2.1 Oh My Zsh
  [[ -d ~/.oh-my-zsh ]] || \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

  # 2.2 Starship
  command -v starship &>/dev/null && echo "✅ Starship already installed" || brew install starship

  # 2.3 Nerd Font
  brew install --cask font-meslo-lg-nerd-font 2>/dev/null || true

  # 2.4 Custom Zsh Plugins
  local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  for plugin in zsh-autosuggestions zsh-completions zsh-history-substring-search zsh-syntax-highlighting; do
    [[ -d "$ZSH_CUSTOM/plugins/$plugin" ]] && echo "✅ $plugin already installed" || \
      git clone "https://github.com/zsh-users/$plugin" "$ZSH_CUSTOM/plugins/$plugin"
  done

  # 2.5 fzf
  command -v fzf &>/dev/null && echo "✅ fzf already installed" || brew install fzf

  # 2.6 Generate .zshrc
  cat > ~/.zshrc << ZSHRC
# =============================================================================
# .zshrc — generated by setup.sh
# =============================================================================

export ZSH="\$HOME/.oh-my-zsh"
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

source \$ZSH/oh-my-zsh.sh

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
eval "\$(zoxide init zsh)"

# --- GPG ---
export GPG_TTY=\$(tty)

# --- Homebrew (must come before mise) ---
eval "\$($BREW_PREFIX/bin/brew shellenv)"

# --- mise ---
command -v mise &>/dev/null && eval "\$(mise activate zsh)"

# --- Android SDK ---
export ANDROID_HOME=\$HOME/Library/Android/sdk
export PATH=\$PATH:\$ANDROID_HOME/emulator
export PATH=\$PATH:\$ANDROID_HOME/platform-tools
export PATH=\$PATH:\$ANDROID_HOME/cmdline-tools/latest/bin

# --- AWS CLI completion ---
complete -C '$BREW_PREFIX/bin/aws_completer' aws

# --- Starship (must be last) ---
eval "\$(starship init zsh)"
ZSHRC

  # 2.7 Starship config
  mkdir -p ~/.config
  cp "$SCRIPT_DIR/dotfiles/starship.toml" ~/.config/starship.toml 2>/dev/null || true
}

# =============================================================================
# Phase 3: macOS System Preferences
# =============================================================================

phase_3() {
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

  # Spaces — independent spaces per display (disable spans-displays)
  defaults write com.apple.spaces spans-displays -bool false

  # Hot corners — bottom-left: Mission Control, bottom-right: Desktop
  # Values: 0=none, 2=Mission Control, 4=Desktop, 5=Screensaver, 10=Sleep Display
  defaults write com.apple.dock wvous-bl-corner -int 2
  defaults write com.apple.dock wvous-bl-modifier -int 0
  defaults write com.apple.dock wvous-br-corner -int 4
  defaults write com.apple.dock wvous-br-modifier -int 0

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

  # Disable Crash Reporter — no dialog, no submission
  defaults write com.apple.CrashReporter DialogType -string "none"
  sudo defaults write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory AutoSubmit -bool false 2>/dev/null || true

  # Restart affected services
  killall Finder 2>/dev/null || true
  killall Dock 2>/dev/null || true
  killall SystemUIServer 2>/dev/null || true
}

# =============================================================================
# Phase 4: Development Tools
# =============================================================================

phase_4_editors() {
  install_if "$INSTALL_VSCODE" brew install --cask visual-studio-code
  install_if "$INSTALL_CURSOR" brew install --cask cursor
  install_if "$INSTALL_ZED" brew install --cask zed
  install_if "$INSTALL_ANDROID_STUDIO" brew install --cask android-studio
}

phase_4_vscode() {
  [[ "$INSTALL_VSCODE" == "true" ]] || { echo "⏭  Skipping VS Code config (VS Code not selected)"; return 0; }
  export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

  # Configure Nerd Font for VS Code terminal
  local VSCODE_SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
  local VSCODE_SETTINGS="$VSCODE_SETTINGS_DIR/settings.json"
  mkdir -p "$VSCODE_SETTINGS_DIR"
  if [[ -f "$VSCODE_SETTINGS" ]]; then
    jq '. + {"terminal.integrated.fontFamily": "MesloLGS Nerd Font"}' "$VSCODE_SETTINGS" > "$VSCODE_SETTINGS.tmp" \
      && mv "$VSCODE_SETTINGS.tmp" "$VSCODE_SETTINGS"
  else
    echo '{"terminal.integrated.fontFamily": "MesloLGS Nerd Font"}' > "$VSCODE_SETTINGS"
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
  install_if "$INSTALL_ITERM2" brew install --cask iterm2
  install_if "$INSTALL_GHOSTTY" brew install --cask ghostty

  # iTerm2 Nerd Font — need to launch once to create default plist
  if [[ "$INSTALL_ITERM2" == "true" ]]; then
    local ITERM_PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
    if [[ ! -f "$ITERM_PLIST" ]]; then
      open -a iTerm 2>/dev/null || true
      sleep 3
      osascript -e 'tell application "iTerm" to quit' 2>/dev/null || true
      sleep 1
    fi
    /usr/libexec/PlistBuddy \
      -c "Set ':New Bookmarks:0:Normal Font' 'MesloLGSNerdFont-Regular 13'" \
      "$ITERM_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy \
      -c "Add ':New Bookmarks:0:Normal Font' string 'MesloLGSNerdFont-Regular 13'" \
      "$ITERM_PLIST" 2>/dev/null || true
  fi

  # Ghostty Nerd Font
  if [[ "$INSTALL_GHOSTTY" == "true" ]]; then
    mkdir -p ~/.config/ghostty
    grep -q "font-family" ~/.config/ghostty/config 2>/dev/null || \
      echo "font-family = MesloLGS Nerd Font" >> ~/.config/ghostty/config
  fi
}

phase_4_docker() {
  [[ "$CONTAINER_RUNTIME" == "none" ]] && { echo "⏭  Skipping container runtime (CONTAINER_RUNTIME=none)"; return 0; }
  if [[ "$CONTAINER_RUNTIME" == "colima" ]]; then
    command -v docker &>/dev/null && echo "✅ Docker CLI already installed" || brew install docker
    command -v colima &>/dev/null && echo "✅ Colima already installed" || brew install colima
    brew install docker-compose docker-credential-helper 2>/dev/null || true
    colima status &>/dev/null || colima start --cpu 4 --memory 4 --disk 60
  else
    brew install --cask docker
    open -a Docker 2>/dev/null || true
  fi
}

phase_4_mise() {
  [[ "$INSTALL_MISE" == "true" ]] || { echo "⏭  Skipping mise + runtimes"; return 0; }
  command -v mise &>/dev/null && echo "✅ mise already installed" || brew install mise
  # Add mise shims to PATH for this session (don't eval activate — it outputs
  # informational text that breaks under eval, e.g. fish shell messages)
  export PATH="$HOME/.local/share/mise/shims:$PATH"

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
  run_sub_phases phase_4_editors phase_4_vscode phase_4_terminals phase_4_docker phase_4_mise
}

# =============================================================================
# Phase 5: AI & LLM Development
# =============================================================================

phase_5_ollama() {
  [[ "$INSTALL_OLLAMA" == "true" ]] || { echo "⏭  Skipping Ollama"; return 0; }
  command -v ollama &>/dev/null && echo "✅ Ollama already installed" || brew install ollama

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
  install_if "$INSTALL_LM_STUDIO" brew install --cask lm-studio
}

phase_5_open_webui() {
  [[ "$INSTALL_OPEN_WEBUI" == "true" ]] || { echo "⏭  Skipping Open WebUI"; return 0; }
  if [[ "$CONTAINER_RUNTIME" == "none" ]]; then
    echo "⚠️  Skipping Open WebUI — requires a container runtime (CONTAINER_RUNTIME=docker|colima)"
    return 0
  fi
  # Wait for Docker daemon
  local docker_ready=false
  for i in {1..30}; do
    if docker info &>/dev/null; then docker_ready=true; break; fi
    echo "Waiting for Docker daemon... ($i/30)" && sleep 2
  done
  if [[ "$docker_ready" != "true" ]]; then
    echo "⚠️  Docker daemon not ready after 60s — skipping Open WebUI. Start your container runtime and run: docker start open-webui"
    return
  fi

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
  [[ "$INSTALL_GEMINI_CLI" == "true" ]] || { echo "⏭  Skipping Gemini CLI"; return 0; }
  npm install -g @google/gemini-cli
}

phase_5() {
  run_sub_phases phase_5_ollama phase_5_lm_studio phase_5_open_webui phase_5_gemini_cli
}

# =============================================================================
# Phase 6: React Native Cross-Platform Environment
# =============================================================================

phase_6_core() {
  if [[ "$INSTALL_WATCHMAN" == "true" ]]; then
    command -v watchman &>/dev/null && echo "✅ watchman already installed" || brew install watchman
  fi
  if [[ "$INSTALL_COCOAPODS" == "true" ]]; then
    command -v pod &>/dev/null && echo "✅ cocoapods already installed" || brew install cocoapods
  fi
  if [[ "$INSTALL_EAS_CLI" == "true" ]]; then
    command -v eas &>/dev/null && echo "✅ eas-cli already installed" || npm install -g eas-cli
  fi
}

phase_6_android_sdk() {
  [[ "$INSTALL_ANDROID_SDK" == "true" ]] || { echo "⏭  Skipping Android SDK"; return 0; }
  if [[ "$INSTALL_ANDROID_STUDIO" != "true" ]]; then
    echo "⚠️  Skipping Android SDK — requires Android Studio (INSTALL_ANDROID_STUDIO=true)"
    return 0
  fi
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
  [[ "$INSTALL_IOS_SIMULATOR" == "true" ]] && xcodebuild -downloadPlatform iOS 2>/dev/null || true
}

phase_6_debugging() {
  install_if "$INSTALL_REACTOTRON" brew install --cask reactotron
}

phase_6() {
  run_sub_phases phase_6_core phase_6_android_sdk phase_6_ios phase_6_debugging
}

# =============================================================================
# Phase 7: Cloud CLI Tools
# =============================================================================

phase_7() {
  if [[ "$INSTALL_AWSCLI" == "true" ]]; then
    command -v aws &>/dev/null && echo "✅ awscli already installed" || brew install awscli
  fi
  if [[ "$INSTALL_WRANGLER" == "true" ]]; then
    command -v wrangler &>/dev/null && echo "✅ wrangler already installed" || npm install -g wrangler
  fi
}

# =============================================================================
# Phase 8: Browsers
# =============================================================================

phase_8() {
  install_if "$INSTALL_CHROME" brew install --cask google-chrome
  install_if "$INSTALL_FIREFOX" brew install --cask firefox
}

# =============================================================================
# Phase 9: Productivity & Communication Apps
# =============================================================================

phase_9() {
  # Office & Productivity
  install_if "$INSTALL_MICROSOFT_OFFICE" brew install --cask microsoft-office
  install_if "$INSTALL_NOTION" brew install --cask notion
  install_if "$INSTALL_OBSIDIAN" brew install --cask obsidian
  install_if "$INSTALL_ZOOM" brew install --cask zoom

  # Communication
  install_if "$INSTALL_TELEGRAM" brew install --cask telegram
  install_if "$INSTALL_WHATSAPP" brew install --cask whatsapp
  install_if "$INSTALL_DISCORD" brew install --cask discord

  # Cloud Storage
  install_if "$INSTALL_GOOGLE_DRIVE" brew install --cask google-drive

  # Dev Productivity
  install_if "$INSTALL_POSTMAN" brew install --cask postman
  install_if "$INSTALL_RAYCAST" brew install --cask raycast
  install_if "$INSTALL_RECTANGLE" brew install --cask rectangle
  install_if "$INSTALL_1PASSWORD" brew install --cask 1password

  # Media
  install_if "$INSTALL_SPOTIFY" brew install --cask spotify
  install_if "$INSTALL_VLC" brew install --cask vlc
  install_if "$INSTALL_IINA" brew install --cask iina

  # Utilities
  install_if "$INSTALL_APPCLEANER" brew install --cask appcleaner
  install_if "$INSTALL_THE_UNARCHIVER" brew install --cask the-unarchiver
  install_if "$INSTALL_KEKA" brew install --cask keka
  install_if "$INSTALL_ALTTAB" brew install --cask alt-tab
  install_if "$INSTALL_STATS" brew install --cask stats
  install_if "$INSTALL_KEEPINGYOUAWAKE" brew install --cask keepingyouawake

  # Security
  install_if "$INSTALL_ADGUARD" brew install --cask adguard
  install_if "$INSTALL_ADGUARD_VPN" brew install --cask adguard-vpn
  [[ "$INSTALL_VPN_UNLIMITED" == "true" ]] && { mas install 694633015 || echo "⚠️  VPN Unlimited install failed"; } || echo "⏭  Skipping VPN Unlimited"
  [[ "$INSTALL_KEEPSOLID_SMARTDNS" == "true" ]] && { mas install 1475622766 || echo "⚠️  KeepSolid SmartDNS install failed"; } || echo "⏭  Skipping KeepSolid SmartDNS"

  # Security — Deeper Network DPN (not in Homebrew, ARM only)
  if [[ "$INSTALL_DPN" == "true" ]]; then
    if [[ ! -d "/Applications/DPN.app" ]]; then
      # ⚠️ Version-pinned URL — update when new releases are available
      curl -L -o /tmp/DPN.dmg "https://downloads.deeper.network/DPN/test/DPN-2.0.0.251202-macos-arm-64.dmg" && {
        DPN_VOL=$(hdiutil attach /tmp/DPN.dmg -nobrowse -quiet 2>/dev/null | grep "/Volumes/" | awk -F'\t' '{print $NF}')
        if [[ -n "$DPN_VOL" ]]; then
          cp -R "$DPN_VOL"/*.app /Applications/ 2>/dev/null || true
          hdiutil detach "$DPN_VOL" -quiet 2>/dev/null || true
        fi
        rm -f /tmp/DPN.dmg
        echo "✅ DPN installed"
      } || echo "⚠️  DPN download failed — install manually from https://deeper.network"
    else
      echo "✅ DPN already installed"
    fi
  else
    echo "⏭  Skipping DPN"
  fi

  # Security — Moonlock (not in Homebrew)
  if [[ "$INSTALL_MOONLOCK" == "true" ]]; then
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
  else
    echo "⏭  Skipping Moonlock"
  fi
}

# =============================================================================
# Phase 11: Validation
# =============================================================================

phase_11() {
  echo ""
  echo "=== Validation ==="
  PASS_COUNT=0
  FAIL_COUNT=0

  check_pass() { echo "✅ $1"; ((PASS_COUNT++)); }
  check_fail() { echo "❌ $1"; ((FAIL_COUNT++)); }
  check_warn() { echo "⚠️  $1"; ((FAIL_COUNT++)); }

  # Foundation
  command -v git    &>/dev/null && check_pass "git $(git --version 2>&1 | head -1)"          || check_fail "git missing"
  command -v brew   &>/dev/null && check_pass "brew $(brew --version 2>&1 | head -1)"        || check_fail "brew missing"
  command -v gpg    &>/dev/null && check_pass "gpg $(gpg --version 2>&1 | head -1)"          || check_fail "gpg missing"

  # SSH
  [[ -f ~/.ssh/id_ed25519 ]]     && check_pass "SSH key exists"       || check_fail "SSH key missing"
  [[ -f ~/.ssh/config ]]         && check_pass "SSH config exists"    || check_fail "SSH config missing"

  # Shell
  [[ -d ~/.oh-my-zsh ]] && check_pass "Oh My Zsh" || check_fail "Oh My Zsh missing"
  command -v starship &>/dev/null && check_pass "Starship" || check_fail "Starship missing"

  # Languages
  command -v mise   &>/dev/null && check_pass "mise $(mise --version 2>&1)"         || check_fail "mise missing"
  command -v node   &>/dev/null && check_pass "node $(node --version 2>&1)"         || check_fail "node missing"
  command -v python &>/dev/null && check_pass "python $(python --version 2>&1)"     || check_fail "python missing"
  command -v java   &>/dev/null && check_pass "java $(java -version 2>&1 | head -1)" || check_fail "java missing"

  # Environment variables
  [[ -n "${JAVA_HOME:-}" ]]    && check_pass "JAVA_HOME=$JAVA_HOME"       || check_fail "JAVA_HOME not set"
  [[ -n "${ANDROID_HOME:-}" ]] && check_pass "ANDROID_HOME=$ANDROID_HOME" || check_fail "ANDROID_HOME not set"

  # React Native
  command -v watchman  &>/dev/null && check_pass "watchman"   || check_fail "watchman missing"
  command -v pod       &>/dev/null && check_pass "cocoapods"  || check_fail "cocoapods missing"
  command -v adb       &>/dev/null && check_pass "adb"        || check_fail "adb missing"
  emulator -list-avds 2>/dev/null | grep -q . && check_pass "AVD found" || check_warn "no AVDs found"
  xcrun simctl list devices 2>/dev/null | grep -q . && check_pass "iOS simulator" || check_warn "iOS simulator issue"

  # Cloud CLIs
  command -v aws      &>/dev/null && check_pass "aws cli"    || check_fail "aws cli missing"
  command -v wrangler &>/dev/null && check_pass "wrangler"   || check_fail "wrangler missing"

  # AI & LLM
  command -v ollama  &>/dev/null && check_pass "ollama"      || check_fail "ollama missing"
  command -v gemini  &>/dev/null && check_pass "Gemini CLI"  || check_fail "gemini cli missing"

  # Container runtime
  if [[ "$CONTAINER_RUNTIME" == "colima" ]]; then
    command -v colima &>/dev/null && check_pass "colima" || check_fail "colima missing"
    command -v docker &>/dev/null && check_pass "docker cli" || check_fail "docker cli missing"
  elif [[ "$CONTAINER_RUNTIME" == "docker" ]]; then
    [[ -d "/Applications/Docker.app" ]] && check_pass "Docker Desktop" || check_fail "Docker Desktop not found"
  fi

  docker ps --filter "name=open-webui" --format '{{.Names}}' 2>/dev/null | grep -q open-webui \
    && check_pass "Open WebUI (running)" || check_warn "Open WebUI container not running"

  # CLI utilities
  for cmd in jq tree gh eza zoxide bat htop wget tldr; do
    command -v "$cmd" &>/dev/null && check_pass "$cmd" || check_fail "$cmd missing"
  done

  # Apps
  for app in "Google Chrome" "Firefox" "Visual Studio Code" "Cursor" "Zed" "Android Studio" \
             "iTerm" "Ghostty" "LM Studio" "Moonlock" "DPN" "AdGuard" "AdGuard VPN" \
             "VPN Unlimited" "KeepSolid SmartDNS" "Microsoft Word" "Telegram" "WhatsApp" "Discord" \
             "Postman" "Raycast" "Rectangle" "1Password" "Notion" "Reactotron" \
             "Spotify" "VLC" "IINA" "AppCleaner" "The Unarchiver" "Keka" \
             "AltTab" "Stats" "KeepingYouAwake" "Obsidian" "zoom.us"; do
    [[ -d "/Applications/${app}.app" ]] && check_pass "$app" || check_fail "$app not found"
  done

  echo ""
  echo "=== Results: $PASS_COUNT passed, $FAIL_COUNT failed ==="
}

# =============================================================================
# Main — Execute all phases
# =============================================================================

# Phase definitions: number, label, function, required (1=always run)
PHASES=(
  "1|Foundation (Homebrew, Git, SSH, GPG, Xcode, CLI)|phase_1|1"
  "2|Shell Configuration (Oh My Zsh, Starship, plugins, .zshrc)|phase_2|0"
  "3|macOS System Preferences|phase_3|0"
  "4|Development Tools (editors, terminals, Docker, mise)|phase_4|0"
  "5|AI & LLM Development (Ollama, LM Studio, Open WebUI, Gemini)|phase_5|0"
  "6|React Native Environment (SDK, emulators, CocoaPods)|phase_6|0"
  "7|Cloud CLI Tools (AWS, Wrangler)|phase_7|0"
  "8|Browsers (Chrome, Firefox)|phase_8|0"
  "9|Productivity & Communication Apps (30+ apps)|phase_9|0"
)

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          Mac Developer Environment Setup                    ║"
echo "║          Log: ~/mac-setup.log                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Determine which phases to run
declare -A PHASE_SELECTED

if [[ "${1:-}" == "--interactive" || "${1:-}" == "-i" ]]; then
  # Initialize all optional phases as selected
  for entry in "${PHASES[@]}"; do
    IFS='|' read -r num label fn required <<< "$entry"
    PHASE_SELECTED[$num]=1
  done

  show_menu() {
    clear
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          Select phases to install                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    for entry in "${PHASES[@]}"; do
      IFS='|' read -r num label fn required <<< "$entry"
      if [[ "$required" == "1" ]]; then
        echo "  [✅] $num. $label (required)"
      elif [[ "${PHASE_SELECTED[$num]}" == "1" ]]; then
        echo "  [✅] $num. $label"
      else
        echo "  [  ] $num. $label"
      fi
    done
    echo ""
    echo "  Commands:  <number> toggle   |   A select all   |   N unselect all   |   Enter confirm"
    echo ""
  }

  while true; do
    show_menu
    read -rp "→ " input
    input="${input^^}"  # uppercase
    if [[ -z "$input" ]]; then
      break
    elif [[ "$input" == "A" ]]; then
      for entry in "${PHASES[@]}"; do
        IFS='|' read -r num _ _ _ <<< "$entry"
        PHASE_SELECTED[$num]=1
      done
    elif [[ "$input" == "N" ]]; then
      for entry in "${PHASES[@]}"; do
        IFS='|' read -r num _ _ required <<< "$entry"
        [[ "$required" == "1" ]] && continue
        PHASE_SELECTED[$num]=0
      done
    else
      # Toggle individual numbers (space-separated)
      for num in $input; do
        # Skip required phases and invalid numbers
        is_valid=false
        for entry in "${PHASES[@]}"; do
          IFS='|' read -r pnum _ _ required <<< "$entry"
          if [[ "$pnum" == "$num" && "$required" != "1" ]]; then
            is_valid=true
            break
          fi
        done
        if [[ "$is_valid" == "true" ]]; then
          if [[ "${PHASE_SELECTED[$num]}" == "1" ]]; then
            PHASE_SELECTED[$num]=0
          else
            PHASE_SELECTED[$num]=1
          fi
        fi
      done
    fi
  done
else
  # Default: run everything
  for entry in "${PHASES[@]}"; do
    IFS='|' read -r num _ _ _ <<< "$entry"
    PHASE_SELECTED[$num]=1
  done
fi

# Check network before starting
echo "🌐 Checking network connectivity..."
wait_for_network || true

# Execute selected phases
for entry in "${PHASES[@]}"; do
  IFS='|' read -r num label fn required <<< "$entry"
  if [[ "${PHASE_SELECTED[$num]}" == "1" ]]; then
    run_phase "Phase $num: $label" "$fn"
  else
    echo ""
    echo "⏭  Skipping Phase $num: $label"
  fi
done

# Phase 11 — Validation (always runs)
phase_11

echo ""
SETUP_END_TIME=$(date +%s)
ELAPSED=$(( SETUP_END_TIME - SETUP_START_TIME ))
ELAPSED_MIN=$(( ELAPSED / 60 ))
ELAPSED_SEC=$(( ELAPSED % 60 ))
echo "=== Setup complete at $(date) (${ELAPSED_MIN}m ${ELAPSED_SEC}s) ==="
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
