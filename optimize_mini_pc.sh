#!/bin/bash

# Force C locale for script execution to avoid locale-related issues
export LC_ALL=C
export LANG=C

################################################################################
# Mini PC Optimization Script (Intel N5095/Jasper Lake Focus)
# Purpose: Complete optimization for Home Server / Media Server on Debian 13
# Hardware Focus: Intel Celeron N5095 (Jasper Lake), SSD/NVMe, Intel UHD GPU
# Version: 1.0.0 (Hybrid VPS+WSL2 features)
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
LOG_FILE="/var/log/minipc_optimization.log"

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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Check if package is available in repositories
package_available() {
    apt-cache show "$1" >/dev/null 2>&1
}

# Safe package installation with availability check
safe_install() {
    packages=("$@")
    available_packages=()
    unavailable_packages=()
    
    # Update package list before checking availability (only if needed)
    # apt-get update >/dev/null 2>&1 
    
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
        warn "No packages available for installation from list: ${packages[*]}"
    fi
    
    if [ ${#unavailable_packages[@]} -gt 0 ]; then
        warn "Skipping unavailable packages: ${unavailable_packages[*]}"
    fi
}

# Prompt Yes/No
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

# Check if dialog is available
check_dialog() {
    if command -v dialog >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

################################################################################
# Configuration Menu
################################################################################

# Default configuration flags
UPDATE_SYSTEM=true
INSTALL_BASE_UTILS=true
CONFIGURE_LOCALES=true
CREATE_USER=true
INSTALL_XANMOD=true
INSTALL_INTEL_GPU=true
OPTIMIZE_SSD=true
INSTALL_DOCKER=true
INSTALL_ZSH=true
INSTALL_GO=true
INSTALL_NODE=true
CONFIGURE_SECURITY=true
DISABLE_SERVICES=true
INSTALL_SAMBA=false 
PERFORMANCE_TUNING=true

show_menu() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Mini PC Optimization Config (Intel N5095/Debian 13)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    # System Basics
    prompt_yn "Update system & Install base utils" true && { UPDATE_SYSTEM=true; INSTALL_BASE_UTILS=true; } || { UPDATE_SYSTEM=false; INSTALL_BASE_UTILS=false; }
    prompt_yn "Configure Locales (en_US + ru_RU) & Timezone" true && CONFIGURE_LOCALES=true || CONFIGURE_LOCALES=false
    prompt_yn "Create new sudo user & Harden SSH" true && { CREATE_USER=true; CONFIGURE_SECURITY=true; } || { CREATE_USER=false; CONFIGURE_SECURITY=false; }

    echo ""
    # Hardware Specifics
    prompt_yn "Install XanMod Kernel (optimized for N5095/JasperLake)" true && INSTALL_XANMOD=true || INSTALL_XANMOD=false
    prompt_yn "Install Intel GPU Drivers (QuickSync/Transcoding)" true && INSTALL_INTEL_GPU=true || INSTALL_INTEL_GPU=false
    prompt_yn "Optimize SSDs (TRIM, I/O scheduler)" true && OPTIMIZE_SSD=true || OPTIMIZE_SSD=false
    prompt_yn "Apply Performance Tuning (Sysctl, Limits, Swap, Tmpfs)" true && { PERFORMANCE_TUNING=true; DISABLE_SERVICES=true; } || { PERFORMANCE_TUNING=false;DISABLE_SERVICES=false; }

    echo ""
    # Software Stack
    prompt_yn "Install Docker CE & Docker Compose" true && INSTALL_DOCKER=true || INSTALL_DOCKER=false
    prompt_yn "Install Zsh + Starship Shell (Full Server Config)" true && INSTALL_ZSH=true || INSTALL_ZSH=false
    prompt_yn "Install Go (Latest)" true && INSTALL_GO=true || INSTALL_GO=false
    prompt_yn "Install Node.js (LTS via NVM)" true && INSTALL_NODE=true || INSTALL_NODE=false
    prompt_yn "Install Samba File Sharing (for /mnt/ssd)" false && INSTALL_SAMBA=true || INSTALL_SAMBA=false

    echo ""
    echo -e "${CYAN}Starting installation with selected options...${NC}"
    sleep 1
}

# Show menu
show_menu

log "=== Starting Mini PC Optimization ==="

################################################################################
# 1. System Update & Base Utils
################################################################################
if $UPDATE_SYSTEM; then
    section "Step 1: System Update"    
    # Enrich sources for non-free drivers (needed for Intel GPU)
    if [ -f /etc/apt/sources.list ]; then
        log "Enabling contrib non-free non-free-firmware repositories..."
        sed -i 's/^deb \(http\|https\)/deb \1/g; s/^deb \([^#]*\)$/deb \1 contrib non-free non-free-firmware/g; s/contrib non-free non-free-firmware.*contrib non-free non-free-firmware/contrib non-free non-free-firmware/g' /etc/apt/sources.list
    fi
    
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    
    if $INSTALL_BASE_UTILS; then
        log "Installing essential packages..."
        # Combined list from VPS + specific needs
        safe_install wget curl git htop iotop sysstat net-tools \
            iptables ufw fail2ban unattended-upgrades apt-listchanges \
            # neofetch lm-sensors cpufrequtils speedtest-cli \
            zip unzip gnupg ca-certificates lsb-release \
            lm-sensors cpufrequtils speedtest-cli \
            fzf ripgrep fd-find bat bc needrestart ncdu tree vim nano tmux \
            make gcc g++ cmake xz-utils xdg-user-dirs
            
        # Aliases for bat and fd
        [ -f /usr/bin/batcat ] && [ ! -f /usr/bin/bat ] && ln -sf /usr/bin/batcat /usr/bin/bat 2>/dev/null || true
        [ -f /usr/bin/fdfind ] && [ ! -f /usr/bin/fd ] && ln -sf /usr/bin/fdfind /usr/bin/fd 2>/dev/null || true
        
        # Configure iptables-legacy for Docker compatibility (Debian 13 specific)
        # Switch ALL iptables utilities to legacy mode (critical for UFW)
        # Set master alternatives first
        update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 100
        update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-legacy 100
        # Set slave alternatives (iptables-restore and iptables-save are automatically managed)
        update-alternatives --set iptables-save /usr/sbin/iptables-legacy-save 2>/dev/null || true
        update-alternatives --set ip6tables-save /usr/sbin/ip6tables-legacy-save 2>/dev/null || true
    fi
fi

################################################################################
# 2. Locale & Timezone
################################################################################
if $CONFIGURE_LOCALES; then
    section "Step 2: Locales & Timezone"
    
    safe_install locales dialog

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
        1) LOCALE_TO_GENERATE="en_US.UTF-8"; DEFAULT_LOCALE="en_US.UTF-8" ;;
        2) LOCALE_TO_GENERATE="ru_RU.UTF-8"; DEFAULT_LOCALE="ru_RU.UTF-8" ;;
        3) LOCALE_TO_GENERATE="en_US.UTF-8 ru_RU.UTF-8"; DEFAULT_LOCALE="en_US.UTF-8" ;;
        *) LOCALE_TO_GENERATE="en_US.UTF-8"; DEFAULT_LOCALE="en_US.UTF-8" ;;
    esac

    log "Generating locales: $LOCALE_TO_GENERATE"
    for locale in $LOCALE_TO_GENERATE; do
        if ! grep -q "^${locale} UTF-8" /etc/locale.gen 2>/dev/null && ! grep -q "^# ${locale} UTF-8" /etc/locale.gen 2>/dev/null; then
            echo "${locale} UTF-8" >> /etc/locale.gen
        fi
        sed -i "s/^# *\(${locale} UTF-8\)/\1/" /etc/locale.gen
    done

    LC_ALL=C.UTF-8 locale-gen

    cat > /etc/default/locale <<EOF
LANG=$DEFAULT_LOCALE
LANGUAGE=${DEFAULT_LOCALE%%.*}
LC_ALL=$DEFAULT_LOCALE
EOF

    cat > /etc/profile.d/locale.sh <<EOF
export LANG=$DEFAULT_LOCALE
export LC_ALL=$DEFAULT_LOCALE
export LANGUAGE=${DEFAULT_LOCALE%%.*}
EOF
    chmod +x /etc/profile.d/locale.sh

    # Timezone
    echo ""
    read -p "Enter timezone (e.g., Europe/Moscow) [Press Enter to keep current]: " NEW_TIMEZONE
    if [ -n "$NEW_TIMEZONE" ]; then
        if [ -f "/usr/share/zoneinfo/$NEW_TIMEZONE" ]; then
            timedatectl set-timezone "$NEW_TIMEZONE" 2>/dev/null || {
                ln -sf "/usr/share/zoneinfo/$NEW_TIMEZONE" /etc/localtime
                echo "$NEW_TIMEZONE" > /etc/timezone
            }
            log "Timezone set to $NEW_TIMEZONE"
        else
            warn "Invalid timezone. Skipping."
        fi
    fi
fi

################################################################################
# 3. User Creation
################################################################################
if $CREATE_USER; then
    section "Step 3: User Creation"
    
    read -p "Enter new username: " NEW_USER
    if [ -n "$NEW_USER" ]; then
        if id "$NEW_USER" &>/dev/null; then
            warn "User $NEW_USER exists."
        else
            adduser --gecos "" --disabled-password "$NEW_USER"
            passwd "$NEW_USER"
            usermod -aG sudo "$NEW_USER"
        fi
        
        # Configure passwordless sudo
        echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$NEW_USER
        chmod 440 /etc/sudoers.d/$NEW_USER
        
        # Setup SSH keys
        USER_HOME=$(eval echo ~$NEW_USER)
        mkdir -p "$USER_HOME/.ssh"
        chmod 700 "$USER_HOME/.ssh"
        
        echo ""
        read -p "Paste SSH Public Key (or press Enter to skip): " SSH_KEY
        if [ -n "$SSH_KEY" ]; then
            echo "$SSH_KEY" > "$USER_HOME/.ssh/authorized_keys"
            chmod 600 "$USER_HOME/.ssh/authorized_keys"
            chown -R "$NEW_USER:$NEW_USER" "$USER_HOME/.ssh"
            
            if $CONFIGURE_SECURITY; then
                log "Hardening SSH..."
                cat > /etc/ssh/sshd_config.d/99-hardening.conf <<EOF
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers $NEW_USER
EOF
                systemctl restart ssh
            fi
        fi
    fi
else
    NEW_USER=$(logname 2>/dev/null || echo $SUDO_USER)
    [ -z "$NEW_USER" ] && NEW_USER="root"
fi
DOCKER_USER=$NEW_USER

################################################################################
# 4. Hardware Optimization (XanMod & CPU & GPU)
################################################################################
if $INSTALL_XANMOD; then
    section "Step 4: Kernel & Hardware"
    
    # N5095 Check
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d':' -f2)
    log "Detected CPU: $CPU_MODEL"
    
    # Force x64v2 for Jasper Lake (No AVX)
    XANMOD_VARIANT="x64v2"
    log "Installing XanMod Kernel ($XANMOD_VARIANT) - Optimized for Jasper Lake..."

    wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list
    
    apt-get update
    safe_install linux-xanmod-x64v2
    
    # CPU Governor (schedutil is best for N5095)
    sed -i 's/^GOVERNOR=.*/GOVERNOR="schedutil"/' /etc/default/cpufrequtils 2>/dev/null || echo 'GOVERNOR="schedutil"' > /etc/default/cpufrequtils
    systemctl restart cpufrequtils 2>/dev/null || true
fi

if $INSTALL_INTEL_GPU; then
    log "Installing Intel GPU Drivers..."
    safe_install intel-media-va-driver-non-free libmfx1 intel-gpu-tools vainfo mesa-utils
    
    groupadd -f render
    groupadd -f video
    if [ -n "$NEW_USER" ] && [ "$NEW_USER" != "root" ]; then
        usermod -aG video,render "$NEW_USER"
        log "Added $NEW_USER to video/render groups."
    fi
fi

################################################################################
# 5. SSD & Storage
################################################################################
if $OPTIMIZE_SSD; then
    section "Step 5: Storage Optimization"
    
    systemctl enable fstrim.timer
    systemctl start fstrim.timer
    
    log "Setting I/O schedulers (mq-deadline for SSD, none for NVMe)..."
    # FIX: Added missing '=' signs in ATTR
    cat > /etc/udev/rules.d/60-ioschedulers.conf <<EOF
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
EOF
    udevadm control --reload
    udevadm trigger
fi

################################################################################
# 6. Zsh + Starship (Full Config)
################################################################################
if $INSTALL_ZSH; then
    section "Step 6: Zsh & Starship"
    safe_install zsh curl git

    curl -sS https://starship.rs/install.sh | sh -s -- -y

    setup_zsh_for_user() {
        local username=$1
        local user_home=$(eval echo ~$username)
        log "Configuring Zsh for $username..."

        mkdir -p "$user_home/.zsh"
        [ ! -d "$user_home/.zsh/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions "$user_home/.zsh/zsh-autosuggestions"
        [ ! -d "$user_home/.zsh/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$user_home/.zsh/zsh-syntax-highlighting"
        [ ! -d "$user_home/.zsh/zsh-completions" ] && git clone https://github.com/zsh-users/zsh-completions "$user_home/.zsh/zsh-completions"

        # Write full .zshrc (copied from VPS script)
        cat > "$user_home/.zshrc" <<'ZSHRC'
# Mini PC Zsh Config (Full Features)

# Fix VSCode Remote terminal error
if [[ -n "$VSCODE_INJECTION" ]] || [[ "$TERM_PROGRAM" == "vscode" ]]; then
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
setopt BASH_REMATCH
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
alias gpu='intel_gpu_top'

# Package management
alias update='sudo apt update && sudo apt upgrade -y'
alias install='sudo apt install'
alias remove='sudo apt remove'
alias search='apt search'
alias autoremove='sudo apt autoremove -y'

# Go/NVM paths
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Initialize Starship prompt
eval "$(starship init zsh)"
ZSHRC
        
        mkdir -p "$user_home/.config"
        
        # Full Starship config (VPS version)
        cat > "$user_home/.config/starship.toml" <<'STARSHIP'
# Starship configuration - Unicode version
command_timeout = 1000
add_newline = true

format = """
$username\
$hostname
$directory
$git_branch
$git_status
$docker_context
$python
$nodejs
$golang
$rust
$java
$line_break
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
read_only = " 🔒"
format = 'in [$path]($style)[$read_only]($read_only_style) '

[character]
success_symbol = '[➜](bold green)'
error_symbol = '[✗](bold red)'

[git_branch]
symbol = "🌱 "
format = 'on [$symbol$branch]($style) '
style = 'purple bold'

[git_status]
format = '([\$all_status$ahead_behind]($style) )'
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

        chown -R "$username:$username" "$user_home/.zsh" "$user_home/.zshrc" "$user_home/.config"
        chsh -s $(which zsh) "$username"
    }

    setup_zsh_for_user root
    [ -n "$NEW_USER" ] && [ "$NEW_USER" != "root" ] && setup_zsh_for_user "$NEW_USER"
fi

################################################################################
# 7. Go & Node.js
################################################################################
if $INSTALL_GO; then
    section "Step 7a: Go Installation"
    GO_ARCH="amd64"
    GO_VERSION=$(curl -s https://go.dev/VERSION?m=text 2>/dev/null | head -1 | sed 's/go//')
    [ -z "$GO_VERSION" ] && GO_VERSION="1.22.0"
    
    wget "https://dl.google.com/go/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -O /tmp/go.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tar.gz
    
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' > /etc/profile.d/go.sh
    rm /tmp/go.tar.gz
    log "Go $GO_VERSION installed."
fi

if $INSTALL_NODE; then
    section "Step 7b: Node.js (NVM)"
    
    install_nvm() {
        local user=$1
        local home=$(eval echo ~$user)
        log "Installing NVM for $user..."
        
        # Create temp installer
        cat > "/tmp/nvm_install.sh" <<'NVMINST'
export NVM_DIR="$HOME/.nvm"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install --lts
NVMINST
        chmod +x /tmp/nvm_install.sh
        
        if [ "$user" = "root" ]; then
            /tmp/nvm_install.sh
        else
            su - "$user" -c "/tmp/nvm_install.sh"
        fi
        rm -f /tmp/nvm_install.sh
    }
    
    install_nvm root
    [ -n "$NEW_USER" ] && [ "$NEW_USER" != "root" ] && install_nvm "$NEW_USER"
fi

################################################################################
# 8. Docker
################################################################################
if $INSTALL_DOCKER; then
    section "Step 8: Docker"
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        apt-get remove -y $pkg 2>/dev/null || true
    done
    
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
      
    apt-get update
    safe_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
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
    # Override socket for proper startup
    mkdir -p /etc/systemd/system/docker.service.d
    echo -e "[Service]\nExecStart=\nExecStart=/usr/bin/dockerd -H unix:///var/run/docker.sock" > /etc/systemd/system/docker.service.d/override.conf
    
    systemctl daemon-reload
    systemctl enable docker
    systemctl start docker
    
    [ -n "$NEW_USER" ] && usermod -aG docker "$NEW_USER"
fi

################################################################################
# 9. Performance Tuning (Sysctl, Swap, Limits)
################################################################################
if $PERFORMANCE_TUNING; then
    section "Step 9: Performance Tuning"
    
    # RAM Detection
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$(echo "$TOTAL_RAM_KB / 1024 / 1024" | bc)
    
    # Swap (50% RAM rule)
    SWAP_SIZE=$(( TOTAL_RAM_GB / 2 ))
    [ $SWAP_SIZE -lt 1 ] && SWAP_SIZE=2
    
    if ! grep -q "/swapfile" /etc/fstab; then
        log "Creating ${SWAP_SIZE}GB Swap..."
        fallocate -l ${SWAP_SIZE}G /swapfile || dd if=/dev/zero of=/swapfile bs=1G count=$SWAP_SIZE
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    # Ensure /etc/sysctl.conf exists
    if [ ! -f /etc/sysctl.conf ]; then
        log "Creating /etc/sysctl.conf (was missing)..."
        cat > /etc/sysctl.conf <<'SYSCTLCONF'
#
# /etc/sysctl.conf - Configuration file for setting system variables
# See /etc/sysctl.d/ for additional system variables.
#

# Additional settings are in /etc/sysctl.d/
SYSCTLCONF
    fi

    # Sysctl (VPS optimized + MiniPC specific)
    cat > /etc/sysctl.d/99-minipc.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
fs.inotify.max_user_watches = 524288
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF
    sysctl -p /etc/sysctl.d/99-minipc.conf
    
    # Limits
    cat > /etc/security/limits.d/99-minipc.conf <<EOF
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF

    # Journald limit
    mkdir -p /etc/systemd/journald.conf.d/
    echo -e "[Journal]\nSystemMaxUse=500M" > /etc/systemd/journald.conf.d/00-size.conf
    systemctl restart systemd-journald
    
    # Tmpfs optimization
    if ! grep -q "tmpfs /tmp" /etc/fstab; then
        log "Optimizing tmpfs..."
        echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=1G 0 0" >> /etc/fstab
        echo "tmpfs /var/tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=512M 0 0" >> /etc/fstab
    fi
fi

################################################################################
# 10. Disable Unnecessary Services
################################################################################
if $DISABLE_SERVICES; then
    section "Step 10: Disable Unused Services"
    SERVICES_TO_DISABLE=("bluetooth.service" "cups.service" "avahi-daemon.service")
    for service in "${SERVICES_TO_DISABLE[@]}"; do
        if systemctl is-enabled "$service" 2>/dev/null; then
            systemctl disable "$service"
            systemctl stop "$service"
            log "Disabled $service"
        fi
    done
fi

################################################################################
# 11. Security (UFW, Auto-Updates)
################################################################################
if $CONFIGURE_SECURITY; then
    section "Step 11: Security"
    
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    $INSTALL_SAMBA && ufw allow samba
    ufw --force enable
    
    # Fail2Ban
    cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = 22
maxretry = 3
bantime = 3600
EOF
    systemctl restart fail2ban
    
    # Auto Updates
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
fi

################################################################################
# 12. Services (Samba)
################################################################################
if $INSTALL_SAMBA; then
    section "Step 12: Samba"
    safe_install samba
    cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
    
    cat >> /etc/samba/smb.conf <<EOF

[SSD_Storage]
   path = /mnt/ssd
   browsable = yes
   writable = yes
   guest ok = no
   read only = no
   create mask = 0644
   directory mask = 0755
   valid users = $NEW_USER
EOF
    
    log "Samba configured. Please set password for $NEW_USER:"
    smbpasswd -a "$NEW_USER" || warn "Samba password set failed."
    systemctl restart smbd
fi

################################################################################
# 13. Monitoring & Maintenance Scripts
################################################################################
section "Step 13: Utility Scripts"

# 13.1 Monitor Script
cat > /usr/local/bin/minipc-monitor.sh <<'EOF'
#!/bin/bash
echo "=== Mini PC Monitor (N5095) ==="
echo ""
echo "--- System ---"
echo "CPU Temp: $(sensors | grep 'Package id 0:' | awk '{print $4}')"
echo "Kernel:   $(uname -r)"
echo "Uptime:   $(uptime -p)"
echo "Load:     $(uptime | awk -F'load average:' '{print $2}')"
echo ""
echo "--- Memory ---"
free -h | grep Mem | awk '{print "Total: "$2 " | Used: "$3 " | Free: "$4}'
echo ""
echo "--- Storage ---"
df -h / /mnt/ssd 2>/dev/null | grep -v Filesystem
echo ""
echo "--- Docker ---"
if command -v docker >/dev/null; then
    docker ps --format "table {{.Names}}	{{.Status}}	{{.Ports}}"
else
    echo "Docker not installed"
fi
echo ""
echo "--- GPU ---"
echo "Run 'sudo intel_gpu_top' for realtime stats."
EOF
chmod +x /usr/local/bin/minipc-monitor.sh

# 13.2 Cleanup Script
cat > /usr/local/bin/minipc-cleanup.sh <<'EOF'
#!/bin/bash
echo "Starting Mini PC cleanup..."
# Clean package cache
apt-get clean
apt-get autoclean
apt-get autoremove -y
# Clean journals > 7 days
journalctl --vacuum-time=7d
# Clean docker
if command -v docker >/dev/null; then
    docker system prune -f
fi
# Clean temp
find /tmp -type f -atime +7 -delete
echo "Cleanup completed!"
EOF
chmod +x /usr/local/bin/minipc-cleanup.sh

# Weekly cleanup cron
echo '#!/bin/bash' > /etc/cron.weekly/minipc-cleanup
echo '/usr/local/bin/minipc-cleanup.sh >> /var/log/minipc-cleanup.log 2>&1' >> /etc/cron.weekly/minipc-cleanup
chmod +x /etc/cron.weekly/minipc-cleanup

# 13.3 Info Script
cat > /usr/local/bin/minipc-info.sh <<'EOF'
#!/bin/bash
echo "=== System Information ==="
hostnamectl
echo ""
echo "=== CPU Info ==="
lscpu | grep -E 'Model name|Architecture|Thread|Core'
echo ""
echo "=== Network ==="
ip -br a
echo ""
echo "=== Public IP ==="
curl -s ifconfig.me || echo "Unavailable"
echo ""
EOF
chmod +x /usr/local/bin/minipc-info.sh

# 13.4 Network Test Script
cat > /usr/local/bin/network-test.sh <<'EOF'
#!/bin/bash
echo "=== Network Performance Test ==="
if ! command -v speedtest-cli &> /dev/null; then
    apt-get install -y speedtest-cli
fi
speedtest-cli
echo ""
echo "=== Network Stats ==="
netstat -s | head -20
EOF
chmod +x /usr/local/bin/network-test.sh

log "=== Optimization Complete ==="
log "Please REBOOT to apply kernel, group changes, and sysctl settings."
log "New Utilities:"
log "  • minipc-monitor.sh"
log "  • minipc-cleanup.sh"
log "  • minipc-info.sh"
log "  • network-test.sh"