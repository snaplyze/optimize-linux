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

# Check if package is available in repositories
package_available() {
    apt-cache show "$1" >/dev/null 2>&1
}

# Safe package installation with availability check
safe_install() {
    packages=("$@")
    available_packages=()
    unavailable_packages=()
    
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
section "Step 2: Configuration Selection"

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
    echo -e "${CYAN}  WSL2 OPTIMIZATION: Debian ${VERSION_ID:-?} (${VERSION_CODENAME^:-?})${NC}"
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
systemd=true
# Command to run on startup
command="service docker start"

[automount]
# Enable metadata for proper file permissions
enabled=true
options="metadata,uid=1000,gid=1000,umask=022,fmask=111"
# Mount drives to / instead of /mnt for cleaner paths
root=/
# Enable case sensitivity (off, dir, or force)
case=dir

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
        "fastfetch"
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
        LOCALE_CHOICE=$(dialog --title "Locale Selection" --menu "Select locale:" --radiolist "1" "English (en_US.UTF-8)" "2" "Russian (ru_RU.UTF-8)" "3" "Both (en_US.UTF-8 + ru_RU.UTF-8)" --default "1")
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
    locale-gen
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

# History configuration
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history
setopt EXTENDED_HISTORY INC_APPEND_HISTORY SHARE_HISTORY
setopt HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE
setopt HIST_SAVE_NO_DUPS HIST_VERIFY APPEND_HISTORY

# Directory navigation
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT

# Load zsh-syntax-highlighting FIRST
if [[ -f ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)
    source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# Load zsh-autosuggestions SECOND
if [[ -f ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
    ZSH_AUTOSUGGEST_USE_ASYNC=true
    bindkey '^ ' autosuggest-accept
    bindkey '^[^M' autosuggest-execute
fi

# Completion settings
fpath=(~/.zsh/zsh-completions/src $fpath)
autoload -Uz compinit
if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+24) ]]; then
    compinit
else
    compinit -C
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
setopt BASH_REMATCH KSH_ARRAYS
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

# Initialize Starship prompt
eval "$(starship init zsh)"
ZSHRC

        # Create Starship config with WSL2 optimizations
        mkdir -p "$user_home/.config"
        
        cat > "$user_home/.config/starship.toml" <<'STARSHIP'
# WSL2 Optimized Starship Configuration

command_timeout = 1000
add_newline = true

format = """
$username\
$hostname\
$directory\
$git_branch\
$git_status\
$docker_context\
$python\
$nodejs\
$golang\
$rust\
$java\
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
style = 'blue bold'
read_only = " 󰌾"
format = 'in [$path]($style)[$read_only]($read_only_style) '

[character]
success_symbol = '[➜](bold green)'
error_symbol = '[✗](bold red)'

[git_branch]
symbol = "🌱 "
format = 'on [$symbol$branch]($style) '
style = 'purple bold'

[git_status]
format = '([\[$all_status$ahead_behind\]]($style) )'
style = 'red bold'
conflicted = '='
ahead = '⇡${count}'
behind = '⇣${count}'
diverged = '⇕${ahead_count}⇣${behind_count}'
untracked = '?${count}'
stashed = '\$${count}'
modified = '!${count}'
staged = '+${count}'
renamed = '»${count}'
deleted = 'x${count}'

[cmd_duration]
min_time = 500
format = 'took [$duration](bold yellow)'
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
        warn "Could not determine latest Go version, skipping Go installation"
        return 1
    fi

    log "Latest Go version: $go_version"

    # Build download URL
    go_download_url="https://go.dev/dl/go${go_version}.${go_os}-${go_arch}.tar.gz"
    go_checksum_url="https://go.dev/dl/go${go_version}.${go_os}-${go_arch}.tar.gz.sha256"

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

    # Add Go to PATH for all users
    cat > /etc/profile.d/golang.sh <<'GOEOF'
export PATH=/usr/local/go/bin:$PATH
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$PATH
GOEOF
    chmod +x /etc/profile.d/golang.sh

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

    # Set environment for NVM installation
    export HOME=$user_home
    export NVM_DIR="$user_home/.nvm"

    # Download and install NVM
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash >/dev/null 2>&1

    # Source NVM
    export NVM_DIR="$user_home/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

    # Install Node.js LTS
    log "Installing Node.js LTS for $username..."
    nvm install --lts >/dev/null 2>&1
    nvm alias default lts/* >/dev/null 2>&1

    log "Node.js installed: $(node --version)"
    log "npm version: $(npm --version)"

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

    # Set ownership
    chown -R "$username:$username" "$NVM_DIR" 2>/dev/null || true
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
    
    # Configure Docker daemon for WSL2
    cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-address-pools": [
    {
      "base": "172.17.0.0/12",
      "size": 24
    }
  ],
  "default-ulimits": {
    "nofile": 65536,
    "nproc": 32768
  },
  "features": {
    "buildkit": true
  }
}
EOF
    
    # Enable and start Docker service
    if has_systemd; then
        systemctl enable docker
        systemctl start docker
        log "Docker service enabled and started"
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

            # Ensure Docker daemon is valid (or create default)
            if [ ! -f /etc/docker/daemon.json ] || ! python3 -m json.tool /etc/docker/daemon.json >/dev/null 2>&1; then
                log "Creating Docker daemon.json..."
                echo '{}' > /etc/docker/daemon.json
            fi

            # Configure NVIDIA runtime
            nvidia-ctk runtime configure --runtime=docker 2>&1 | grep -v "^INFO" || {
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
                local retry_count=0
                local max_retries=3
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
    
    # System limits
    cat > /etc/security/limits.d/99-wsl2-limits.conf <<EOF
# WSL2 Performance Limits
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
root soft nofile 65535
root hard nofile 65535
root soft nproc 65535
root hard nproc 65535
EOF
    
    # Kernel parameters for WSL2
    cat > /etc/sysctl.d/99-wsl2-optimization.conf <<EOF
# WSL2 Performance Optimization

# Network Performance
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 8096
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10240 65535

# TCP Congestion Control (BBR for better throughput)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# File System Performance
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# Virtual Memory (optimized for WSL2)
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.min_free_kbytes = 65536

# Security
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
    
    sysctl -p /etc/sysctl.d/99-wsl2-optimization.conf
    
    # I/O scheduler optimization
    cat > /etc/udev/rules.d/60-ioschedulers.conf <<EOF
# I/O Scheduler Optimization for WSL2
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
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
# Get WSL version - extract version number from wsl.exe output
# wsl.exe --version outputs multiple lines with strange characters, extract just the version
WSL_VERSION=$(wsl.exe --version 2>/dev/null | grep -o "WSL: [0-9.]*" | cut -d: -f2 | xargs)
if [ -z "$WSL_VERSION" ]; then
    echo "WSL Version: Unknown (wsl.exe not available or Windows integration disabled)"
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