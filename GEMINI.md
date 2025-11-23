# Project Context: Linux Optimization Scripts

## Overview
This project provides comprehensive Bash scripts for optimizing Linux environments, specifically targeting:
*   **VPS Servers:** Debian 11/12/13 and Ubuntu 20.04+ (`optimize_vps.sh`)
*   **WSL2 Environments:** Debian 12/13 (`optimize_wsl2.sh`)

The scripts automate tasks such as kernel updates (XanMod for VPS), shell configuration (Zsh + Starship), Docker installation, security hardening (SSH, UFW), and development environment setup (Go, Node.js).

## Key Files

*   **`optimize_vps.sh`**: Main script for VPS optimization. Features system auto-detection, XanMod kernel installation, and SSH hardening.
*   **`optimize_wsl2.sh`**: Main script for WSL2 optimization. Features WSL2-specific configurations (systemd, wsl.conf), NVIDIA/CUDA support, and Windows integration.
*   **`README.md`**: Extensive project documentation, including comparison tables and known issues.
*   **`docs/`**: Contains detailed documentation for each environment (`README_VPS.md`, `README_WSL2.md`).
*   **`logs.log`**: Local log file (note: scripts also log to `/var/log/`).

## Usage

Scripts are intended to be run as `root` (or via `sudo`) on a fresh or existing installation.

### VPS
```bash
chmod +x optimize_vps.sh
sudo ./optimize_vps.sh
```

### WSL2
```bash
chmod +x optimize_wsl2.sh
sudo ./optimize_wsl2.sh
```

## Development Conventions

### Script Structure
*   **Language:** Bash
*   **Error Handling:** Scripts use `set -e` to exit immediately on error.
*   **Localization:** Scripts force `LC_ALL=C` and `LANG=C` to avoid locale issues.
*   **Logging:** Custom logging functions (`log`, `warn`, `error`, `info`) are used to print color-coded messages to the console and write to a log file (e.g., `/var/log/vps_optimization.log`).
*   **Modularity:** Functionality is broken down into helper functions (e.g., `package_available`, `safe_install`) and logical sections.

### Coding Style
*   **Indentation:** 4 spaces.
*   **Comments:** Extensive header comments and section separators are used to maintain readability.
*   **Variables:** Uppercase for global configuration/constants (e.g., `LOG_FILE`, colors).

## Known Issues & Fixes
Refer to `README.md` for the most up-to-date list of known issues, such as VSCode Terminal errors (`__vsc_update_env`) or npm permissions, which are automatically handled by the scripts.
