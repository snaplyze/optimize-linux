#!/bin/bash

# Force C locale for script execution to avoid locale-related issues
export LC_ALL=C
export LANG=C

################################################################################
# VPS Optimization Script for Debian 13 (Trixie)
# Purpose: Complete VPS optimization with XanMod kernel support
# Features: Auto RAM detection, XanMod kernel, user creation, SSH hardening
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="/var/log/vps_optimization.log"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

section() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Wait for dpkg/apt lock to be released
wait_for_dpkg_lock() {
    local max_wait=300  # 5 minutes maximum wait
    local wait_time=0
    local check_interval=2

    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do

        if [ $wait_time -ge $max_wait ]; then
            error "Timeout waiting for dpkg lock after ${max_wait}s"
            return 1
        fi

        if [ $wait_time -eq 0 ]; then
            info "Waiting for other package managers to finish..."
        fi

        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done

    # Additional small delay to ensure lock is fully released
    [ $wait_time -gt 0 ] && sleep 1
    return 0
}

# Check if package is available in repositories
package_available() {
    LC_ALL=C apt-cache policy "$1" 2>/dev/null | grep -q "Candidate:" && \
    ! LC_ALL=C apt-cache policy "$1" 2>/dev/null | grep -q "Candidate: (none)"
}

# Safe package installation with availability check
safe_install() {
    packages=("$@")
    available_packages=()
    unavailable_packages=()

    # Wait for any running package managers to finish
    wait_for_dpkg_lock || return 1

    # Update package list before checking availability
    apt-get update >/dev/null 2>&1 || warn "Failed to update package list"
    
    for pkg in "${packages[@]}"; do
        if package_available "$pkg"; then
            available_packages+=("$pkg")
        else
            unavailable_packages+=("$pkg")
        fi
    done
    
    if [ ${#available_packages[@]} -gt 0 ]; then
        log "Installing available packages: ${available_packages[*]}"
        apt-get install -y "${available_packages[@]}"
    else
        warn "No packages available for installation"
    fi
    
    if [ ${#unavailable_packages[@]} -gt 0 ]; then
        warn "Skipping unavailable packages: ${unavailable_packages[*]}"
    fi
}

# Yes/No prompt with default value
prompt_yn() {
    local prompt="$1"
    local default="$2"  # "yes" or "no"
    local response

    if [ "$default" = "yes" ]; then
        read -p "$prompt [Y/n]: " response
        response=${response:-y}
    else
        read -p "$prompt [y/N]: " response
        response=${response:-n}
    fi

    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        [nN][oO]|[nN]) return 1 ;;
        *)
            warn "Invalid response. Please answer 'yes' or 'no'."
            prompt_yn "$prompt" "$default"
            ;;
    esac
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Check if dialog is available, fallback to read if not
check_dialog() {
    if command -v dialog >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

log "=== Starting VPS Optimization ==="

################################################################################
# 1. Detect OS Version
################################################################################
section "Step 1: Detecting operating system..."

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$NAME
    OS_VERSION=$VERSION_ID
    OS_CODENAME=$VERSION_CODENAME
    log "Detected OS: $OS_NAME $OS_VERSION ($OS_CODENAME)"
else
    error "Cannot detect OS version. /etc/os-release not found."
    exit 1
fi

# Check if Debian-based
if [[ ! "$ID" =~ ^(debian|ubuntu)$ ]]; then
    error "This script is designed for Debian/Ubuntu only. Detected: $ID"
    exit 1
fi

# Validate Debian version (support Debian 11, 12, 13 and Ubuntu 20.04+)
case "$ID" in
    debian)
        if [[ ! "$VERSION_ID" =~ ^(11|12|13)$ ]]; then
            warn "This script is optimized for Debian 11-13. Detected: Debian $VERSION_ID"
            warn "Continuing anyway, but some features may not work correctly."
        fi
        ;;
    ubuntu)
        if (( $(echo "$VERSION_ID < 20.04" | bc -l) )); then
            warn "This script is optimized for Ubuntu 20.04+. Detected: Ubuntu $VERSION_ID"
            warn "Continuing anyway, but some features may not work correctly."
        fi
        ;;
esac

################################################################################
# 2. User Creation and SSH Key Setup
################################################################################
section "Step 2: User account setup..."

echo ""
info "We need to create a new sudo user for secure access."
info "Root login will be disabled after setup."
echo ""

read -p "Enter new username: " NEW_USER

if [ -z "$NEW_USER" ]; then
    error "Username cannot be empty!"
    exit 1
fi

# Check if user already exists
if id "$NEW_USER" &>/dev/null; then
    warn "User $NEW_USER already exists. Skipping user creation..."

    # Offer to change password for existing user
    echo ""
    read -p "Do you want to change password for existing user $NEW_USER? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        passwd "$NEW_USER" && log "Password changed for $NEW_USER" || warn "Failed to change password"
    fi
else
    # Create user with disabled password initially (will be set below)
    adduser --gecos "" --disabled-password "$NEW_USER" || {
        error "Failed to create user $NEW_USER"
        exit 1
    }

    # Add to sudo group
    usermod -aG sudo "$NEW_USER"
    log "User $NEW_USER created and added to sudo group"

    # Set password for new user
    log "Setting password for new user $NEW_USER..."
    passwd "$NEW_USER" || warn "Failed to set password"
fi

# Store user for later use (adding to docker group)
DOCKER_USER=$NEW_USER

# Configure passwordless sudo for the new user
echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$NEW_USER
chmod 440 /etc/sudoers.d/$NEW_USER
log "Passwordless sudo configured for $NEW_USER"

# Configure passwordless sudo for root
if ! grep -q "^root.*NOPASSWD:ALL" /etc/sudoers.d/root 2>/dev/null; then
    echo "root ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/root
    chmod 440 /etc/sudoers.d/root
    log "Passwordless sudo configured for root"
fi

# Setup SSH keys
USER_HOME=$(eval echo ~$NEW_USER)
mkdir -p "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"

echo ""
info "Please paste your SSH public key (the content of your id_rsa.pub or id_ed25519.pub):"
info "If you don't have one, generate it on your local machine with: ssh-keygen -t ed25519"
echo ""
read -p "SSH Public Key: " SSH_PUBLIC_KEY

if [ -z "$SSH_PUBLIC_KEY" ]; then
    error "SSH public key cannot be empty!"
    exit 1
fi

# Add SSH key to authorized_keys
echo "$SSH_PUBLIC_KEY" > "$USER_HOME/.ssh/authorized_keys"
chmod 600 "$USER_HOME/.ssh/authorized_keys"
chown -R $NEW_USER:$NEW_USER "$USER_HOME/.ssh"
log "SSH key configured for $NEW_USER"

echo ""
warn "IMPORTANT: Please test SSH login with the new user in another terminal!"
warn "Command: ssh $NEW_USER@$(hostname -I | awk '{print $1}')"
echo ""
read -p "Press Enter once you've verified SSH access works..."

################################################################################
# 3. System Localization Settings
################################################################################
section "Step 3: Configuring system localization..."

echo ""
info "Setting up system locale, hostname, and timezone..."
echo ""

# Check if dialog is available, fallback to read if not
check_dialog() {
    if command -v dialog >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Locale selection
    echo "Select system locale:"
    echo "1) en_US.UTF-8 (English)"
    echo "2) ru_RU.UTF-8 (Russian)"
    echo "3) Both (en_US.UTF-8 + ru_RU.UTF-8)"
    
    if check_dialog; then
        LOCALE_CHOICE=$(dialog --title "Locale Selection" --radiolist "Select locale:" 15 60 3 "1" "English (en_US.UTF-8)" on "2" "Russian (ru_RU.UTF-8)" off "3" "Both (en_US.UTF-8 + ru_RU.UTF-8)" off 3>&1 1>&2 2>&3)
    else
        read -p "Enter choice [1-3]: " LOCALE_CHOICE
    fi

case $LOCALE_CHOICE in
    1)
        LOCALE_TO_GENERATE="en_US.UTF-8"
        DEFAULT_LOCALE="en_US.UTF-8"
        log "Selected locale: English (en_US.UTF-8)"
        ;;
    2)
        LOCALE_TO_GENERATE="ru_RU.UTF-8"
        DEFAULT_LOCALE="ru_RU.UTF-8"
        log "Selected locale: Russian (ru_RU.UTF-8)"
        ;;
    3)
        LOCALE_TO_GENERATE="en_US.UTF-8 ru_RU.UTF-8"
        DEFAULT_LOCALE="en_US.UTF-8"
        log "Selected locales: English + Russian"
        ;;
    *)
        warn "Invalid choice. Using English (en_US.UTF-8) as default"
        LOCALE_TO_GENERATE="en_US.UTF-8"
        DEFAULT_LOCALE="en_US.UTF-8"
        ;;
esac

# Install locales package with availability check
if package_available locales; then
    safe_install locales
else
    warn "locales package not available"
fi

# Generate locales
log "Generating locales..."
for locale in $LOCALE_TO_GENERATE; do
    log "Processing locale: $locale"
    
    # Ensure the locale exists in locale.gen
    if ! grep -q "^${locale} UTF-8" /etc/locale.gen 2>/dev/null && ! grep -q "^# ${locale} UTF-8" /etc/locale.gen 2>/dev/null; then
        echo "${locale} UTF-8" >> /etc/locale.gen
        log "Added ${locale} to /etc/locale.gen"
    fi
    
    # Uncomment the locale
    sed -i "s/^# *\(${locale} UTF-8\)/\1/" /etc/locale.gen
    log "Uncommented ${locale} in /etc/locale.gen"
done

# Generate locales without LC_ALL set
LC_ALL=C.UTF-8 /usr/sbin/locale-gen

# Update locale configuration file
cat > /etc/default/locale <<EOF
LANG=$DEFAULT_LOCALE
LANGUAGE=${DEFAULT_LOCALE%%.*}
LC_ALL=$DEFAULT_LOCALE
EOF

# Export for current session using safe C.UTF-8 to avoid warnings
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export LANGUAGE=en

# Write to profile for all users (will be applied on next login)
cat > /etc/profile.d/locale.sh <<EOF
export LANG=$DEFAULT_LOCALE
export LC_ALL=$DEFAULT_LOCALE
export LANGUAGE=${DEFAULT_LOCALE%%.*}
EOF

chmod +x /etc/profile.d/locale.sh

log "Default locale set to: $DEFAULT_LOCALE"
log "Locale will be fully applied after reboot or re-login"

# Hostname configuration
echo ""
read -p "Enter new hostname (press Enter to keep current: $(hostname)): " NEW_HOSTNAME

if [ -n "$NEW_HOSTNAME" ]; then
    # Validate hostname
    if [[ $(LC_ALL=C; echo "$NEW_HOSTNAME") =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        OLD_HOSTNAME=$(hostname)

        # Set new hostname
        hostnamectl set-hostname "$NEW_HOSTNAME"

        # Update /etc/hosts
        sed -i "s/127.0.1.1.*/127.0.1.1\t${NEW_HOSTNAME}/" /etc/hosts

        # Add entry if not exists
        if ! grep -q "127.0.1.1" /etc/hosts; then
            echo "127.0.1.1	${NEW_HOSTNAME}" >> /etc/hosts
        fi

        log "Hostname changed: $OLD_HOSTNAME -> $NEW_HOSTNAME"
    else
        warn "Invalid hostname format. Keeping current hostname: $(hostname)"
    fi
else
    log "Keeping current hostname: $(hostname)"
fi

# Timezone configuration
echo ""
# Get current timezone
if command -v timedatectl >/dev/null 2>&1; then
    CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null)
elif [ -L /etc/localtime ]; then
    CURRENT_TZ=$(readlink /etc/localtime | sed 's|/usr/share/zoneinfo/||')
else
    CURRENT_TZ="Unknown"
fi

info "Current timezone: $CURRENT_TZ"
info "Examples: Europe/Moscow, America/New_York, Asia/Tokyo, UTC"
echo ""
read -p "Enter timezone (press Enter to keep current): " NEW_TIMEZONE

if [ -n "$NEW_TIMEZONE" ]; then
    # Validate timezone
    if [ -f "/usr/share/zoneinfo/$NEW_TIMEZONE" ]; then
        if command -v timedatectl >/dev/null 2>&1; then
            # Use timedatectl if available
            timedatectl set-timezone "$NEW_TIMEZONE" 2>/dev/null && log "Timezone set to: $NEW_TIMEZONE" || {
                # Fallback to manual method
                ln -sf "/usr/share/zoneinfo/$NEW_TIMEZONE" /etc/localtime
                echo "$NEW_TIMEZONE" > /etc/timezone
                log "Timezone set to: $NEW_TIMEZONE (manual method)"
            }
        else
            # Manual timezone configuration
            ln -sf "/usr/share/zoneinfo/$NEW_TIMEZONE" /etc/localtime
            echo "$NEW_TIMEZONE" > /etc/timezone
            log "Timezone set to: $NEW_TIMEZONE"
        fi
    else
        warn "Invalid timezone '$NEW_TIMEZONE'. Timezone file not found."
        warn "Keeping current timezone."
    fi
else
    log "Keeping current timezone: $CURRENT_TZ"
fi

# Enable NTP if timedatectl is available
if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-ntp true 2>/dev/null && log "NTP synchronization enabled" || warn "Could not enable NTP"
else
    info "NTP configuration requires systemd - install ntp package manually if needed"
fi

echo ""
info "Localization configured:"
info "  Locale: $DEFAULT_LOCALE"
info "  Hostname: $(hostname)"
# Get timezone again for display
if command -v timedatectl >/dev/null 2>&1; then
    DISPLAY_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null)
elif [ -L /etc/localtime ]; then
    DISPLAY_TZ=$(readlink /etc/localtime | sed 's|/usr/share/zoneinfo/||')
else
    DISPLAY_TZ="Unknown"
fi
info "  Timezone: $DISPLAY_TZ"
echo ""

################################################################################
# 4. Zsh and Starship Installation
################################################################################
section "Step 4: Installing and configuring Zsh + Starship..."

echo ""
info "Installing Zsh and Starship for better shell experience..."
echo ""

# Install Zsh and dependencies with availability check
safe_install zsh git curl

# Install Starship prompt (universal, works everywhere)
curl -sS https://starship.rs/install.sh | sh -s -- -y
log "Starship prompt installed"

# Function to setup Zsh for a user
setup_zsh_for_user() {
    local username=$1
    local user_home=$(eval echo ~$username)

    log "Setting up Zsh for user: $username"

    # Create plugins directory
    mkdir -p "$user_home/.zsh"

    # Install zsh-autosuggestions
    if [ ! -d "$user_home/.zsh/zsh-autosuggestions" ]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions "$user_home/.zsh/zsh-autosuggestions"
        log "zsh-autosuggestions plugin installed for $username"
    fi

    # Install zsh-syntax-highlighting
    if [ ! -d "$user_home/.zsh/zsh-syntax-highlighting" ]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$user_home/.zsh/zsh-syntax-highlighting"
        log "zsh-syntax-highlighting plugin installed for $username"
    fi

    # Install zsh-completions
    if [ ! -d "$user_home/.zsh/zsh-completions" ]; then
        git clone https://github.com/zsh-users/zsh-completions "$user_home/.zsh/zsh-completions"
        log "zsh-completions plugin installed for $username"
    fi

    # Create .zshrc with optimal configuration
    cat > "$user_home/.zshrc" <<'ZSHRC'
# Fix VSCode Remote SSH/Tunnels terminal error with __vsc_update_env
# This must be at the top to override VSCode's function
if [[ -n "$VSCODE_INJECTION" ]] || [[ "$TERM_PROGRAM" == "vscode" ]]; then
    # Define a safe version of __vsc_update_env function
    # The original VSCode function conflicts with KSH_ARRAYS and other Zsh options
    __vsc_update_env() {
        emulate -L zsh
        setopt LOCAL_OPTIONS
        unsetopt KSH_ARRAYS
        local -a args
        args=("${(@)@}")
        local key value
        for arg in "${args[@]}"; do
            key="${arg%%=*}"
            value="${arg#*=}"
            # Only export if key exists and contains =
            if [[ -n "$key" && "$key" != "$arg" ]]; then
                export "$key=$value"
            fi
        done
    }
fi

# History configuration
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history
setopt EXTENDED_HISTORY INC_APPEND_HISTORY SHARE_HISTORY
setopt HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE
setopt HIST_SAVE_NO_DUPS HIST_VERIFY APPEND_HISTORY

# Directory navigation
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT

# Initialize Completion FIRST (before plugins)
# Use safe array expansion and check directory existence
if [[ -d "$HOME/.zsh/zsh-completions/src" ]]; then
    fpath=("$HOME/.zsh/zsh-completions/src" "${fpath[@]}")
fi

autoload -Uz compinit compdump
# Enable EXTENDED_GLOB for (#qN.mh+24)
setopt EXTENDED_GLOB
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
    compinit
else
    compinit -C
fi

# Load zsh-autosuggestions SECOND
if [[ -f ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
    ZSH_AUTOSUGGEST_USE_ASYNC=true
    ZSH_AUTOSUGGEST_MANUAL_REBIND=1
    bindkey '^ ' autosuggest-accept
    bindkey '^[^M' autosuggest-execute
fi

# Load zsh-syntax-highlighting LAST
if [[ -f ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)
    source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

setopt COMPLETE_IN_WORD ALWAYS_TO_END PATH_DIRS AUTO_MENU AUTO_LIST AUTO_PARAM_SLASH
unsetopt FLOW_CONTROL

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'
zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm -w -w"
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache

# Bash compatibility
setopt BASH_REMATCH
# Only enable KSH_ARRAYS outside of VSCode terminal (it conflicts with VSCode's __vsc_update_env)
if [[ -z "$VSCODE_INJECTION" && "$TERM_PROGRAM" != "vscode" ]]; then
    setopt KSH_ARRAYS
fi
autoload -Uz bashcompinit && bashcompinit

# Key bindings
bindkey '^[[A' up-line-or-history
bindkey '^[[B' down-line-or-history
bindkey '^[[3~' delete-char
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line

# Environment variables
export EDITOR='vim'
export VISUAL='vim'
export PAGER='less'

# Docker aliases
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'
alias dex='docker exec -it'
alias drm='docker rm'
alias drmi='docker rmi'
alias dprune='docker system prune -af'

# Git aliases
alias g='git'
alias gs='git status'
alias gst='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit -a'
alias gcam='git commit -am'
alias gp='git pull'
alias gP='git push'
alias gpo='git push origin'
alias gl='git log --oneline --graph --decorate'
alias gd='git diff'
alias gb='git branch'
alias gco='git checkout'
alias gcb='git checkout -b'

# System aliases
alias ll='ls -alFh'
alias la='ls -A'
alias l='ls -CF'
alias cls='clear'
alias c='clear'
alias h='history'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# System monitoring
alias meminfo='free -h'
alias cpuinfo='lscpu'
alias diskinfo='df -h'
alias ports='netstat -tulanp'
alias psa='ps aux'
alias psg='ps aux | grep'

# Package management
alias update='sudo apt update && sudo apt upgrade -y'
alias install='sudo apt install'
alias remove='sudo apt remove'
alias search='apt search'
alias autoremove='sudo apt autoremove -y'

# Safety aliases
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -pv'

# Useful functions
mkcd() {
    mkdir -p "$1" && cd "$1"
}

extract() {
    if [ -f $1 ] ; then
        case $1 in
            *.tar.bz2)   tar xjf $1     ;;
            *.tar.gz)    tar xzf $1     ;;
            *.bz2)       bunzip2 $1     ;;
            *.rar)       unrar e $1     ;;
            *.gz)        gunzip $1      ;;
            *.tar)       tar xf $1      ;;
            *.tbz2)      tar xjf $1     ;;
            *.tgz)       tar xzf $1     ;;
            *.zip)       unzip $1       ;;
            *.Z)         uncompress $1  ;;
            *.7z)        7z x $1        ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Initialize Starship prompt
eval "$(starship init zsh)"

ZSHRC

    # Compile .zshrc for faster loading (~50-100ms improvement)
    if [ "$username" = "root" ]; then
        zsh -c "zcompile $user_home/.zshrc" 2>/dev/null || true
    else
        su - "$username" -c "zsh -c 'zcompile ~/.zshrc'" 2>/dev/null || true
    fi

    # Create Starship config with Unicode icons (works everywhere)
    mkdir -p "$user_home/.config"
    
    cat > "$user_home/.config/starship.toml" <<'STARSHIP'
# Starship configuration - Modern & Clean
# Optimized for VPS environments

command_timeout = 500
add_newline = true
scan_timeout = 30

format = """
$username\
$hostname\
$directory\
$git_branch\
$git_commit\
$git_status\
$docker_context\
$python\
$nodejs\
$golang\
$rust\
$java\
$terraform\
$aws\
$kubernetes\
$line_break\
$character"""

right_format = """$cmd_duration $time"""

[username]
style_user = 'cyan bold'
style_root = 'red bold'
format = '[$user]($style) '
disabled = false
show_always = true

[hostname]
ssh_only = false
format = 'on [$hostname](bold yellow) '
disabled = false
trim_at = '.'

[directory]
truncation_length = 3
truncate_to_repo = true
style = 'cyan bold'
read_only = " 🔒"
format = 'in [$path]($style)[$read_only]($read_only_style) '

[character]
success_symbol = '[❯](bold green)'
error_symbol = '[❯](bold red)'

[git_branch]
symbol = "🌱 "
format = 'on [$symbol$branch]($style) '
style = 'purple bold'

[git_commit]
commit_hash_length = 7
format = '[\($hash$tag\)]($style) '
style = 'green bold'
only_detached = true
tag_disabled = false
tag_symbol = ' 🏷 '

[git_status]
format = '([\[$all_status$ahead_behind\]]($style) )'
style = 'red bold'
conflicted = '🏳'
ahead = '⇡${count}'
behind = '⇣${count}'
diverged = '⇕⇡${ahead_count}⇣${behind_count}'
up_to_date = '✓'
untracked = '?${count}'
stashed = '📦'
modified = '!${count}'
staged = '+${count}'
renamed = '»${count}'
deleted = '✘${count}'

[cmd_duration]
min_time = 500
format = 'took [$duration](bold yellow) '
show_milliseconds = false

[time]
disabled = false
format = '[$time](bold white)'
time_format = '%T'

[docker_context]
symbol = "🐋 "
format = 'via [$symbol$context]($style) '
style = 'blue bold'
only_with_files = true

[python]
symbol = "🐍 "
format = 'via [$symbol$version]($style) '
style = 'yellow bold'

[nodejs]
symbol = "[⬢](bold green) "
format = 'via [$symbol$version]($style) '
style = 'green bold'

[golang]
symbol = "🐹 "
format = 'via [$symbol$version]($style) '
style = 'cyan bold'

[rust]
symbol = "🦀 "
format = 'via [$symbol$version]($style) '
style = 'red bold'

[java]
symbol = "☕ "
format = 'via [$symbol$version]($style) '
style = 'red bold'

[terraform]
symbol = "💠 "
format = 'via [$symbol$version]($style) '
style = 'purple bold'

[aws]
symbol = "☁️ "
format = 'on [$symbol($profile )(\($region\) )(\[$duration\] )]($style)'
style = 'bold yellow'

[kubernetes]
symbol = "⎈ "
format = 'on [$symbol$context( \($namespace\))]($style) '
style = 'cyan bold'
disabled = false

[package]
disabled = true

[memory_usage]
disabled = true

[battery]
disabled = true
STARSHIP

    # Create cache directory for completions
    mkdir -p "$user_home/.zsh/cache"

    # Set correct ownership for all created files and directories
    chown -R $username:$username "$user_home/.zshrc" "$user_home/.zsh" "$user_home/.config" "$user_home/.zcompdump" 2>/dev/null || true

    # Set correct permissions
    chmod 644 "$user_home/.zshrc" 2>/dev/null || true
    chmod 644 "$user_home/.config/starship.toml" 2>/dev/null || true

    # Change default shell to Zsh
    local zsh_path=$(which zsh)
    if [ -z "$zsh_path" ]; then
        error "Cannot find zsh binary"
        return 1
    fi

    # Ensure zsh is in /etc/shells
    if ! grep -q "^$zsh_path$" /etc/shells; then
        echo "$zsh_path" >> /etc/shells
        log "Added $zsh_path to /etc/shells"
    fi

    chsh -s "$zsh_path" "$username"
    log "Default shell changed to Zsh for $username"
}

# Ensure zsh is available before setup
if ! command -v zsh &> /dev/null; then
    error "Zsh installation failed - zsh binary not found!"
    exit 1
fi

# Setup Zsh for root
setup_zsh_for_user root

# Setup Zsh for new user
setup_zsh_for_user $NEW_USER

# Ensure starship is available
if ! command -v starship &> /dev/null; then
    error "Starship installation failed!"
    exit 1
fi

echo ""
info "Zsh + Starship configured successfully!"
info "Features enabled:"
info "  • Starship prompt with Unicode icons (⬢ 🐋 🐍 🌱)"
info "  • Autosuggestions (fish-like suggestions)"
info "  • Syntax highlighting (real-time red/green)"
info "  • Git integration"
info "  • Docker context display"
info "  • Advanced completion system"
info "  • 50+ useful aliases"
info "  • Bash compatibility mode"
info ""
info "How to use autosuggestions:"
info "  • Type command → see gray suggestion from history"
info "  • Press → (Right arrow) or End to accept"
info "  • Ctrl+→ to accept one word"
echo ""

################################################################################
# 5. Go Installation
################################################################################
section "Step 5: Go Installation"

log "Installing Go programming language..."

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) GO_ARCH="amd64" ;;
    aarch64) GO_ARCH="arm64" ;;
    *) GO_ARCH="$ARCH"; warn "Unknown architecture, attempting with: $ARCH" ;;
esac

# Fetch latest Go version
GO_VERSION=$(curl -s https://go.dev/VERSION?m=text 2>/dev/null | head -1 | sed 's/go//')
if [ -z "$GO_VERSION" ]; then
    GO_VERSION="1.25.4"  # fallback version
    warn "Could not detect latest Go version, using fallback: $GO_VERSION"
fi

GO_DOWNLOAD_URL="https://dl.google.com/go/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
GO_CHECKSUM_URL="https://dl.google.com/go/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz.sha256"

log "Go version: $GO_VERSION ($GO_ARCH)"
log "Downloading Go from: $GO_DOWNLOAD_URL"

# Download Go binary
cd /tmp

# Download checksum (Google provides just the hash, sometimes with filename)
CHECKSUM=$(curl -fsSL "$GO_CHECKSUM_URL" 2>/dev/null | head -1 | awk '{print $1}')
if [ -z "$CHECKSUM" ]; then
    error "Could not download Go checksum from $GO_CHECKSUM_URL"
    exit 1
fi

log "Expected checksum: $CHECKSUM"

# Download Go binary
curl -fsSL "$GO_DOWNLOAD_URL" -o "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"

# Verify checksum
ACTUAL_CHECKSUM=$(sha256sum "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" | awk '{print $1}')
if [ "$CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
    error "Go checksum verification failed!"
    error "Expected: $CHECKSUM"
    error "Actual:   $ACTUAL_CHECKSUM"
    exit 1
fi
log "Go checksum verified successfully"

# Remove old Go installation if exists
rm -rf /usr/local/go
mkdir -p /usr/local/go

# Extract and install
tar -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -C /usr/local/

# Create profile.d entry for Go PATH
cat > /etc/profile.d/golang.sh <<'GOEOF'
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
GOEOF

chmod +x /etc/profile.d/golang.sh

# Add Go to .zshrc for root
if [ -f /root/.zshrc ]; then
    if ! grep -q "GOROOT" /root/.zshrc; then
        cat >> /root/.zshrc <<'GORC'

# Go configuration
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
GORC
    fi
fi

# Add Go to .zshrc for new user
USER_HOME=$(eval echo ~$NEW_USER)
if [ -f "$USER_HOME/.zshrc" ]; then
    if ! grep -q "GOROOT" "$USER_HOME/.zshrc"; then
        cat >> "$USER_HOME/.zshrc" <<'GORC'

# Go configuration
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
GORC
        chown $NEW_USER:$NEW_USER "$USER_HOME/.zshrc"
    fi
fi

# Source the profile for current session
. /etc/profile.d/golang.sh

log "Go ${GO_VERSION} installed successfully"
log "Go path: /usr/local/go/bin/go"

# Cleanup
rm -f /tmp/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz

################################################################################
# 6. Node.js and NVM Installation
################################################################################
section "Step 6: Node.js Installation (NVM)"

log "Installing Node.js via NVM (Node Version Manager)..."

# Function to install NVM for a user
install_nvm_for_user() {
    local username=$1
    local user_home=$(eval echo ~$username)

    log "Installing NVM for user: $username"

    # Create NVM installation script that runs as the target user
    local nvm_install_script="/tmp/nvm_install_${username}.sh"

    cat > "$nvm_install_script" <<'NVMINSTALL'
#!/bin/bash
# This script runs as the target user to install NVM

export HOME="$1"
export USER="$2"

# Get latest NVM version from GitHub API
NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

# Fallback to known stable version if API fails
if [ -z "$NVM_VERSION" ]; then
    NVM_VERSION="v0.40.1"
    echo "Warning: Could not fetch latest NVM version, using fallback: $NVM_VERSION"
else
    echo "Installing NVM version: $NVM_VERSION"
fi

# Download and install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash

# Source NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Install Node.js LTS
nvm install --lts
nvm alias default lts/*
nvm use default

# Output versions for verification
node --version
npm --version
NVMINSTALL

    chmod +x "$nvm_install_script"

    # Run the installation script as the target user
    if [ "$username" = "root" ]; then
        # For root, run directly
        bash "$nvm_install_script" "$user_home" "$username"
    else
        # For non-root users, use su to run as that user
        su - "$username" -c "bash $nvm_install_script $user_home $username"
    fi

    # Verify installation
    export NVM_DIR="$user_home/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        log "NVM installed successfully for $username"
    else
        warn "NVM installation may have failed for $username"
    fi

    # Add NVM lazy loading to .zshrc if present (~500-1000ms improvement)
    if [ -f "$user_home/.zshrc" ]; then
        if ! grep -q "NVM_DIR" "$user_home/.zshrc"; then
            cat >> "$user_home/.zshrc" <<'NVMRC'

# NVM (Node Version Manager) - Lazy Loading for fast shell startup
export NVM_DIR="$HOME/.nvm"

# Only load NVM when actually using node/npm/nvm commands
if [ -s "$NVM_DIR/nvm.sh" ]; then
    # Create placeholder functions that load NVM on first use
    nvm() {
        unset -f nvm node npm npx 2>/dev/null
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm "$@"
    }

    node() {
        unset -f nvm node npm npx 2>/dev/null
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        node "$@"
    }

    npm() {
        unset -f nvm node npm npx 2>/dev/null
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        npm "$@"
    }

    npx() {
        unset -f nvm node npm npx 2>/dev/null
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        npx "$@"
    }
fi
NVMRC
        fi
    fi

    # Ensure all NVM files have correct ownership
    chown -R "$username:$username" "$user_home/.nvm" 2>/dev/null || true
    chown -R "$username:$username" "$user_home/.npm" 2>/dev/null || true
    chown "$username:$username" "$user_home/.zshrc" 2>/dev/null || true

    # Clean up
    rm -f "$nvm_install_script"

    log "NVM setup completed for $username"
}

# Install NVM for root
install_nvm_for_user root

# Install NVM for new user
install_nvm_for_user $NEW_USER

log "Node.js and NVM installation complete"

################################################################################
# 7. Detect CPU Architecture and RAM
################################################################################
log "Step 7: Detecting system specifications..."

# Install bc with availability check (needed for calculations)
safe_install bc

# Detect CPU architecture
CPU_ARCH=$(uname -m)
log "CPU Architecture: $CPU_ARCH"

# Get total RAM in GB (force English locale for decimal point)
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$(LC_NUMERIC=C awk "BEGIN {printf \"%.2f\", $TOTAL_RAM_KB/1024/1024}")
# Replace comma with dot for calculations
TOTAL_RAM_GB=$(echo "$TOTAL_RAM_GB" | tr ',' '.')
log "Total RAM: ${TOTAL_RAM_GB}GB"

# Calculate swap size based on RAM (force English locale for bc)
if (( $(LC_NUMERIC=C echo "$TOTAL_RAM_GB < 3" | bc -l) )); then
    # Less than 3GB: swap = 2 * RAM
    SWAP_SIZE=$(LC_NUMERIC=C awk "BEGIN {printf \"%.0f\", $TOTAL_RAM_GB * 2 + 0.5}")
    SWAPPINESS=60
    log "RAM < 3GB: Creating ${SWAP_SIZE}GB swap (2x RAM)"
else
    # 3GB or more: swap = RAM / 2 (rounded up for better performance)
    SWAP_SIZE=$(LC_NUMERIC=C awk "BEGIN {printf \"%.0f\", ($TOTAL_RAM_GB / 2) + 0.5}")
    SWAPPINESS=10
    log "RAM >= 3GB: Creating ${SWAP_SIZE}GB swap (0.5x RAM)"
fi

################################################################################
# 6. System Update and Essential Packages
################################################################################
log "Step 8: Updating system and installing essential packages..."

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Enrich APT sources with non-free packages
log "Enriching APT sources with contrib and non-free components..."
if [ -f /etc/apt/sources.list ]; then
    # Add contrib and non-free to all deb sources (if not already present)
    sed -i 's/^deb \(http\|https\)/deb \1/g; s/^deb \([^#]*\)$/deb \1 contrib non-free non-free-firmware/g; s/contrib non-free non-free-firmware.*contrib non-free non-free-firmware/contrib non-free non-free-firmware/g' /etc/apt/sources.list
fi
apt-get update
log "APT sources enriched with contrib and non-free components"

# Install essential packages with availability check
essential_packages=(
    "wget"
    "curl"
    "git"
    "htop"
    "iotop"
    "sysstat"
    "net-tools"
    "iptables"
    "ufw"
    "fail2ban"
    "unattended-upgrades"
    "apt-listchanges"
    "needrestart"
    "ncdu"
    "tree"
    "vim"
    "nano"
    "tmux"
    "zip"
    "unzip"
    "gnupg"
    "ca-certificates"
    "lsb-release"
    # "fastfetch"  # Commented out - may not be available in Debian 13
    "cmake"
    "make"
    "gcc"
    "g++"
    "python3-venv"
    "fzf"
    "ripgrep"
    "fd-find"
    "bat"
    "xz-utils"
    "xdg-user-dirs"
)

safe_install "${essential_packages[@]}"

# Configure iptables-legacy for Debian 13+ (nftables compatibility issue with UFW)
# Must be done BEFORE installing UFW to ensure proper initialization
log "Configuring iptables-legacy for UFW and Docker compatibility..."

# Switch ALL iptables utilities to legacy mode (critical for UFW)
# Set master alternatives first
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 100
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-legacy 100
# Set slave alternatives (iptables-restore and iptables-save are automatically managed)
update-alternatives --set iptables-save /usr/sbin/iptables-legacy-save 2>/dev/null || true
update-alternatives --set ip6tables-save /usr/sbin/ip6tables-legacy-save 2>/dev/null || true

log "iptables switched to legacy mode (all utilities) for compatibility"

log "Essential packages installed"

# Create Debian package aliases (Debian uses different names for some packages)
log "Creating package aliases..."
[ -f /usr/bin/batcat ] && [ ! -f /usr/bin/bat ] && ln -sf /usr/bin/batcat /usr/bin/bat 2>/dev/null || true
[ -f /usr/bin/fdfind ] && [ ! -f /usr/bin/fd ] && ln -sf /usr/bin/fdfind /usr/bin/fd 2>/dev/null || true
log "Package aliases created"

################################################################################
# 8. XanMod Kernel Installation
################################################################################
log "Step 9: Checking XanMod kernel compatibility..."

# XanMod supports x86_64 (amd64) architecture
if [[ "$CPU_ARCH" == "x86_64" ]]; then
    log "CPU architecture is compatible with XanMod kernel"

    # Use official XanMod CPU level detection script
    info "Detecting CPU microarchitecture level..."
    
    CPU_LEVEL=$(awk 'BEGIN {
        while (!/flags/) if (getline < "/proc/cpuinfo" != 1) exit 1
        if (/lm/&&/cmov/&&/cx8/&&/fpu/&&/fxsr/&&/mmx/&&/syscall/&&/sse2/) level = 1
        if (level == 1 && /cx16/&&/lahf/&&/popcnt/&&/sse4_1/&&/sse4_2/&&/ssse3/) level = 2
        if (level == 2 && /avx/&&/avx2/&&/bmi1/&&/bmi2/&&/f16c/&&/fma/&&/abm/&&/movbe/&&/xsave/) level = 3
        if (level == 3 && /avx512f/&&/avx512bw/&&/avx512cd/&&/avx512dq/&&/avx512vl/) level = 4
        if (level > 0) { print level; exit 0 }
        exit 1
    }')

    # Determine XanMod variant based on CPU level
    case "$CPU_LEVEL" in
        4)
            XANMOD_VARIANT="x64v4"
            log "CPU supports x86-64-v4 (AVX-512) - using XanMod x64v4 variant"
            ;;
        3)
            XANMOD_VARIANT="x64v3"
            log "CPU supports x86-64-v3 (AVX2, BMI2, FMA) - using XanMod x64v3 variant"
            ;;
        2)
            XANMOD_VARIANT="x64v2"
            log "CPU supports x86-64-v2 (SSE4.2, POPCNT) - using XanMod x64v2 variant"
            ;;
        1)
            XANMOD_VARIANT="x64v1"
            log "CPU supports x86-64-v1 (basic) - using XanMod x64v1 variant"
            ;;
        *)
            warn "Unable to detect CPU level. Using generic XanMod x64v1 variant"
            XANMOD_VARIANT="x64v1"
            ;;
    esac

    info "Installing XanMod kernel ($XANMOD_VARIANT)..."

    # Add XanMod repository
    wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg

    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list

    # Install XanMod kernel based on detected variant with availability check
    case $XANMOD_VARIANT in
        "x64v4")
            if package_available linux-xanmod-x64v4; then
                safe_install linux-xanmod-x64v4
            else
                warn "x64v4 package not available, falling back to x64v3"
                safe_install linux-xanmod-x64v3
                XANMOD_VARIANT="x64v3"
            fi
            ;;
        "x64v3")
            safe_install linux-xanmod-x64v3
            ;;
        "x64v2")
            safe_install linux-xanmod-x64v2
            ;;
        *)
            safe_install linux-xanmod-x64v1
            ;;
    esac

    log "XanMod kernel ($XANMOD_VARIANT) installed successfully"
    XANMOD_INSTALLED=true
else
    warn "CPU architecture ($CPU_ARCH) is not compatible with XanMod kernel"
    warn "Skipping XanMod installation. Continuing with default kernel..."
    XANMOD_INSTALLED=false
fi

################################################################################
# 8. Docker and Docker Compose Installation
################################################################################
log "Step 10: Installing Docker and Docker Compose..."

# Remove old Docker versions if present
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    apt-get remove -y $pkg 2>/dev/null || true
done

# Note: iptables-legacy was already configured above for UFW and Docker compatibility
log "Using iptables-legacy for Docker compatibility (already configured)"

# Install prerequisites (ca-certificates, curl, gnupg, lsb-release already installed)
install -m 0755 -d /etc/apt/keyrings

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/$ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID \
  $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine, CLI, containerd, and Docker Compose plugin with availability check
docker_packages=(
    "docker-ce"
    "docker-ce-cli"
    "containerd.io"
    "docker-buildx-plugin"
    "docker-compose-plugin"
)

safe_install "${docker_packages[@]}"

# Check if Docker was actually installed
if ! command -v docker &>/dev/null; then
    error "Docker installation failed - docker binary not found!"
    exit 1
fi

# Configure Docker daemon for better performance BEFORE starting service
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "features": {
    "buildkit": true
  }
}
EOF

# Create systemd drop-in directory for Docker service customization
mkdir -p /etc/systemd/system/docker.service.d

# Create systemd service override to fix socket activation issues
cat > /etc/systemd/system/docker.service.d/override.conf <<'SYSTEMD_EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H unix:///var/run/docker.sock
SYSTEMD_EOF

# Enable and start Docker service with stale process cleanup
systemctl daemon-reload

# Clean up any stale Docker processes and PID file before starting
if [ -f /var/run/docker.pid ]; then
    old_pid=$(cat /var/run/docker.pid 2>/dev/null || echo "")
    if [ -n "$old_pid" ]; then
        kill -9 "$old_pid" 2>/dev/null || true
        sleep 1
    fi
    rm -f /var/run/docker.pid
fi

# Also try to kill any lingering dockerd processes
pkill -9 dockerd 2>/dev/null || true
sleep 1

systemctl enable docker
systemctl enable docker.socket
systemctl start docker.socket
systemctl start docker

# Ensure docker group exists
groupadd -f docker

# Fix docker.sock permissions
sleep 1
if [ -S /var/run/docker.sock ]; then
    chown root:docker /var/run/docker.sock
    chmod 660 /var/run/docker.sock
    log "Docker socket permissions fixed"
fi

# Add user to docker group
usermod -aG docker "$DOCKER_USER"
log "User $DOCKER_USER added to docker group"

# Verify Docker installation
DOCKER_VERSION=$(docker --version)
COMPOSE_VERSION=$(docker compose version)
log "Docker installed: $DOCKER_VERSION"
log "Docker Compose installed: $COMPOSE_VERSION"

log "Docker and Docker Compose installation complete"

################################################################################
# 9. Kernel Parameters Optimization (sysctl)
################################################################################
log "Step 11: Optimizing kernel parameters..."

# Ensure /etc/sysctl.conf exists (some minimal Debian installations don't have it)
if [ ! -f /etc/sysctl.conf ]; then
    log "Creating /etc/sysctl.conf (was missing)..."
    cat > /etc/sysctl.conf <<'SYSCTLCONF'
#
# /etc/sysctl.conf - Configuration file for setting system variables
# See /etc/sysctl.d/ for additional system variables.
# See sysctl.conf (5) for information.
#

# Additional settings are in /etc/sysctl.d/
SYSCTLCONF
fi

# Backup original sysctl.conf
cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%F) 2>/dev/null || true

cat > /etc/sysctl.d/99-vps-optimization.conf <<EOF
# VPS Optimization - Optimized for VPN servers with 1-4GB RAM
# Focus: Low latency, efficient memory usage, VPN traffic optimization

# ============================================================================
# Network Performance - Optimized for VPN (TCP + UDP)
# ============================================================================

# TCP/UDP Buffer Sizes (balanced for 1-4GB RAM, VPN optimized)
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 131072 16777216

# UDP Buffer Sizes (critical for VPN protocols like WireGuard, OpenVPN)
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# Network Queues (optimized for VPN latency)
net.core.netdev_max_backlog = 8192
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192

# TCP Performance Tuning
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 10240 65535

# TCP Fast Open (reduces VPN connection latency by 15-40%)
net.ipv4.tcp_fastopen = 3

# TCP Keep-Alive (faster dead connection detection for VPN)
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3

# TCP Window Scaling & SACK (better for high-latency VPN connections)
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# TCP Orphan & TIME_WAIT limits (prevent memory exhaustion)
net.ipv4.tcp_max_orphans = 32768
net.ipv4.tcp_max_tw_buckets = 131072

# MTU Probing (helps with VPN encapsulation overhead)
net.ipv4.tcp_mtu_probing = 1

# ============================================================================
# TCP Congestion Control - BBR for better VPN throughput
# ============================================================================
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# ============================================================================
# Connection Tracking - Optimized for VPN tunnels
# ============================================================================
net.netfilter.nf_conntrack_max = 131072
net.netfilter.nf_conntrack_tcp_timeout_established = 1800
net.netfilter.nf_conntrack_udp_timeout = 60
net.netfilter.nf_conntrack_udp_timeout_stream = 120

# Generic timeout (for VPN protocols)
net.netfilter.nf_conntrack_generic_timeout = 120

# ============================================================================
# File System Performance
# ============================================================================
fs.file-max = 1048576
fs.inotify.max_user_watches = 262144
fs.inotify.max_user_instances = 256

# ============================================================================
# Virtual Memory - Optimized for 1-4GB RAM
# ============================================================================
vm.swappiness = $SWAPPINESS
vm.vfs_cache_pressure = 60
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500

# Memory management
vm.min_free_kbytes = 65536
vm.overcommit_memory = 1
vm.overcommit_ratio = 50
vm.zone_reclaim_mode = 0

# ============================================================================
# Security (VPN server hardening)
# ============================================================================

# IP Forwarding (required for VPN)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Reverse Path Filtering
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ICMP & Broadcast protection
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Source routing (disable for security)
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Redirect protection
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# SYN flood protection
net.ipv4.tcp_syncookies = 1

# ============================================================================
# Kernel Performance
# ============================================================================
kernel.panic = 10
kernel.panic_on_oops = 1

# Process limits (moderate for low RAM)
kernel.pid_max = 65536
kernel.threads-max = 65536

# Scheduler optimization (low latency for VPN)
# Note: sched_migration_cost_ns may not be available in virtualized environments
kernel.sched_migration_cost_ns = 5000000
kernel.sched_autogroup_enabled = 0

# Entropy (important for VPN encryption)
kernel.random.write_wakeup_threshold = 1024

EOF

# Apply sysctl settings with error tolerance for missing parameters
# Some parameters may not exist in virtualized environments (WSL2, containers, etc.)
sysctl -e -p /etc/sysctl.d/99-vps-optimization.conf 2>&1 | grep -v "cannot stat" | grep -v "No such file or directory" || true
log "Kernel parameters applied (some may be skipped in virtualized environments)"

################################################################################
# 10. Swap Optimization
################################################################################
log "Step 12: Setting up swap file..."

# Remove existing swap if present
if swapon --show | grep -q "/swapfile"; then
    log "Removing existing swap..."
    swapoff /swapfile
    rm -f /swapfile
    sed -i '/\/swapfile/d' /etc/fstab
fi

# Create new swap with calculated size
log "Creating ${SWAP_SIZE}GB swap file..."
if ! fallocate -l ${SWAP_SIZE}G /swapfile 2>/dev/null; then
    dd if=/dev/zero of=/swapfile bs=1G count=$SWAP_SIZE status=progress
fi
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Add to fstab
if ! grep -q "/swapfile" /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

log "Swap file created and enabled (${SWAP_SIZE}GB, swappiness=$SWAPPINESS)"

################################################################################
# 11. Firewall Configuration (UFW)
################################################################################
log "Step 13: Firewall configuration..."

# Enable UFW firewall (iptables-legacy was already configured above for compatibility)
log "Enabling UFW firewall..."
ufw --force enable >/dev/null 2>&1 || warn "Could not enable UFW"

# Configure UFW rules
# Default policies
ufw default deny incoming 2>/dev/null
ufw default allow outgoing 2>/dev/null

# Allow SSH (critical for VPS access)
ufw allow 22/tcp 2>/dev/null || warn "Could not allow SSH port"

# Allow HTTP and HTTPS if Docker is running web services
ufw allow 80/tcp 2>/dev/null
ufw allow 443/tcp 2>/dev/null

log "UFW firewall enabled with SSH access allowed"
log "Firewall rules: SSH (22/tcp), HTTP (80/tcp), HTTPS (443/tcp) allowed"

################################################################################
# 12. Fail2Ban Configuration
################################################################################
log "Step 14: Configuring Fail2Ban..."

systemctl enable fail2ban
systemctl start fail2ban

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban

[sshd]
enabled = true
port = 22
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF

systemctl restart fail2ban

################################################################################
# 25. System Limits Optimization
################################################################################
log "Step 15: Optimizing system limits..."

cat > /etc/security/limits.d/99-vps-limits.conf <<EOF
# VPS Limits Optimization
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
root soft nofile 65535
root hard nofile 65535
root soft nproc 65535
root hard nproc 65535
EOF

################################################################################
# 14. Automatic Security Updates
################################################################################
log "Step 16: Configuring automatic security updates..."

cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

################################################################################
# 15. Journal Log Size Limit
################################################################################
log "Step 17: Limiting systemd journal size..."

mkdir -p /etc/systemd/journald.conf.d/
cat > /etc/systemd/journald.conf.d/00-journal-size.conf <<EOF
[Journal]
SystemMaxUse=500M
SystemMaxFileSize=100M
RuntimeMaxUse=100M
EOF

systemctl restart systemd-journald

################################################################################
# 24. SSH Hardening
################################################################################
log "Step 18: Hardening SSH configuration..."

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%F) 2>/dev/null || true

# Create hardening config
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<EOF
# SSH Hardening - VPS Optimization
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10
AllowTcpForwarding yes

# Only allow specific user
AllowUsers $NEW_USER
EOF

# Test SSH configuration
if sshd -t; then
    log "SSH configuration is valid"
    systemctl restart sshd
    log "SSH service restarted with new configuration"
else
    error "SSH configuration test failed! Reverting changes..."
    rm -f /etc/ssh/sshd_config.d/99-hardening.conf
    exit 1
fi

################################################################################
# 25. Optimize tmpfs
################################################################################
log "Step 19: Optimizing tmpfs..."

# Check if entries already exist to avoid duplicates
if ! grep -q "tmpfs /tmp" /etc/fstab; then
    cat >> /etc/fstab <<EOF
tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=1G 0 0
tmpfs /var/tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=512M 0 0
EOF
fi

################################################################################
# 24. Disable Unnecessary Services
################################################################################
log "Step 20: Disabling unnecessary services..."

SERVICES_TO_DISABLE=(
    "bluetooth.service"
    "cups.service"
    "avahi-daemon.service"
)

for service in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl is-enabled "$service" &>/dev/null; then
        systemctl disable "$service" &>/dev/null || true
        systemctl stop "$service" &>/dev/null || true
        log "Disabled $service"
    fi
done

################################################################################
# 25. I/O Scheduler Optimization
################################################################################
log "Step 21: Optimizing I/O scheduler..."

cat > /etc/udev/rules.d/60-ioschedulers.conf <<'EOF'
# I/O Scheduler optimization for VPS environments

# NVMe drives - use 'none' scheduler (best for NVMe)
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/nr_requests}="1024"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/read_ahead_kb}="256"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/rq_affinity}="2"

# SSD drives - use 'mq-deadline' scheduler (best for SATA SSD)
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/nr_requests}="512"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/read_ahead_kb}="128"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/rq_affinity}="2"

# HDD drives - use 'bfq' scheduler (best for rotational drives)
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/read_ahead_kb}="256"
EOF

# Reload udev rules
udevadm control --reload-rules
udevadm trigger

log "I/O scheduler optimized"

################################################################################
# 26. CPU Governor Optimization
################################################################################
log "Step 22: Optimizing CPU governor..."

# Install cpufrequtils for CPU frequency management
safe_install cpufrequtils linux-cpupower

# Set CPU governor to 'schedutil' (balance between performance and power efficiency)
# For VPN servers, 'schedutil' provides good balance - responsive when needed, efficient when idle
if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
    log "Setting CPU governor to 'schedutil' for optimal VPN performance..."

    # Create systemd service to set governor on boot
    cat > /etc/systemd/system/cpu-governor.service <<'CPUGOV'
[Unit]
Description=Set CPU Governor to schedutil
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "schedutil" > \$cpu 2>/dev/null || true; done'

[Install]
WantedBy=multi-user.target
CPUGOV

    # Enable and start the service
    systemctl daemon-reload
    systemctl enable cpu-governor.service
    systemctl start cpu-governor.service

    # Also set it now
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "schedutil" > $cpu 2>/dev/null || true
    done

    log "CPU governor set to 'schedutil'"
else
    warn "CPU frequency scaling not available (virtual CPU or governor not supported)"
fi

################################################################################
# 27. System Limits Optimization
################################################################################
log "Step 23: Optimizing system limits..."

# Backup existing limits.conf
cp /etc/security/limits.conf /etc/security/limits.conf.backup.$(date +%F) 2>/dev/null || true

# Add optimized limits for VPN server
cat >> /etc/security/limits.conf <<'LIMITS'

# ============================================================================
# VPS Optimization - System Limits for VPN Server (1-4GB RAM)
# ============================================================================

# Open file limits (moderate for low RAM VPS)
*               soft    nofile          262144
*               hard    nofile          262144
root            soft    nofile          262144
root            hard    nofile          262144

# Process limits
*               soft    nproc           16384
*               hard    nproc           16384

# Memory lock (for VPN encryption)
*               soft    memlock         unlimited
*               hard    memlock         unlimited

LIMITS

log "System limits optimized"

################################################################################
# 24. Create Monitoring Script
################################################################################
log "Step 22: Creating monitoring script..."

cat > /usr/local/bin/vps-monitor.sh <<'SCRIPT'
#!/bin/bash

echo "=== VPS System Monitor ==="
echo ""

echo "=== System Info ==="
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime -p)"
echo "Kernel: $(uname -r)"
echo ""

echo "=== CPU Usage ==="
top -bn1 | head -n 5
echo ""

# Show CPU governor if available
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    echo "CPU Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'N/A')"
    echo "CPU Frequency: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null | awk '{printf "%.2f GHz", $1/1000000}' || echo 'N/A')"
fi

echo ""
echo "=== Memory Usage ==="
free -h

echo ""
echo "=== Disk Usage ==="
df -h | grep -v tmpfs

echo ""
echo "=== I/O Scheduler & Disk Info ==="
for disk in /sys/block/sd? /sys/block/nvme?n?; do
    if [ -e "$disk" ]; then
        device=$(basename $disk)
        scheduler=$(cat $disk/queue/scheduler 2>/dev/null | grep -oP '\[\K[^\]]+' || echo 'N/A')
        rotational=$(cat $disk/queue/rotational 2>/dev/null)
        if [ "$rotational" = "0" ]; then
            disk_type="SSD/NVMe"
        else
            disk_type="HDD"
        fi
        echo "$device: $disk_type, Scheduler: $scheduler"
    fi
done

echo ""
echo "=== Network Performance ==="
echo "TCP Congestion Control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'N/A')"
echo "Default Qdisc: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo 'N/A')"
echo "IP Forwarding (VPN): $(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 'N/A')"

echo ""
echo "=== Network Connections ==="
ss -s

echo ""
echo "=== Memory Parameters ==="
echo "Swappiness: $(sysctl -n vm.swappiness 2>/dev/null || echo 'N/A')"
echo "VFS Cache Pressure: $(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo 'N/A')"

echo ""
echo "=== Load Average ==="
uptime

echo ""
echo "=== Top 5 Processes by Memory ==="
ps aux --sort=-%mem | head -6

echo ""
echo "=== Top 5 Processes by CPU ==="
ps aux --sort=-%cpu | head -6

echo ""
echo "=== Swap Usage ==="
swapon --show

echo ""
echo "=== Active VPN Connections (if any) ==="
# Check for common VPN interfaces
if ip link show | grep -qE 'tun|wg|ppp'; then
    ip -s link show | grep -A 2 -E 'tun|wg|ppp'
else
    echo "No VPN interfaces detected"
fi

SCRIPT

chmod +x /usr/local/bin/vps-monitor.sh

################################################################################
# 21. Create Cleanup Script
################################################################################
log "Step 23: Creating cleanup script..."

cat > /usr/local/bin/vps-cleanup.sh <<'SCRIPT'
#!/bin/bash

echo "Starting VPS cleanup..."

# Clean package cache
apt-get clean
apt-get autoclean
apt-get autoremove -y

# Clean journal logs older than 7 days
journalctl --vacuum-time=7d

# Clean old kernels (keep current + 1)
dpkg -l 'linux-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | head -n -1 | xargs apt-get -y purge 2>/dev/null || true

# Clean temp files older than 7 days
find /tmp -type f -atime +7 -delete 2>/dev/null || true
find /var/tmp -type f -atime +7 -delete 2>/dev/null || true

# Clean thumbnail cache if exists
rm -rf ~/.cache/thumbnails/* 2>/dev/null || true

echo "Cleanup completed!"
SCRIPT

chmod +x /usr/local/bin/vps-cleanup.sh

# Create weekly cron job for cleanup
cat > /etc/cron.weekly/vps-cleanup <<'EOF'
#!/bin/bash
/usr/local/bin/vps-cleanup.sh >> /var/log/vps-cleanup.log 2>&1
EOF

chmod +x /etc/cron.weekly/vps-cleanup

################################################################################
# 24. Network Performance Test Script
################################################################################
log "Step 24: Creating network performance test script..."

cat > /usr/local/bin/network-test.sh <<'SCRIPT'
#!/bin/bash

echo "=== Network Performance Test ==="
echo ""
echo "Testing network speed with speedtest-cli..."

if ! command -v speedtest-cli &> /dev/null; then
    echo "Installing speedtest-cli..."
    safe_install speedtest-cli
fi

speedtest-cli

echo ""
echo "=== Network Statistics ==="
netstat -s | head -20
SCRIPT

chmod +x /usr/local/bin/network-test.sh

################################################################################
# 23. System Information Script
################################################################################
log "Step 25: Creating system information script..."

cat > /usr/local/bin/vps-info.sh <<'SCRIPT'
#!/bin/bash

echo "=== VPS System Information ==="
echo ""
echo "Hostname: $(hostname)"
echo "OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"
echo ""

# CPU Detection with fallback
CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d':' -f2 | xargs)
if [ -z "$CPU_MODEL" ]; then
    # Fallback for systems without "model name" (ARM, some VPS)
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
fi
if [ -z "$CPU_MODEL" ]; then
    # Final fallback - show CPU architecture
    CPU_MODEL=$(lscpu | grep "Architecture" | cut -d':' -f2 | xargs)
fi

echo "CPU: ${CPU_MODEL:-Unknown}"
echo "CPU Cores: $(nproc)"
echo "Architecture: $(uname -m)"
echo ""
echo "Total RAM: $(free -h | awk '/^Mem:/ {print $2}')"
echo "Used RAM: $(free -h | awk '/^Mem:/ {print $3}')"
echo "Free RAM: $(free -h | awk '/^Mem:/ {print $4}')"
echo ""
echo "Swap Total: $(free -h | awk '/^Swap:/ {print $2}')"
echo "Swap Used: $(free -h | awk '/^Swap:/ {print $3}')"
echo ""
echo "Disk Usage:"
df -h / | tail -1
echo ""
PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null || echo "Unable to detect")
echo "Public IP: $PUBLIC_IP"
echo ""
echo "Active Firewall Rules:"
ufw status numbered
echo ""
echo "TCP Congestion Control: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "Swappiness: $(sysctl -n vm.swappiness)"
echo ""
if command -v docker &> /dev/null; then
    echo "Docker Version: $(docker --version 2>/dev/null || echo 'Not available')"
    echo "Docker Compose: $(docker compose version 2>/dev/null || echo 'Not available')"
    echo "Docker Status: $(systemctl is-active docker 2>/dev/null || echo 'Not running')"
fi
SCRIPT

chmod +x /usr/local/bin/vps-info.sh

################################################################################
# Final Summary
################################################################################
echo ""
echo "================================================================================"
log "=== VPS Optimization Complete ==="
echo "================================================================================"
echo ""
log "Summary of optimizations:"
log "  ✓ OS detected: $OS_NAME $OS_VERSION ($OS_CODENAME)"
log "  ✓ Locale: $DEFAULT_LOCALE (will apply after reboot)"
log "  ✓ Hostname: $(hostname)"
# Get timezone for display with fallback
if command -v timedatectl >/dev/null 2>&1; then
    SUMMARY_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null)
elif [ -L /etc/localtime ]; then
    SUMMARY_TZ=$(readlink /etc/localtime | sed 's|/usr/share/zoneinfo/||')
else
    SUMMARY_TZ="Unknown"
fi
log "  ✓ Timezone: $SUMMARY_TZ"
log "  ✓ Zsh + Starship installed for root and $NEW_USER"
log "  ✓ Starship with Unicode icons"
log "  ✓ Autosuggestions plugin"
log "  ✓ Syntax highlighting"
log "  ✓ Zsh completions with plugins"
log "  ✓ New user created: $NEW_USER (with sudo + docker access, passwordless)"
log "  ✓ SSH keys configured for $NEW_USER"
log "  ✓ System updated and essential packages installed"
log "  ✓ Docker & Docker Compose installed (latest version)"
log "  ✓ User $NEW_USER added to docker group (no sudo needed for docker)"
log "  ✓ Kernel parameters optimized (BBR enabled)"
if [ "$XANMOD_INSTALLED" = true ]; then
    log "  ✓ XanMod kernel installed ($XANMOD_VARIANT)"
else
    log "  ✗ XanMod kernel not installed (incompatible architecture)"
fi
log "  ✓ Swap configured (${SWAP_SIZE}GB, swappiness=$SWAPPINESS)"
log "  ✓ Firewall (UFW) enabled with SSH, HTTP, HTTPS"
log "  ✓ Fail2Ban configured for SSH protection"
log "  ✓ System limits increased"
log "  ✓ Automatic security updates enabled"
log "  ✓ Journal logs limited to 500MB"
log "  ✓ SSH hardened (root login disabled, only key auth)"
log "  ✓ tmpfs optimized"
log "  ✓ I/O scheduler optimized"
log "  ✓ Unnecessary services disabled"
echo ""
log "Created utility scripts:"
log "  • vps-monitor.sh   - System monitoring"
log "  • vps-cleanup.sh   - System cleanup (runs weekly)"
log "  • vps-info.sh      - System information"
log "  • network-test.sh  - Network performance test"
echo ""
log "Security Configuration:"
log "  • Root login: DISABLED"
log "  • Password authentication: DISABLED"
log "  • SSH key authentication: ENABLED (for $NEW_USER only)"
log "  • Passwordless sudo: ENABLED (for $NEW_USER and root)"
log "  • SSH port: 22"
echo ""
warn "================================================================================"
warn "CRITICAL: Before disconnecting, verify SSH access:"
warn "  1. Open a new terminal (don't close this one!)"
warn "  2. Test login: ssh $NEW_USER@$(hostname -I | awk '{print $1}')"
warn "  3. Test sudo: sudo -l (should work without password)"
warn "  4. Only disconnect current session after successful test!"
warn "================================================================================"
echo ""
info "System Information:"
/usr/local/bin/vps-info.sh
echo ""
echo "================================================================================"
warn "A system reboot is REQUIRED to activate all changes:"
warn "  • Locale settings ($DEFAULT_LOCALE)"
if [ "$XANMOD_INSTALLED" = true ]; then
    warn "  • XanMod kernel ($XANMOD_VARIANT)"
fi
warn "  • Docker group membership for $NEW_USER"
warn "  • Zsh shell with all plugins"
echo "================================================================================"
echo ""
read -p "Do you want to reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Rebooting system in 5 seconds... Press Ctrl+C to cancel"
    sleep 5
    reboot
else
    log "Reboot skipped. Please reboot manually when ready with: sudo reboot"
    echo ""
    warn "After reboot:"
    warn "  • Check kernel version: uname -r"
    if [ "$XANMOD_INSTALLED" = true ]; then
        warn "    (should contain 'xanmod')"
    fi
    warn "  • Verify locale: locale"
    warn "  • Test Zsh: zsh (should show colors and autosuggestions)"
    warn "  • Test Docker: docker ps (should work without sudo)"
fi
