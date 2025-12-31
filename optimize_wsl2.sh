#!/bin/bash

# Force C locale for script execution to avoid locale-related issues
export LC_ALL=C
export LANG=C

################################################################################
# WSL2 Optimization Script for Debian 12/13 (Bookworm/Trixie)
# Purpose: Complete WSL2 optimization with modern Zsh + Starship setup
# Features: WSL2-specific configs, systemd, Docker, NVIDIA/CUDA support, performance tuning
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
LOG_FILE="/var/log/wsl2_optimization.log"

# Helper functions
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

section() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# WSL2 detection functions
is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]
}

has_systemd() {
    command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

has_user_systemd() {
    systemctl --user show-environment >/dev/null 2>&1
}

sudo_or_su() {
    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        su -c "$*"
    fi
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Verify WSL2 environment
if ! is_wsl; then
    warn "This script is designed for WSL2 environment."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

log "=== Starting WSL2 Optimization for Debian 12/13 ==="

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
# 2. Interactive Configuration Menu
################################################################################

# Default configuration flags
CONFIGURE_WSL_CONF=true
UPDATE_SYSTEM=true
INSTALL_BASE_UTILS=true
CREATE_USER=false
CONFIGURE_LOCALES=true
INSTALL_ZSH=true
INSTALL_DOCKER=true
INSTALL_NVIDIA=false
INSTALL_CUDA=false
CONFIGURE_SSH_AGENT=true
ENABLE_AUTO_UPDATES=true
PERFORMANCE_TUNING=true

# Interactive menu
show_menu() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Step 2: Configuration Selection${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Before starting, ensure in PowerShell:${NC}"
    echo -e "${YELLOW}1) wsl --update; 2) wsl --set-default-version 2;${NC}"
    echo -e "${YELLOW}3) Check C:\\Users\\<USER>\\.wslconfig (RAM/CPU settings).${NC}"
    echo ""

    prompt_yn() {
        local prompt="$1" default_yes="$2"; local ans
        if $default_yes; then
            read -p " - $prompt [Y/n]: " ans
            case "$ans" in n|N) return 1;; *) return 0;; esac
        else
            read -p " - $prompt [y/N]: " ans
            case "$ans" in y|Y) return 0;; *) return 1;; esac
        fi
    }

    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  CONFIGURATION OPTIONS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    # System configuration
    prompt_yn "Configure WSL2 (wsl.conf with systemd)" true && CONFIGURE_WSL_CONF=true || CONFIGURE_WSL_CONF=false
    prompt_yn "Update system packages" true && UPDATE_SYSTEM=true || UPDATE_SYSTEM=false
    prompt_yn "Install base utilities (git, curl, htop, etc.)" true && INSTALL_BASE_UTILS=true || INSTALL_BASE_UTILS=false
    prompt_yn "Create new user with sudo rights" false && CREATE_USER=true || CREATE_USER=false
    prompt_yn "Configure locales (ru_RU, en_US)" true && CONFIGURE_LOCALES=true || CONFIGURE_LOCALES=false

    echo ""
    # Shell and development
    prompt_yn "Install Zsh + Starship (replaces Fish)" true && INSTALL_ZSH=true || INSTALL_ZSH=false
    prompt_yn "Configure ssh-agent" true && CONFIGURE_SSH_AGENT=true || CONFIGURE_SSH_AGENT=false

    echo ""
    # Containerization
    prompt_yn "Install Docker CE" true && INSTALL_DOCKER=true || INSTALL_DOCKER=false
    if prompt_yn "Install NVIDIA Container Toolkit + CUDA support" false; then
        INSTALL_NVIDIA=true
        if prompt_yn "  → Install full CUDA Toolkit" true; then
            INSTALL_CUDA=true
        else
            INSTALL_CUDA=false
        fi
    else
        INSTALL_NVIDIA=false
        INSTALL_CUDA=false
    fi

    echo ""
    # System optimization
    prompt_yn "Enable automatic security updates" true && ENABLE_AUTO_UPDATES=true || ENABLE_AUTO_UPDATES=false
    prompt_yn "Apply performance tuning" true && PERFORMANCE_TUNING=true || PERFORMANCE_TUNING=false

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Starting installation with selected options...${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Show menu
show_menu

################################################################################
# 3. WSL2 Configuration
################################################################################
section "Step 3: WSL2 Configuration"

if $CONFIGURE_WSL_CONF; then
    log "Configuring /etc/wsl.conf with systemd and optimizations..."
    
    # Backup existing wsl.conf
    if [ -f /etc/wsl.conf ]; then
        cp /etc/wsl.conf "/etc/wsl.conf.backup.$(date +%F)" || true
    fi

    # Create optimized wsl.conf
    cat > /etc/wsl.conf <<'EOF'
[boot]
# Enable systemd for better service management
# systemd allows Docker to auto-start via service configuration
systemd=true

[automount]
# Enable metadata for proper file permissions
enabled=true
# Mount Windows drives to /mnt (standard WSL behavior)
# C: will be /mnt/c, D: will be /mnt/d, etc.
root=/mnt
# Combined options: metadata for permissions, case sensitivity, umask for directories
# Note: fmask removed to allow Windows executables (like VSCode scripts) to work
options="metadata,case=dir,umask=022"

[network]
# Generate hosts file for local development
generateHosts=true
# Custom hostname (will be set below)
hostname=debian-wsl

[interop]
# Enable Windows process integration
enabled=true
# Append Windows PATH for better tool access
appendWindowsPath=true

[user]
# Default user - login with this user instead of root
# Will be set to the created user, or leave empty to login as root
default=
EOF

    log "WSL2 configuration updated"
    info "After script completion, run 'wsl --shutdown' in Windows to apply changes"
else
    log "Skipping WSL2 configuration"
fi

################################################################################
# 4. System Update and Base Packages
################################################################################
section "Step 4: System Update and Base Packages"

if $UPDATE_SYSTEM; then
    log "Updating system packages..."
    
    # Enrich APT components
    enrich_apt_components() {
        local f="$1"; [ -f "$f" ] || return 0
        sed -i -E '/^\s*deb\s/ { /non-free-firmware/! s/(^deb\s+[^#]*\bmain)(\s|$)/\1 contrib non-free non-free-firmware\2/ }' "$f"
    }
    
    enrich_apt_components "/etc/apt/sources.list"
    for f in /etc/apt/sources.list.d/*.list; do 
        [ -e "$f" ] && enrich_apt_components "$f"
    done
    
    # Update package lists
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    
    log "System updated successfully"
else
    log "Skipping system update"
fi

if $INSTALL_BASE_UTILS; then
    log "Installing base utilities..."
    
    # Define packages array for easier management
    base_packages=(
        "curl"
        "wget"
        "git"
        "htop"
        "iotop"
        "sysstat"
        "net-tools"
        "build-essential"
        "cmake"
        "make"
        "gcc"
        "g++"
        "python3"
        "python3-pip"
        "python3-venv"
        "fzf"
        "ripgrep"
        "fd-find"
        "tree"
        "jq"
        "bat"
        "unzip"
        "zip"
        "tar"
        "xz-utils"
        "gnupg"
        "ca-certificates"
        "lsb-release"
        "apt-transport-https"
        "xdg-user-dirs"
        # "fastfetch"  # Commented out - may not be available in Debian 13
        "bc"
    )
    
    safe_install "${base_packages[@]}"

    # Create aliases for Debian naming
    if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
        ln -sf "$(command -v batcat)" /usr/local/bin/bat || true
    fi
    
    if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
        ln -sf "$(command -v fdfind)" /usr/local/bin/fd || true
    fi
    
    log "Base utilities installed"
else
    log "Skipping base utilities installation"
fi

################################################################################
# 5. User Creation
################################################################################
section "Step 5: User Management"

NEW_USER=""
if $CREATE_USER; then
    read -p "Enter new username: " NEW_USER
    
    if [ -z "$NEW_USER" ]; then
        warn "Username cannot be empty! Skipping user creation."
        CREATE_USER=false
    else
        if id "$NEW_USER" &>/dev/null; then
            warn "User $NEW_USER already exists. Skipping creation but will configure..."
            # Offer to change password for existing user
            read -p "Do you want to change password for existing user $NEW_USER? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                passwd "$NEW_USER" && log "Password changed for $NEW_USER" || warn "Failed to change password"
            fi

            # Ensure user is in sudo group
            if ! groups "$NEW_USER" | grep -q sudo; then
                usermod -aG sudo "$NEW_USER"
                log "Added $NEW_USER to sudo group"
            fi
        else
            # Create user
            adduser --gecos "" --disabled-password "$NEW_USER" || {
                error "Failed to create user $NEW_USER"
                CREATE_USER=false
            }
            if [ $CREATE_USER = true ]; then
                usermod -aG sudo "$NEW_USER"
                log "User $NEW_USER created and added to sudo group"

                # Set password for new user
                log "Setting password for new user $NEW_USER..."
                passwd "$NEW_USER" || warn "Failed to set password"
            fi
        fi

        # Only configure if user was created/configured successfully
        if [ $CREATE_USER = true ]; then
            # Configure passwordless sudo
            echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$NEW_USER
            chmod 440 /etc/sudoers.d/$NEW_USER
            log "Passwordless sudo configured for $NEW_USER"

            # Verify user home directory exists
            USER_HOME=$(eval echo ~$NEW_USER)
            if [ ! -d "$USER_HOME" ]; then
                warn "User home directory $USER_HOME does not exist, creating..."
                mkdir -p "$USER_HOME"
                chown -R "$NEW_USER:$NEW_USER" "$USER_HOME"
                chmod 700 "$USER_HOME"
            fi

            # Update wsl.conf with default user
            if $CONFIGURE_WSL_CONF; then
                sed -i "s/^default=.*/default=$NEW_USER/" /etc/wsl.conf
                log "Set $NEW_USER as default user in wsl.conf"
                info "Default user will apply after WSL restart (wsl --shutdown)"
            fi

            # Store for later use
            DOCKER_USER=$NEW_USER
        fi
    fi
else
    # Use current user or default
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
        DOCKER_USER="$SUDO_USER"
    else
        DOCKER_USER="$(logname 2>/dev/null || whoami)"
    fi
    log "Using existing user: $DOCKER_USER"
fi

################################################################################
# 6. Locale Configuration
################################################################################
section "Step 6: System Localization"

if $CONFIGURE_LOCALES; then
    log "Configuring system locales..."
    
    # Install locales package with availability check
    safe_install locales
    
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
            ;;
        2)
            LOCALE_TO_GENERATE="ru_RU.UTF-8"
            DEFAULT_LOCALE="ru_RU.UTF-8"
            ;;
        3)
            LOCALE_TO_GENERATE="en_US.UTF-8 ru_RU.UTF-8"
            DEFAULT_LOCALE="en_US.UTF-8"
            ;;
        *)
            warn "Invalid choice. Using English (en_US.UTF-8) as default"
            LOCALE_TO_GENERATE="en_US.UTF-8"
            DEFAULT_LOCALE="en_US.UTF-8"
            ;;
    esac
    
    # Generate locales
    for locale in $LOCALE_TO_GENERATE; do
        if ! grep -q "^${locale} UTF-8" /etc/locale.gen 2>/dev/null && ! grep -q "^# ${locale} UTF-8" /etc/locale.gen 2>/dev/null; then
            echo "${locale} UTF-8" >> /etc/locale.gen
        fi
        sed -i "s/^# *\(${locale} UTF-8\)/\1/" /etc/locale.gen
    done

    # Generate locales with C.UTF-8 to avoid LC_ALL=C conflicts
    unset LC_ALL
    unset LANG
    export LC_ALL=C.UTF-8
    export LANG=C.UTF-8
    /usr/sbin/locale-gen
    unset LC_ALL
    unset LANG

    # Update locale configuration file
    cat > /etc/default/locale <<EOF
LANG=$DEFAULT_LOCALE
LANGUAGE=${DEFAULT_LOCALE%%.*}
LC_ALL=$DEFAULT_LOCALE
EOF

    # Write to profile for all users (will be sourced on login)
    cat > /etc/profile.d/locale.sh <<EOF
export LANG=$DEFAULT_LOCALE
export LC_ALL=$DEFAULT_LOCALE
export LANGUAGE=${DEFAULT_LOCALE%%.*}
EOF

    chmod +x /etc/profile.d/locale.sh

    # DO NOT export locale in current session - it may not be fully ready
    # Wait for restart for locale to be properly applied
    log "Locale configured: $DEFAULT_LOCALE"
    info "Locale will be fully applied after WSL restart"
else
    log "Skipping locale configuration"
fi

################################################################################
# 7. Zsh and Starship Installation
################################################################################
section "Step 7: Zsh + Starship Installation"

if $INSTALL_ZSH; then
    log "Installing Zsh and Starship..."
    
    # Install Zsh with availability check
    safe_install zsh git curl
    
    # Install Starship
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
        fi
        
        # Install zsh-syntax-highlighting
        if [ ! -d "$user_home/.zsh/zsh-syntax-highlighting" ]; then
            git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$user_home/.zsh/zsh-syntax-highlighting"
        fi
        
        # Install zsh-completions
        if [ ! -d "$user_home/.zsh/zsh-completions" ]; then
            git clone https://github.com/zsh-users/zsh-completions "$user_home/.zsh/zsh-completions"
        fi
        
        # Create .zshrc with WSL2-optimized configuration
        cat > "$user_home/.zshrc" <<'ZSHRC'
# WSL2 Optimized Zsh Configuration

# Fix VSCode Remote WSL terminal error with __vsc_update_env
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

# WSL2-specific environment variables
export EDITOR='code'
export VISUAL='code'
export BROWSER="/mnt/c/Windows/System32/cmd.exe /c start"
export DISPLAY=":0"

# Path optimization for WSL
export PATH="/usr/local/bin:/usr/bin:$PATH"
export PATH="/mnt/c/Windows/System32:$PATH"

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

# WSL2-specific functions
explorer() {
    explorer.exe $(wslpath -w "$1")
}

cmd() {
    cmd.exe /c "$*"
}

powershell() {
    powershell.exe -Command "$*"
}

wslperf() {
    echo "=== WSL Performance ==="
    echo "Memory: $(free -h | grep '^Mem:' | awk '{print $3"/"$7}')"
    echo "CPU: $(top -bn1 | grep 'Cpu(s):' | awk '{print $2}')"
    echo "Disk: $(df -h / | tail -1)"
}

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

# Initialize Starship prompt
eval "$(starship init zsh)"
ZSHRC

        # Compile .zshrc for faster loading (~50-100ms improvement)
        if [ "$username" = "root" ]; then
            zsh -c "zcompile $user_home/.zshrc" 2>/dev/null || true
        else
            su - "$username" -c "zsh -c 'zcompile ~/.zshrc'" 2>/dev/null || true
        fi

        # Create Starship config with WSL2 optimizations
        mkdir -p "$user_home/.config"

        cat > "$user_home/.config/starship.toml" <<'STARSHIP'
# Starship configuration - Modern & Clean
# WSL2 Optimized for ML/AI Development

command_timeout = 500
scan_timeout = 30
add_newline = true

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
        
        # Set correct ownership
        chown -R $username:$username "$user_home/.zshrc" "$user_home/.zsh" "$user_home/.config" 2>/dev/null || true
        
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

    # Setup Zsh for new user if created
    if [ -n "$NEW_USER" ]; then
        setup_zsh_for_user $NEW_USER
    fi

    # Setup Zsh for docker user
    if [ -n "$DOCKER_USER" ] && [ "$DOCKER_USER" != "root" ] && [ "$DOCKER_USER" != "$NEW_USER" ]; then
        setup_zsh_for_user $DOCKER_USER
    fi

    log "Zsh + Starship configuration completed"
else
    log "Skipping Zsh installation"
fi

################################################################################
# 8. Go Installation (Latest Version)
################################################################################
section "Step 8: Go Installation"

log "Installing Go (latest stable version)..."

# Install Go using curl and SHA256 verification
install_go() {
    local go_version
    local go_arch
    local go_os="linux"
    local go_download_url
    local go_checksum_url
    local go_expected_checksum
    local go_actual_checksum
    local temp_dir

    # Detect architecture
    go_arch=$(uname -m)
    case $go_arch in
        x86_64)
            go_arch="amd64"
            ;;
        aarch64)
            go_arch="arm64"
            ;;
        *)
            warn "Unsupported architecture: $go_arch"
            return 1
            ;;
    esac

    log "Detected architecture: $go_arch"

    # Get latest Go version
    log "Fetching latest Go version..."
    go_version=$(curl -s https://go.dev/VERSION?m=text | head -1 | sed 's/go//')

    if [ -z "$go_version" ]; then
        go_version="1.25.4"  # fallback version
        warn "Could not determine latest Go version, using fallback: $go_version"
    fi

    log "Latest Go version: $go_version"

    # Build download URL
    # Use dl.google.com for direct downloads (go.dev redirects and causes issues)
    go_download_url="https://dl.google.com/go/go${go_version}.${go_os}-${go_arch}.tar.gz"
    go_checksum_url="https://dl.google.com/go/go${go_version}.${go_os}-${go_arch}.tar.gz.sha256"

    # Create temporary directory
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    # Download checksum
    log "Downloading Go checksum..."
    if ! curl -fsSL "$go_checksum_url" -o "$temp_dir/checksum.txt"; then
        warn "Failed to download Go checksum"
        return 1
    fi

    go_expected_checksum=$(cut -d' ' -f1 "$temp_dir/checksum.txt")
    log "Expected checksum: $go_expected_checksum"

    # Download Go
    log "Downloading Go ${go_version} for ${go_arch}..."
    if ! curl -fsSL "$go_download_url" -o "$temp_dir/go.tar.gz"; then
        warn "Failed to download Go"
        return 1
    fi

    # Verify checksum
    log "Verifying Go checksum..."
    cd "$temp_dir"
    if ! echo "$go_expected_checksum  go.tar.gz" | sha256sum -c - >/dev/null 2>&1; then
        warn "Go checksum verification failed"
        return 1
    fi
    cd - >/dev/null

    log "Checksum verified successfully"

    # Remove old Go if exists
    if [ -d "/usr/local/go" ]; then
        log "Removing old Go installation..."
        rm -rf /usr/local/go
    fi

    # Extract and install Go
    log "Installing Go to /usr/local/go..."
    tar -C /usr/local -xzf "$temp_dir/go.tar.gz"

    # Add Go to PATH for all users via profile.d
    cat > /etc/profile.d/golang.sh <<'GOEOF'
export PATH=/usr/local/go/bin:$PATH
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$PATH
GOEOF
    chmod +x /etc/profile.d/golang.sh

    # Also add to Zsh configs if they exist
    add_go_to_zshrc() {
        local zshrc_path=$1
        if [ -f "$zshrc_path" ]; then
            if ! grep -q "golang" "$zshrc_path"; then
                cat >> "$zshrc_path" <<'ZSHEOF'

# Go environment (install-go-latest)
export PATH=/usr/local/go/bin:$PATH
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$PATH
ZSHEOF
                log "Added Go configuration to $zshrc_path"
            fi
        fi
    }

    # Add to root's .zshrc
    add_go_to_zshrc "/root/.zshrc"

    # Add to regular user's .zshrc if exists
    if [ -n "$NEW_USER" ] && $CREATE_USER; then
        user_home=$(eval echo ~$NEW_USER)
        add_go_to_zshrc "$user_home/.zshrc"
    fi

    # Source it for current session
    export PATH=/usr/local/go/bin:$PATH
    export GOPATH=$HOME/go
    export PATH=$GOPATH/bin:$PATH

    log "Go ${go_version} installed successfully"
    /usr/local/go/bin/go version
}

install_go || warn "Go installation failed, continuing..."

################################################################################
# 9. Node.js Installation with NVM
################################################################################
section "Step 9: Node.js Installation (NVM + Latest LTS)"

log "Installing NVM and Node.js LTS..."

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

    # Create .zshrc addition for NVM if using Zsh
    if [ -f "$user_home/.zshrc" ]; then
        if ! grep -q "nvm/nvm.sh" "$user_home/.zshrc"; then
            log "Adding NVM to $username .zshrc..."
            cat >> "$user_home/.zshrc" <<'NVMEOF'

# NVM initialization
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
NVMEOF
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
install_nvm_for_user "root" || warn "NVM installation for root failed"

# Install NVM for regular user if created
if [ -n "$NEW_USER" ] && $CREATE_USER; then
    install_nvm_for_user "$NEW_USER" || warn "NVM installation for $NEW_USER failed"
fi

log "Node.js and NVM installation completed"

################################################################################
# 10. SSH Agent Configuration
################################################################################
section "Step 10: SSH Agent Configuration"

if $CONFIGURE_SSH_AGENT; then
    log "Configuring SSH agent for WSL2..."
    
    # Install openssh-client with availability check
    safe_install openssh-client
    
    if has_user_systemd; then
        log "Enabling ssh-agent.socket via systemd..."
        systemctl --user enable --now ssh-agent.socket || warn "Failed to enable ssh-agent.socket"
    else
        log "Configuring ssh-agent via profile..."
        
        PROFILE_SNIPPET='# WSL2: автозапуск ssh-agent (без systemd)
if ! pgrep -u "$USER" ssh-agent >/dev/null 2>&1; then
  eval "$(ssh-agent -s)" >/dev/null
fi
'
        
        for f in "/home/$DOCKER_USER/.bash_profile" "/home/$DOCKER_USER/.profile" "/home/$DOCKER_USER/.zprofile"; do
            [ -f "$f" ] || touch "$f"
            if ! grep -F "WSL2: автозапуск ssh-agent" "$f" >/dev/null 2>&1; then
                printf "%b\n" "$PROFILE_SNIPPET" >>"$f"
                log "Added ssh-agent autostart to ${f##*/}"
            fi
        done
    fi
    
    log "SSH agent configuration completed"
else
    log "Skipping SSH agent configuration"
fi

################################################################################
# 11. Docker Installation
################################################################################
section "Step 11: Docker Installation"

if $INSTALL_DOCKER; then
    log "Installing Docker CE..."

    # Remove old Docker versions
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        apt-get remove -y $pkg 2>/dev/null || true
    done

    # Switch to iptables-legacy on Debian 13 (nftables is incompatible with Docker)
    log "Configuring iptables-legacy for Docker compatibility..."
    safe_install iptables

    # Switch ALL iptables utilities to legacy mode (critical for UFW)
    # Set master alternatives first
    update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 100
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-legacy 100
    # Set slave alternatives (iptables-restore and iptables-save are automatically managed)
    update-alternatives --set iptables-save /usr/sbin/iptables-legacy-save 2>/dev/null || true
    update-alternatives --set ip6tables-save /usr/sbin/ip6tables-legacy-save 2>/dev/null || true

    log "iptables switched to legacy mode (all utilities) for compatibility"

    # Install prerequisites
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID \
      $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    log "Updating package list for Docker repository..."
    apt-get update >/dev/null 2>&1 || warn "Warning: Failed to update package list for Docker"

    # Install Docker Engine with availability check
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

    # Configure Docker daemon for WSL2
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

    # Enable and start Docker service
    if has_systemd; then
        # Clean up any stale Docker processes and PID file
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

        systemctl daemon-reload
        systemctl enable docker
        systemctl enable docker.socket
        systemctl start docker.socket
        systemctl start docker
        log "Docker service enabled and started"

        # Ensure docker group exists
        groupadd -f docker

        # Fix docker.sock permissions
        sleep 1
        if [ -S /var/run/docker.sock ]; then
            chown root:docker /var/run/docker.sock
            chmod 660 /var/run/docker.sock
            log "Docker socket permissions fixed"
        fi
    else
        warn "systemd not available - Docker will need to be started manually"
    fi

    # Add user to docker group
    if [ -n "$DOCKER_USER" ]; then
        usermod -aG docker "$DOCKER_USER"
        log "User $DOCKER_USER added to docker group"
    fi
    
    # Verify Docker installation
    DOCKER_VERSION=$(docker --version 2>/dev/null || echo "Not available")
    COMPOSE_VERSION=$(docker compose version 2>/dev/null || echo "Not available")
    log "Docker installed: $DOCKER_VERSION"
    log "Docker Compose: $COMPOSE_VERSION"
    
else
    log "Skipping Docker installation"
fi

################################################################################
# 12. NVIDIA Container Toolkit and CUDA
################################################################################
section "Step 12: NVIDIA Support Installation"

if $INSTALL_NVIDIA; then
    log "Installing NVIDIA Container Toolkit..."
    
    # Check GPU status
    gpu_status_wsl() {
        local ok_flag=0
        echo "Checking GPU/WSL status:"
        if [ -e /dev/dxg ]; then
            echo " - /dev/dxg: OK (WSL GPU available)"
        else
            echo " - /dev/dxg: Missing (GPU not available in WSL)"
            ok_flag=1
        fi
        if command -v nvidia-smi >/dev/null 2>&1; then
            echo " - nvidia-smi: found"
            nvidia-smi -L || true
        else
            echo " - nvidia-smi: not found in Linux environment"
            ok_flag=1
        fi
        
        if [ $ok_flag -ne 0 ]; then
            warn "GPU may not be available. Installation will continue but may not work properly."
            warn "Tips:"
            warn " - Install latest NVIDIA driver with WSL support"
            warn " - Enable GPU support for your WSL distribution"
            warn " - Run 'wsl --shutdown' after driver update"
        fi
        return $ok_flag
    }
    
    gpu_status_wsl
    
    # Install NVIDIA Container Toolkit
    install -m 0755 -d /usr/share/keyrings
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    ARCH="$(dpkg --print-architecture)"
    echo "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/${ARCH}/ /" | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    safe_install nvidia-container-toolkit

    # Configure NVIDIA runtime - only if Docker is installed
    if command -v nvidia-ctk >/dev/null 2>&1; then
        if command -v docker >/dev/null 2>&1; then
            # Ensure Docker directory exists
            mkdir -p /etc/docker

            # Stop Docker before configuration if running
            if has_systemd; then
                systemctl stop docker 2>/dev/null || true
                sleep 2
            fi

            # Ensure Docker daemon.json is valid JSON (nvidia-ctk needs valid JSON to modify)
            if [ ! -f /etc/docker/daemon.json ]; then
                log "Creating empty Docker daemon.json..."
                echo '{}' > /etc/docker/daemon.json
            fi

            # Validate daemon.json before modifying
            if ! grep -q '{' /etc/docker/daemon.json 2>/dev/null; then
                log "Repairing invalid daemon.json..."
                echo '{}' > /etc/docker/daemon.json
            fi

            # Configure NVIDIA runtime using nvidia-ctk (idempotent, safe to run multiple times)
            log "Configuring NVIDIA Container Runtime..."
            nvidia-ctk runtime configure --runtime=docker 2>&1 | tee -a "$LOG_FILE" | grep -v "^INFO" || {
                warn "nvidia-ctk configuration completed with status: $?"
            }

            # Reload and restart Docker
            if has_systemd; then
                log "Reloading systemd daemon..."
                systemctl daemon-reload 2>/dev/null || true
                sleep 1

                log "Starting Docker service..."
                systemctl start docker 2>/dev/null || true
                sleep 2

                # Check Docker status with retries
                retry_count=0
                max_retries=3
                while [ $retry_count -lt $max_retries ]; do
                    if systemctl is-active docker >/dev/null 2>&1; then
                        log "NVIDIA Container Toolkit configured successfully"
                        break
                    fi
                    retry_count=$((retry_count + 1))
                    if [ $retry_count -lt $max_retries ]; then
                        warn "Docker not ready yet, waiting... ($retry_count/$max_retries)"
                        sleep 2
                    fi
                done

                if [ $retry_count -eq $max_retries ]; then
                    warn "Docker service may not be running - this is not critical for NVIDIA toolkit"
                    info "You can manually restart Docker with: sudo systemctl restart docker"
                fi
            else
                warn "systemd not available - cannot restart Docker automatically"
            fi
        else
            warn "Docker not installed - skipping NVIDIA runtime configuration"
            warn "Install Docker first, then run: sudo nvidia-ctk runtime configure --runtime=docker"
        fi
    else
        warn "nvidia-ctk not found - installation may have failed"
    fi
    
    # Install CUDA Toolkit if requested
    if $INSTALL_CUDA; then
        log "Installing CUDA Toolkit..."

        # Add CUDA repository
        CUDA_REPO_PATH="debian13/x86_64"
        if ! curl -fsI "https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_REPO_PATH}/" >/dev/null 2>&1; then
            log "CUDA repo for debian13 unavailable, using debian12"
            CUDA_REPO_PATH="debian12/x86_64"
        fi

        CUDA_KEY_URL="https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_REPO_PATH}/3bf863cc.pub"
        if curl -fsSL "$CUDA_KEY_URL" | gpg --dearmor -o /usr/share/keyrings/cuda-archive-keyring.gpg 2>/dev/null; then
            log "CUDA GPG key imported"
        else
            warn "Failed to import CUDA GPG key, continuing anyway..."
        fi

        echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_REPO_PATH}/ /" | \
            tee /etc/apt/sources.list.d/cuda-${CUDA_REPO_PATH//\//-}.list > /dev/null

        log "Updating package list for CUDA repository..."
        apt-get update >/dev/null 2>&1 || warn "Failed to update package list"

        # Install CUDA packages
        # Try to install cuda-toolkit metapackage first, fall back to individual components
        if apt-cache search cuda | grep -q "^cuda-toolkit"; then
            log "Found cuda-toolkit metapackage, installing..."
            safe_install cuda-toolkit 2>/dev/null || {
                log "cuda-toolkit metapackage not available, trying cuda package..."
                if apt-cache search "^cuda " | grep -q "^cuda "; then
                    safe_install cuda
                    log "CUDA Toolkit installed (cuda metapackage)"
                else
                    warn "No CUDA toolkit packages found - CUDA repository may not be properly configured"
                fi
            }
        elif apt-cache search "^cuda " | grep -q "^cuda "; then
            log "Installing cuda metapackage..."
            safe_install cuda
            log "CUDA Toolkit installed (cuda metapackage)"
        else
            warn "No CUDA packages available in repository"
            log "Repository: https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_REPO_PATH}/"
            log "Try running: apt-cache search cuda"
        fi
    fi
    
else
    log "Skipping NVIDIA installation"
fi

################################################################################
# 13. Performance Tuning
################################################################################
section "Step 13: Performance Tuning"

if $PERFORMANCE_TUNING; then
    log "Applying performance optimizations..."
    
    # System limits (optimized for 32GB RAM and ML/AI)
    cat > /etc/security/limits.d/99-wsl2-limits.conf <<EOF
# WSL2 Performance Limits - High Performance (32GB RAM)

# Open file limits (for large projects and datasets)
* soft nofile 524288
* hard nofile 524288
root soft nofile 524288
root hard nofile 524288

# Process limits (for parallel ML/AI training)
* soft nproc 131072
* hard nproc 131072
root soft nproc 131072
root hard nproc 131072

# Memory lock (for CUDA and GPU memory pinning)
* soft memlock unlimited
* hard memlock unlimited

# Core dump size (for debugging)
* soft core unlimited
* hard core unlimited

EOF

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

    # Kernel parameters for WSL2 (High Performance: 32GB RAM, i7-13700K, RTX 4090)
    cat > /etc/sysctl.d/99-wsl2-optimization.conf <<EOF
# WSL2 Optimization - High Performance (32GB RAM, i7-13700K, RTX 4090)
# Optimized for ML/AI workloads, development, and GPU computing

# ============================================================================
# Network Performance - Maximum buffers for 32GB RAM
# ============================================================================

# TCP/UDP Buffer Sizes (aggressive for 32GB RAM)
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 524288 67108864
net.ipv4.tcp_wmem = 4096 524288 67108864

# Network Queues (high throughput)
net.core.netdev_max_backlog = 32768
net.core.somaxconn = 16384
net.ipv4.tcp_max_syn_backlog = 32768

# TCP Performance
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 10240 65535

# TCP Fast Open
net.ipv4.tcp_fastopen = 3

# TCP Window Scaling & SACK
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# MTU Probing
net.ipv4.tcp_mtu_probing = 1

# TCP Orphan & TIME_WAIT limits
net.ipv4.tcp_max_orphans = 65536
net.ipv4.tcp_max_tw_buckets = 262144

# ============================================================================
# Virtual Memory - Aggressive caching for 32GB RAM
# ============================================================================
vm.swappiness = 1
vm.vfs_cache_pressure = 40
vm.dirty_ratio = 30
vm.dirty_background_ratio = 10
vm.dirty_expire_centisecs = 6000
vm.dirty_writeback_centisecs = 500
vm.min_free_kbytes = 262144
vm.overcommit_memory = 1
vm.overcommit_ratio = 80
vm.zone_reclaim_mode = 0

# Memory mapping (for large datasets and ML models)
vm.max_map_count = 262144

# ============================================================================
# File System Performance (for large datasets)
# ============================================================================
fs.file-max = 4194304
fs.inotify.max_user_watches = 2097152
fs.inotify.max_user_instances = 2048

# ============================================================================
# Shared Memory (for CUDA and multi-process ML/AI)
# ============================================================================
kernel.shmmax = 68719476736
kernel.shmall = 16777216

# ============================================================================
# Kernel Performance (ML/AI workloads)
# ============================================================================
kernel.sched_migration_cost_ns = 5000000
kernel.sched_autogroup_enabled = 0
kernel.pid_max = 131072
kernel.threads-max = 131072

# Entropy (for cryptography)
kernel.random.write_wakeup_threshold = 1024

# ============================================================================
# Security
# ============================================================================
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
EOF

    # Enable Transparent Huge Pages for ML/AI (if available)
    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        log "Enabling Transparent Huge Pages for ML/AI workloads..."
        echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
        echo defer > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
    fi

    # Apply sysctl settings with error tolerance for missing parameters
    # Some parameters may not exist in WSL2 environment
    sysctl -e -p /etc/sysctl.d/99-wsl2-optimization.conf 2>&1 | grep -v "cannot stat" | grep -v "No such file or directory" || true
    log "Kernel parameters applied (some may be skipped in WSL2 environment)"

    # I/O scheduler optimization (for high-performance NVMe)
    cat > /etc/udev/rules.d/60-ioschedulers.conf <<'EOF'
# I/O Scheduler Optimization for WSL2 (High Performance)

# NVMe drives - use 'none' scheduler (best for high-end NVMe)
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/nr_requests}="2048"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/read_ahead_kb}="1024"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/rq_affinity}="2"

# SSD drives - use 'mq-deadline' scheduler
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/nr_requests}="1024"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/read_ahead_kb}="1024"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/rq_affinity}="2"
EOF
    
    log "Performance tuning applied"
else
    log "Skipping performance tuning"
fi

################################################################################
# 14. Automatic Security Updates
################################################################################
section "Step 14: Automatic Security Updates"

if $ENABLE_AUTO_UPDATES; then
    log "Configuring automatic security updates..."
    
    # Install unattended-upgrades with availability check
    safe_install unattended-upgrades apt-listchanges
    
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

    log "Automatic security updates configured"
else
    log "Skipping automatic security updates"
fi

################################################################################
# 15. Create Utility Scripts
################################################################################
section "Step 15: Creating Utility Scripts"

# WSL2 Performance Monitor
cat > /usr/local/bin/wsl2-monitor.sh <<'SCRIPT'
#!/bin/bash

echo "=== WSL2 System Monitor ==="
echo ""
echo "=== System Information ==="
echo "Hostname: $(hostname)"
echo "OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"
echo ""

echo "=== CPU Usage ==="
top -bn1 | head -n 5

echo ""
echo "=== Memory Usage ==="
free -h

echo ""
echo "=== Disk Usage ==="
df -h | grep -v tmpfs

echo ""
echo "=== WSL2 Specific ==="
# Try to get WSL version from wsl.exe (available from Windows side)
WSL_VERSION=$(wsl.exe --version 2>/dev/null | grep -o "WSL: [0-9.]*" | cut -d: -f2 | xargs)

# If wsl.exe not available, try to get WSL kernel version from /proc/version
if [ -z "$WSL_VERSION" ]; then
    KERNEL_VERSION=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' /proc/version 2>/dev/null | head -1)
    if [ -n "$KERNEL_VERSION" ]; then
        echo "WSL Version: $KERNEL_VERSION (kernel)"
    else
        echo "WSL Version: Unknown (run from Windows PowerShell: wsl --version)"
    fi
else
    echo "WSL Version: $WSL_VERSION"
fi
echo "GPU Support: $([ -e /dev/dxg ] && echo 'Available' || echo 'Not Available')"
if command -v nvidia-smi >/dev/null 2>&1; then
    NVIDIA_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null | head -1)
    if [ -n "$NVIDIA_VERSION" ]; then
        echo "NVIDIA Driver: $NVIDIA_VERSION"
    fi
fi

echo ""
echo "=== Top 5 Processes by Memory ==="
ps aux --sort=-%mem | head -6

echo ""
echo "=== Top 5 Processes by CPU ==="
ps aux --sort=-%cpu | head -6
SCRIPT

chmod +x /usr/local/bin/wsl2-monitor.sh

# WSL2 Cleanup Script
cat > /usr/local/bin/wsl2-cleanup.sh <<'SCRIPT'
#!/bin/bash

echo "Starting WSL2 cleanup..."

# Clean package cache
apt-get clean
apt-get autoclean
apt-get autoremove -y

# Clean journal logs
journalctl --vacuum-time=7d

# Clean temp files
find /tmp -type f -atime +7 -delete 2>/dev/null || true
find /var/tmp -type f -atime +7 -delete 2>/dev/null || true

# Clean Docker if installed
if command -v docker >/dev/null 2>&1; then
    docker system prune -f
fi

# Clear package lists to save space
rm -rf /var/lib/apt/lists/* 2>/dev/null || true

echo "WSL2 cleanup completed!"
SCRIPT

chmod +x /usr/local/bin/wsl2-cleanup.sh

# WSL2 Backup Script
cat > /usr/local/bin/wsl2-backup.sh <<'SCRIPT'
#!/bin/bash

BACKUP_DIR="/mnt/c/WSL-Backups/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

echo "Creating WSL2 backup to $BACKUP_DIR"

# Backup configuration files
cp /etc/wsl.conf "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/docker/daemon.json "$BACKUP_DIR/" 2>/dev/null || true

# Backup user configurations
if [ -n "$1" ]; then
    USER_HOME="/home/$1"
    if [ -d "$USER_HOME" ]; then
        tar -czf "$BACKUP_DIR/home-$1-$(date +%H%M%S).tar.gz" -C "$(dirname "$USER_HOME")" "$(basename "$USER_HOME")"
    fi
fi

echo "Backup completed: $BACKUP_DIR"
SCRIPT

chmod +x /usr/local/bin/wsl2-backup.sh

# Create weekly cron job for cleanup
cat > /etc/cron.weekly/wsl2-cleanup <<'EOF'
#!/bin/bash
/usr/local/bin/wsl2-cleanup.sh >> /var/log/wsl2-cleanup.log 2>&1
EOF

chmod +x /etc/cron.weekly/wsl2-cleanup

log "Utility scripts created"

################################################################################
# 16. Final Cleanup
################################################################################
section "Step 16: Final Cleanup"

log "Performing final cleanup..."

# Clean package cache
apt-get clean
apt-get autoclean
apt-get autoremove -y

# Clear journal logs
journalctl --vacuum-time=3d

log "Final cleanup completed"

################################################################################
# 17. Final Summary and Instructions
################################################################################
section "Step 17: Installation Complete"

echo ""
echo -e "${GREEN}================================================================================${NC}"
echo -e "${GREEN}=== WSL2 OPTIMIZATION COMPLETE ===${NC}"
echo -e "${GREEN}================================================================================${NC}"
echo ""

log "Summary of optimizations:"
log "  ✓ OS detected: $OS_NAME $OS_VERSION ($OS_CODENAME)"

if $CONFIGURE_WSL_CONF; then
    log "  ✓ WSL2 configuration (wsl.conf) with systemd"
fi

if $UPDATE_SYSTEM; then
    log "  ✓ System packages updated"
fi

if $INSTALL_BASE_UTILS; then
    log "  ✓ Base utilities installed"
fi

if [ -n "$NEW_USER" ]; then
    log "  ✓ New user created: $NEW_USER (with sudo access)"
fi

if $CONFIGURE_LOCALES; then
    log "  ✓ Locale configured: ${DEFAULT_LOCALE:-en_US.UTF-8}"
fi

if $INSTALL_ZSH; then
    log "  ✓ Zsh + Starship installed with WSL2 optimizations"
    log "  ✓ Autosuggestions, syntax highlighting, completions"
    log "  ✓ WSL2-specific functions (explorer, cmd, powershell, wslperf)"
fi

if $INSTALL_DOCKER; then
    log "  ✓ Docker CE + Docker Compose installed"
    if [ -n "$DOCKER_USER" ]; then
        log "  ✓ User $DOCKER_USER added to docker group"
    fi
fi

if $INSTALL_NVIDIA; then
    log "  ✓ NVIDIA Container Toolkit installed"
    if $INSTALL_CUDA; then
        log "  ✓ CUDA Toolkit installed"
    fi
fi

if $PERFORMANCE_TUNING; then
    log "  ✓ Performance tuning applied (sysctl, limits, I/O scheduler)"
fi

if $ENABLE_AUTO_UPDATES; then
    log "  ✓ Automatic security updates enabled"
fi

echo ""
log "Created utility scripts:"
log "  • wsl2-monitor.sh   - WSL2 system monitoring"
log "  • wsl2-cleanup.sh   - System cleanup (runs weekly)"
log "  • wsl2-backup.sh    - Backup configuration"

echo ""
echo -e "${CYAN}================================================================================${NC}"
echo -e "${YELLOW}IMPORTANT NEXT STEPS:${NC}"
echo -e "${CYAN}================================================================================${NC}"
echo ""

if [ -n "$NEW_USER" ] && $CREATE_USER; then
    warn "1. Run 'wsl --shutdown' in Windows PowerShell to apply default user"
    warn "   After: you will login as $NEW_USER instead of root"
    warn "2. Restart WSL2 distribution"
    echo ""
fi

if $CONFIGURE_WSL_CONF; then
    warn "Run 'wsl --shutdown' in Windows PowerShell to apply WSL2 configuration"
    warn "Then restart WSL2 distribution"
fi

if $INSTALL_ZSH; then
    info ""
    info "✓ New shell session will start with Zsh + Starship"
    info "  Features: autosuggestions (gray text), syntax highlighting, Git integration"
    info "  WSL2 functions: explorer(), cmd(), powershell(), wslperf()"
fi

if $INSTALL_DOCKER && [ -n "$DOCKER_USER" ]; then
    info ""
    info "✓ Docker group membership requires relogin or run: newgrp docker"
fi

echo ""
echo -e "${CYAN}================================================================================${NC}"
echo -e "${YELLOW}WSL2 PERFORMANCE TIPS:${NC}"
echo -e "${CYAN}================================================================================${NC}"
echo ""
info "• Create %USERPROFILE%\\.wslconfig in Windows for memory/CPU allocation:"
info "  [wsl2]"
info "  memory=8GB"
info "  processors=4"
info "  autoMemoryReclaim=dropCache"
info "  sparseVhd=true"
echo ""
info "• Enable mirrored networking in .wslconfig for better integration:"
info "  networkingMode=mirrored"
echo ""
info "• Run 'wsl2-monitor.sh' for system performance monitoring"
info "• Run 'wsl2-cleanup.sh' for periodic maintenance"
echo ""

echo -e "${GREEN}================================================================================${NC}"
echo -e "${GREEN}WSL2 OPTIMIZATION SUCCESSFULLY COMPLETED!${NC}"
echo -e "${GREEN}================================================================================${NC}"
echo ""

# Show system information
if command -v wsl2-monitor.sh >/dev/null 2>&1; then
    wsl2-monitor.sh
fi
