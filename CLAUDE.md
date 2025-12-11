# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains specialized Bash scripts for optimizing Linux systems across three different environments:

- **VPS Optimization** (`optimize_vps.sh`) - Debian 11/12/13 and Ubuntu 20.04+ servers
- **WSL2 Optimization** (`optimize_wsl2.sh`) - Debian 12/13 on Windows Subsystem for Linux 2
- **Mini PC Optimization** (`optimize_mini_pc.sh`) - Intel N5095/Jasper Lake home servers on Debian 13

Each script is a comprehensive, interactive installation tool that handles system updates, kernel installation, shell configuration, development tools, Docker setup, and security hardening.

## Running and Testing Scripts

### Testing Scripts
```bash
# NEVER run these scripts in the development environment
# These scripts perform system-level modifications and should only be tested on:
# - Fresh VPS installations
# - WSL2 instances
# - Dedicated mini PC hardware

# To verify syntax without execution:
bash -n optimize_vps.sh
bash -n optimize_wsl2.sh
bash -n optimize_mini_pc.sh

# To test individual functions, extract them to a separate test script
```

### Quick Installation URLs
Scripts are designed to be run directly from GitHub:
```bash
# VPS
bash <(curl -s https://raw.githubusercontent.com/snaplyze/optimize-linux/refs/heads/main/optimize_vps.sh)

# WSL2
bash <(curl -s https://raw.githubusercontent.com/snaplyze/optimize-linux/refs/heads/main/optimize_wsl2.sh)

# Mini PC
bash <(curl -s https://raw.githubusercontent.com/snaplyze/optimize-linux/refs/heads/main/optimize_mini_pc.sh)
```

## Architecture and Code Structure

### Script Design Philosophy

All three scripts follow a consistent architecture pattern:

1. **Initialization Block** - Locale forcing, error handling (`set -e`), color definitions, logging setup
2. **Helper Functions** - Package availability checking, safe installation, user prompts, WSL detection
3. **OS Detection** - Validates Debian/Ubuntu version compatibility
4. **Interactive Menu** - Users select which components to install (VPS: 25 steps, WSL2: 17 steps, Mini PC: varies)
5. **Sequential Execution** - Numbered sections that execute chosen components
6. **Final Summary** - Displays what was installed and next steps

### Key Architectural Patterns

#### Safe Package Installation
All scripts use `safe_install()` function instead of direct `apt-get install`:
```bash
safe_install package1 package2 package3
```
This function:
- Checks package availability in repositories before attempting installation
- Handles missing packages gracefully (Debian 13 compatibility)
- Logs warnings for unavailable packages
- Only installs what's available

#### Logging System
Four-tier logging with color coding:
- `log()` - Success messages (green)
- `warn()` - Warnings (yellow)
- `error()` - Errors (red)
- `info()` - Information (blue)

All messages go to both stdout and log files:
- VPS: `/var/log/vps_optimization.log`
- WSL2: `/var/log/wsl2_optimization.log`
- Mini PC: `/var/log/minipc_optimization.log`

#### Multi-User Configuration
Scripts apply configurations to multiple user contexts:
- `root` user
- Newly created user (`NEW_USER`)
- Docker user (`DOCKER_USER`, VPS only)

This pattern is used for:
- Zsh configuration
- Starship prompt
- NVM/Node.js installation
- Go environment variables

### Environment-Specific Features

#### VPS (`optimize_vps.sh`)
- **XanMod Kernel Auto-Detection**: Detects CPU capabilities (x64v1-v4) and installs optimal kernel variant
- **SSH Hardening**: Disables root login, enforces key-based auth, configures Fail2Ban
- **UFW Firewall**: With iptables-legacy mode for Debian 13 compatibility
- **Swap Calculation**: Auto-calculates swap size based on RAM (formula: `RAM < 2GB ? RAM*2 : RAM+2GB`)

#### WSL2 (`optimize_wsl2.sh`)
- **systemd Integration**: Configures WSL2 to use systemd (`/etc/wsl.conf`)
- **Windows Integration Functions**: `explorer()`, `cmd()`, `powershell()` bash functions
- **Docker Auto-start**: Configures Docker to start automatically with WSL2
- **NVIDIA/CUDA Support**: Optional NVIDIA Container Toolkit and CUDA installation
- **WSL Mount Path**: Uses standard `/mnt/c/` instead of `/c/`

#### Mini PC (`optimize_mini_pc.sh`)
- **Intel N5095 Specific**: XanMod x64v2 kernel (no AVX/AVX2 but supports SSE4.2)
- **CPU Governor**: Sets `schedutil` for balance between performance and thermal management
- **Intel GPU Drivers**: Installs `intel-media-va-driver-non-free` for QuickSync hardware transcoding
- **Storage Optimization**: Configures I/O schedulers (NVMe: `none`, SATA SSD: `mq-deadline`)
- **Media Server Ready**: Adds user to `render` and `video` groups, includes monitoring utilities

### Critical Code Sections

#### Go Installation Pattern
All scripts install the latest Go version with SHA256 verification:
```bash
ARCH=$(dpkg --print-architecture)
GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n1)
curl -OL "https://go.dev/dl/${GO_VERSION}.linux-${ARCH}.tar.gz"
curl -OL "https://go.dev/dl/${GO_VERSION}.linux-${ARCH}.tar.gz.sha256"
# SHA256 verification logic
rm -rf /usr/local/go && tar -C /usr/local -xzf "${GO_VERSION}.linux-${ARCH}.tar.gz"
```

#### NVM Installation Pattern
Uses GitHub API to get latest NVM version and installs for each user:
```bash
NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
# Install as each user (not root) to avoid npm permission issues
sudo -u $USERNAME bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | bash"
```

#### VSCode Terminal Fix
All scripts include a fix for the `__vsc_update_env` error in VS Code Remote extensions:
```zsh
# Only enable KSH_ARRAYS outside of VS Code terminal
[[ -z "$VSCODE_INJECTION" ]] && setopt KSH_ARRAYS
```

## Common Development Tasks

### Modifying Script Functionality

When adding new features:

1. **Add to Interactive Menu** - Update the section number and menu display
2. **Create Numbered Section** - Follow the `section "Step X: Description"` pattern
3. **Use Safe Installation** - Always use `safe_install()` instead of `apt-get install`
4. **Add Logging** - Use appropriate `log()`, `warn()`, `error()`, `info()` calls
5. **Update Documentation** - Modify corresponding `docs/README_*.md` file
6. **Update Main README** - Add to feature comparison table if applicable

### Version Bumping

Version numbers are referenced in:
- Script comments (header section)
- README.md (multiple locations)
- Documentation files in `docs/`

Current versions:
- VPS: v2.1.0
- WSL2: v2.1.2
- Mini PC: First release

### Testing Checklist for Changes

- [ ] Run `bash -n script.sh` to check syntax
- [ ] Verify `safe_install()` is used for all package installations
- [ ] Check that new configurations apply to all relevant users (root, NEW_USER, DOCKER_USER)
- [ ] Ensure logging is added for new sections
- [ ] Test on clean installation of target OS
- [ ] Update version number and changelog
- [ ] Update documentation

## Known Issues and Fixes

### Debian 13 (Trixie) Compatibility
Debian 13 removed several packages from repositories. Scripts handle this via:
- `safe_install()` function that checks availability
- iptables-legacy mode for UFW
- Package availability checks before installation

### VSCode Remote Terminal Error
Fixed automatically in all scripts. The error `__vsc_update_env:6: key: attempt to set associative array to scalar` occurs with Zsh when using VS Code Remote extensions (SSH/WSL/Tunnels).

Fix applied: Conditional `KSH_ARRAYS` option only when not in VS Code terminal.

### npm EACCES Errors
Fixed by installing NVM as the target user (not root), ensuring correct permissions for `~/.npm` and `~/.nvm` directories.

### WSL2 Mount Path Change
WSL2 v2.1.2+ uses standard `/mnt/c/` instead of `/c/` for Windows drive mounting. Scripts configure this via `/etc/wsl.conf`.

## Documentation Structure

- `README.md` - Main project documentation, feature comparison, quick start
- `docs/README_VPS.md` - Detailed VPS optimization guide
- `docs/README_WSL2.md` - Detailed WSL2 optimization guide
- `docs/README_MINI_PC.md` - Detailed Mini PC optimization guide (Intel N5095)
- `GEMINI.md` - Legacy context file for Gemini AI
- `CLAUDE.md` - This file

## Important Notes for Code Modifications

1. **Never break backward compatibility** - Users may run old scripts, ensure new changes don't break existing installations
2. **Preserve the interactive menu system** - Users should always be able to select which components to install
3. **Maintain multi-user support** - All shell/dev tool configurations must apply to root, NEW_USER, and DOCKER_USER
4. **Test on target OS versions** - VPS (Debian 11/12/13, Ubuntu 20.04+), WSL2 (Debian 12/13), Mini PC (Debian 13)
5. **Use locale-agnostic code** - Scripts force `LC_ALL=C` to avoid locale issues
6. **Follow existing logging patterns** - Consistent color-coded output helps users track progress
7. **Document all fixes** - Known issues and their solutions should be documented in README.md
