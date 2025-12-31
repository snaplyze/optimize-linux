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
# 0. Detect OS Version & Validation
################################################################################
section "Step 0: Pre-flight Checks"

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

# Validate Debian version
case "$ID" in
    debian)
        if [[ ! "$VERSION_ID" =~ ^(11|12|13)$ ]]; then
            warn "This script is optimized for Debian 11-13. Detected: Debian $VERSION_ID"
            warn "Continuing anyway, but some features (like XanMod) might fail."
        fi
        ;;
    ubuntu)
        if (( $(echo "$VERSION_ID < 20.04" | bc -l) )); then
            warn "This script is optimized for Ubuntu 20.04+. Detected: Ubuntu $VERSION_ID"
        fi
        ;;
esac

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
    prompt_yn "Install Node.js (LTS via NVM)" true && INSTALL_NODE=true || INSTALL_NODE=false
    
    SAMBA_SHARE_NAME="SSD_Storage"
    prompt_yn "Install Samba File Sharing" false && INSTALL_SAMBA=true || INSTALL_SAMBA=false
    if $INSTALL_SAMBA; then
        while true; do
            echo -ne "  ${YELLOW}Enter Samba Share Name (folder name) [SSD_Storage]: ${NC}"
            read input_name
            input_name=${input_name:-SSD_Storage}
            if [[ "$input_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                SAMBA_SHARE_NAME="$input_name"
                break
            else
                echo -e "  ${RED}Invalid name. Use only A-Z, a-z, 0-9, underscores, and hyphens.${NC}"
            fi
        done
        log_info "Samba Share Name set to: $SAMBA_SHARE_NAME"
    fi

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
    
    # Check if dialog is available, fallback to read if not
    check_dialog() {
        if command -v dialog > /dev/null 2>&1; then
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
        
        # Remove all existing entries for this locale (both commented and uncommented)
        # to avoid duplicates from previous runs
        sed -i "/^#* *${locale} UTF-8/d" /etc/locale.gen
        
        # Add a single uncommented entry
        echo "${locale} UTF-8" >> /etc/locale.gen
        log "Added ${locale} to /etc/locale.gen"
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
    
    echo ""
    info "We need to create a new sudo user for secure access."
    if $CONFIGURE_SECURITY; then
        info "Root login will be disabled after setup."
    fi
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
            # Loop until password is successfully set
            while true; do
                if passwd "$NEW_USER"; then
                    log "Password changed for $NEW_USER"
                    break
                else
                    warn "Failed to change password. Please try again."
                    read -p "Retry? (Y/n): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Nn]$ ]]; then
                        warn "Skipping password change."
                        break
                    fi
                fi
            done
        fi
    else
        # Create user with disabled password initially (will be set below)
        /usr/sbin/adduser --gecos "" --disabled-password "$NEW_USER" || {
            error "Failed to create user $NEW_USER"
            exit 1
        }
        
        # Add to sudo group
        /usr/sbin/usermod -aG sudo "$NEW_USER"
        log "User $NEW_USER created and added to sudo group"
        
        # Set password for new user
        log "Setting password for new user $NEW_USER..."
        # Set password for new user
        log "Setting password for new user $NEW_USER..."
        while true; do
            if passwd "$NEW_USER"; then
                 break
            else
                 warn "Failed to set password. Please try again."
                 read -p "Retry? (Y/n): " -n 1 -r
                 echo
                 if [[ $REPLY =~ ^[Nn]$ ]]; then
                     warn "Skipping password setup (user might be locked)."
                     break
                 fi
            fi
        done
    fi
    
    # Store user for later use (adding to docker group, video/render groups)
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
    info "Press Enter to skip SSH key setup (you can add it later)"
    echo ""
    read -p "SSH Public Key: " SSH_PUBLIC_KEY
    
    if [ -n "$SSH_PUBLIC_KEY" ]; then
        echo "$SSH_PUBLIC_KEY" > "$USER_HOME/.ssh/authorized_keys"
        chmod 600 "$USER_HOME/.ssh/authorized_keys"
        chown -R "$NEW_USER:$NEW_USER" "$USER_HOME/.ssh"
        log "SSH public key added for $NEW_USER"
        
        if $CONFIGURE_SECURITY; then
            log "Hardening SSH configuration..."
            cat > /etc/ssh/sshd_config.d/99-hardening.conf <<EOF
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers $NEW_USER
EOF
            systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null || true
            log "SSH hardened: only $NEW_USER can login with SSH keys"
        fi
    else
        warn "SSH key setup skipped. You can add a key later to ~/.ssh/authorized_keys"
        if $CONFIGURE_SECURITY; then
            warn "SSH hardening skipped (no SSH key provided)"
            CONFIGURE_SECURITY=false
        fi
    fi
else
    NEW_USER=$(logname 2>/dev/null || echo $SUDO_USER)
    [ -z "$NEW_USER" ] && NEW_USER="root"
    log "Using existing user: $NEW_USER"
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
    # cpufrequtils is deprecated in Debian 13, using linux-cpupower
    safe_install linux-cpupower

    # Detect best available governor
    AVAILABLE_GOVERNORS=$(cpupower frequency-info -g | grep "available cpufreq governors:" | cut -d: -f2)
    
    if [[ "$AVAILABLE_GOVERNORS" == *"schedutil"* ]]; then
        GOVERNOR="schedutil"
    elif [[ "$AVAILABLE_GOVERNORS" == *"powersave"* ]]; then
        GOVERNOR="powersave"
        log "Note: Using 'powersave' governor (standard for intel_pstate driver)"
    elif [[ "$AVAILABLE_GOVERNORS" == *"ondemand"* ]]; then
        GOVERNOR="ondemand"
    else
        GOVERNOR="performance"
    fi
    
    log "Selected CPU Governor: $GOVERNOR"

    # Apply immediately
    cpupower frequency-set -g $GOVERNOR 2>/dev/null || true

    # Create persistent service for cpupower
    cat > /etc/systemd/system/cpupower-config.service <<EOF
[Unit]
Description=Apply CPU performance settings
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/cpupower frequency-set -g $GOVERNOR

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable cpupower-config.service
    systemctl start cpupower-config.service
fi

if $INSTALL_INTEL_GPU; then
    log "Installing Intel GPU Drivers..."
    # libmfx1 is replaced by libmfx-gen1.2 in Debian 13 for Jasper Lake+
    safe_install intel-media-va-driver-non-free libmfx-gen1.2 intel-gpu-tools vainfo mesa-utils
    
    /usr/sbin/groupadd -f render
    /usr/sbin/groupadd -f video
    if [ -n "$NEW_USER" ] && [ "$NEW_USER" != "root" ]; then
        /usr/sbin/usermod -aG video,render "$NEW_USER"
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
    
    log "Setting I/O schedulers (optimized for media server)..."
    cat > /etc/udev/rules.d/60-ioschedulers.conf <<'EOF'
# I/O Scheduler optimization for Media Server

# NVMe drives - use 'none' scheduler (best for NVMe)
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/nr_requests}="1024"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/read_ahead_kb}="512"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/rq_affinity}="2"

# SSD drives - use 'mq-deadline' scheduler (best for SATA SSD with media files)
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/nr_requests}="512"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/read_ahead_kb}="512"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/rq_affinity}="2"

# HDD drives - use 'bfq' scheduler
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/read_ahead_kb}="1024"
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

# Add sbin to PATH for admin commands (ufw, sysctl, ip, etc.) highlighting
export PATH=$PATH:/usr/sbin:/sbin

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

# Go/NVM paths
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin

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
        
        mkdir -p "$user_home/.config"
        
        # Full Starship config - Modern & Clean
        cat > "$user_home/.config/starship.toml" <<'STARSHIP'
# Starship configuration - Modern & Clean
# Optimized for Mini PC Media Server

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

        # Compile .zshrc for faster loading (~50-100ms improvement)
        if [ "$username" = "root" ]; then
            zsh -c "zcompile $user_home/.zshrc" 2>/dev/null || true
        else
            su - "$username" -c "zsh -c 'zcompile ~/.zshrc'" 2>/dev/null || true
        fi

        chown -R "$username:$username" "$user_home/.zsh" "$user_home/.zshrc" "$user_home/.config"
        local zsh_path=$(which zsh)
        if [ -z "$zsh_path" ]; then
            error "Cannot find zsh binary"
            return 1
        fi
        chsh -s "$zsh_path" "$username"
    }

    # Ensure zsh is available before setup
    if ! command -v zsh &> /dev/null; then
        error "Zsh installation failed - zsh binary not found!"
        exit 1
    fi

    setup_zsh_for_user root
    [ -n "$NEW_USER" ] && [ "$NEW_USER" != "root" ] && setup_zsh_for_user "$NEW_USER"
fi

################################################################################
# 7. Go & Node.js
################################################################################
if $INSTALL_GO; then
    section "Step 7a: Go Installation"
    
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
    
    # Download checksum
    CHECKSUM=$(curl -fsSL "$GO_CHECKSUM_URL" 2>/dev/null | head -1 | awk '{print $1}')
    if [ -z "$CHECKSUM" ]; then
        error "Could not download Go checksum from $GO_CHECKSUM_URL"
        exit 1
    fi
    
    # Download binary
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
    
    # Extract
    tar -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -C /usr/local/
    
    # Create profile.d entry
    cat > /etc/profile.d/golang.sh <<'GOEOF'
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
GOEOF
    chmod +x /etc/profile.d/golang.sh
    
    # Add to .zshrc for root
    if [ -f /root/.zshrc ] && ! grep -q "GOROOT" /root/.zshrc; then
        cat >> /root/.zshrc <<'GORC'
# Go configuration
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
GORC
    fi
    
    # Add to .zshrc for new user
    USER_HOME=$(eval echo ~$NEW_USER)
    if [ -f "$USER_HOME/.zshrc" ] && ! grep -q "GOROOT" "$USER_HOME/.zshrc"; then
         cat >> "$USER_HOME/.zshrc" <<'GORC'
# Go configuration
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
GORC
        chown "$NEW_USER:$NEW_USER" "$USER_HOME/.zshrc"
    fi
    
    # Cleanup
    rm -f "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    log "Go ${GO_VERSION} installed successfully"
fi

if $INSTALL_NODE; then
    section "Step 7b: Node.js (NVM)"
    
    install_nvm_for_user() {
        local username=$1
        local user_home=$(eval echo ~$username)
        log "Installing NVM for user: $username"
        
        local nvm_install_script="/tmp/nvm_install_${username}.sh"
        
        cat > "$nvm_install_script" <<'NVMINSTALL'
#!/bin/bash
export HOME="$1"
export USER="$2"

# Get latest NVM version
NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
[ -z "$NVM_VERSION" ] && NVM_VERSION="v0.39.7"

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

nvm install --lts
nvm alias default lts/*
nvm use default
NVMINSTALL

        chmod +x "$nvm_install_script"
        
        if [ "$username" = "root" ]; then
            bash "$nvm_install_script" "$user_home" "$username"
        else
            su - "$username" -c "bash $nvm_install_script $user_home $username"
        fi
        
        # Add lazy load to zshrc
        if [ -f "$user_home/.zshrc" ] && ! grep -q "NVM_DIR" "$user_home/.zshrc"; then
             cat >> "$user_home/.zshrc" <<'NVMRC'
# NVM Lazy Load
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    nvm() { unset -f nvm node npm npx; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; nvm "$@"; }
    node() { unset -f nvm node npm npx; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; node "$@"; }
    npm() { unset -f nvm node npm npx; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; npm "$@"; }
    npx() { unset -f nvm node npm npx; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; npx "$@"; }
fi
NVMRC
             chown "$username:$username" "$user_home/.zshrc"
        fi
        
        rm -f "$nvm_install_script"
        log "NVM setup completed for $username"
    }
    
    install_nvm_for_user root
    [ -n "$NEW_USER" ] && [ "$NEW_USER" != "root" ] && install_nvm_for_user "$NEW_USER"
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

    # Check if Docker was actually installed
    if ! command -v docker &>/dev/null; then
        error "Docker installation failed - docker binary not found!"
        exit 1
    fi

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
    
    [ -n "$NEW_USER" ] && /usr/sbin/usermod -aG docker "$NEW_USER"
fi

################################################################################
# 9. Performance Tuning (Sysctl, Swap, Limits)
################################################################################
if $PERFORMANCE_TUNING; then
    section "Step 9: Performance Tuning"
    
    # RAM Detection
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    # Use awk for accurate calculation with rounding
    TOTAL_RAM_GB=$(LC_NUMERIC=C awk "BEGIN {printf \"%.2f\", $TOTAL_RAM_KB/1024/1024}")

    # Swap calculation (optimized for 16GB RAM)
    # For systems with 12GB+, use 4GB swap (no need for large swap with plenty RAM)
    if (( $(echo "$TOTAL_RAM_GB >= 12" | bc -l) )); then
        SWAP_SIZE=4
        log "Detected ${TOTAL_RAM_GB}GB RAM - using optimized 4GB swap"
    else
        # For smaller systems, use 50% rule
        SWAP_SIZE=$(LC_NUMERIC=C awk "BEGIN {printf \"%.0f\", ($TOTAL_RAM_GB / 2) + 0.5}")
        [ $SWAP_SIZE -lt 1 ] && SWAP_SIZE=2
    fi
    
    # Validated swap check and recreate logic (ported from optimize_vps.sh)
    if /usr/sbin/swapon --show | grep -q "/swapfile"; then
        log "Removing existing swap (to ensure correct size)..."
        /usr/sbin/swapoff /swapfile 2>/dev/null || true
        rm -f /swapfile
        sed -i '/\/swapfile/d' /etc/fstab
    fi

    # Check if remaining swap (from partitions or other sources) is sufficient
    # We use awk to sum up total existing swap bytes
    EXISTING_SWAP_BYTES=$(/usr/sbin/swapon --show --noheadings --bytes 2>/dev/null | awk '{sum+=$3} END {print sum}')
    # Default to 0 if command fails or empty
    EXISTING_SWAP_BYTES=${EXISTING_SWAP_BYTES:-0}
    
    # Calculate desired size in bytes (SWAP_SIZE is in GB)
    REQUIRED_BYTES=$((SWAP_SIZE * 1024 * 1024 * 1024))
    
    if [ "$EXISTING_SWAP_BYTES" -ge "$REQUIRED_BYTES" ]; then
        EXISTING_GB=$(LC_NUMERIC=C awk "BEGIN {printf \"%.1f\", $EXISTING_SWAP_BYTES/1024/1024/1024}")
        log "Sufficient existing swap detected (${EXISTING_GB}GB >= ${SWAP_SIZE}GB). Skipping /swapfile creation."
    else
        log "Creating ${SWAP_SIZE}GB Swap..."
        if ! /usr/bin/fallocate -l ${SWAP_SIZE}G /swapfile 2>/dev/null; then
            dd if=/dev/zero of=/swapfile bs=1G count=$SWAP_SIZE status=progress
        fi
        
        chmod 600 /swapfile
        /usr/sbin/mkswap /swapfile
        /usr/sbin/swapon /swapfile
        
        if ! grep -q "/swapfile" /etc/fstab; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
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

    # Sysctl (Media Server optimized for 16GB RAM + Intel N5095)
    cat > /etc/sysctl.d/99-minipc.conf <<EOF
# Mini PC Optimization - Media Server (16GB RAM, Intel N5095)
# Optimized for Plex/Jellyfin with QuickSync transcoding

# ============================================================================
# Network Performance - Enhanced for streaming
# ============================================================================

# TCP/UDP Buffer Sizes (optimized for 16GB RAM, media streaming)
net.core.rmem_default = 524288
net.core.wmem_default = 524288
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 262144 33554432
net.ipv4.tcp_wmem = 4096 262144 33554432

# Network Queues (for multiple concurrent streams)
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 16384

# TCP Performance
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 10240 65535

# TCP Fast Open (reduces streaming connection latency)
net.ipv4.tcp_fastopen = 3

# TCP Window Scaling & SACK (better for high-latency clients)
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# MTU Probing
net.ipv4.tcp_mtu_probing = 1

# TCP Orphan & TIME_WAIT limits
net.ipv4.tcp_max_orphans = 32768
net.ipv4.tcp_max_tw_buckets = 131072

# ============================================================================
# Virtual Memory - Optimized for 16GB RAM
# ============================================================================
vm.swappiness = 5
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
vm.min_free_kbytes = 131072
vm.overcommit_memory = 1
vm.zone_reclaim_mode = 0

# ============================================================================
# File System Performance (for large media files)
# ============================================================================
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1024

# ============================================================================
# Connection Tracking (for multiple streaming sessions)
# ============================================================================
net.netfilter.nf_conntrack_max = 262144
net.netfilter.nf_conntrack_tcp_timeout_established = 3600



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

EOF

    # Apply sysctl settings
    # Apply sysctl settings with error tolerance for missing parameters
    /usr/sbin/sysctl -e -p /etc/sysctl.d/99-minipc.conf 2>&1 | grep -v "cannot stat" | grep -v "No such file or directory" | grep -v "unknown key" || true
    log "Kernel parameters applied (some may be skipped if not supported by hardware)"

    # Limits (optimized for media server)
    cat > /etc/security/limits.d/99-minipc.conf <<EOF
# Mini PC System Limits - Media Server (16GB RAM)

# Open file limits (for media libraries and concurrent streams)
* soft nofile 262144
* hard nofile 262144
root soft nofile 262144
root hard nofile 262144

# Process limits
* soft nproc 32768
* hard nproc 32768

# Memory lock (for QuickSync transcoding)
* soft memlock unlimited
* hard memlock unlimited

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
        if systemctl is-enabled "$service" &>/dev/null; then
            systemctl disable "$service" &>/dev/null || true
            systemctl stop "$service" &>/dev/null || true
            log "Disabled $service"
        fi
    done
fi

################################################################################
# 11. Security (UFW, Auto-Updates)
################################################################################
if $CONFIGURE_SECURITY; then
    section "Step 11: Security"
    
    /usr/sbin/ufw default deny incoming
    /usr/sbin/ufw default allow outgoing
    /usr/sbin/ufw allow 22/tcp
    /usr/sbin/ufw allow 80/tcp
    /usr/sbin/ufw allow 443/tcp
    $INSTALL_SAMBA && /usr/sbin/ufw allow samba
    /usr/sbin/ufw --force enable
    
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
    
    # Check if /mnt/ssd exists
    if [ ! -d "/mnt/ssd" ]; then
        warn "Directory /mnt/ssd does not exist! Skipping Samba configuration."
        warn "Please mount your drive to /mnt/ssd and configure Samba manually later."
    else
        safe_install samba
        
        # Backup config
        [ ! -f /etc/samba/smb.conf.bak ] && cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
        
        # Add share if not exists (simple check)
        if ! grep -q "\[$SAMBA_SHARE_NAME\]" /etc/samba/smb.conf; then
            cat >> /etc/samba/smb.conf <<EOF

[$SAMBA_SHARE_NAME]
   path = /mnt/ssd
   browsable = yes
   writable = yes
   guest ok = no
   read only = no
   create mask = 0644
   directory mask = 0755
   valid users = $NEW_USER
EOF
        else
            warn "Share [$SAMBA_SHARE_NAME] might already exist in smb.conf"
        fi
        
        log "Samba configured. Please set SMB password for user: $NEW_USER"
        log "Note: This password can be different from system password."
        
        # Retry loop for password
        while ! smbpasswd -a "$NEW_USER"; do
            warn "Password setting failed (mismatch?). Please try again."
            echo ""
        done
        
        systemctl restart smbd
        log "Samba service restarted."
    fi
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

echo ""
if prompt_yn "Do you want to reboot now?" true; then
    log "Rebooting..."
    /usr/sbin/reboot
else
    warn "Please remember to reboot manually!"
fi