# arch-cinnamon-postinstall

**Use at your own risk, I'm not responsible if anything blows up. Always keep backups of important data and configuration files.**

A personal post-installation script for **Arch Linux + Cinnamon**, written with the help of AI.

This _could_ work with other DE too, especially other GTK-based ones. I have _not_ tested it with anything else other than Cinnamon, so YMMV.

The script automates the setup of a fresh Arch Linux installation with useful applications, system utilities, multimedia codecs, hardware drivers, and desktop customizations.

It is designed to be run as a normal user, not as root.

## Features

### System setup
- Enables color output and the Multilib repository in Pacman.
- Performs a full system upgrade.
- Installs essential build tools and utilities.
- Installs and configures `yay` for AUR packages.
- Enables Tailscale.

### Packages and applications

**System utilities**
- `base-devel`, `git`, `curl`, `unzip`, `pciutils`
- `gvfs`, `gvfs-mtp`, `gvfs-smb`, `gvfs-afc`
- `ntfs-3g`, `gnome-keyring`
- `xdg-utils`, `dconf`, `pavucontrol`
- `flatpak`, `tailscale`
- `snapd` (installed as a Pamac dependency; `snapd.socket` is enabled)

**Cinnamon applications and applets**
- Nemo extensions and file roller
- Sets Ptyxis as the system-wide default Cinnamon terminal through dconf. Users can override it in their own preferences; new users and users without an override inherit Ptyxis.
- Ptyxis (default Cinnamon terminal; GNOME Terminal is not installed)
- Xed and Xreader
- GNOME System Monitor
- GNOME Disk Utility and GParted
- GNOME Screenshot
- Xviewer and GNOME Calculator
- Spicy Clipboard Manager Cinnamon applet

**Spicy Clipboard Manager**
- Downloads and installs the applet from Cinnamon Spices for the current user.
- Installs its `yad`, `xclip` and `python` dependencies.
- Enables the applet and places it first in the right-hand zone of `panel1`, shifting existing applets in that zone to make room.
- If automatic panel configuration fails, the applet can be added manually through **System Settings → Applets**.

**Fonts**
- Noto Fonts
- Noto Emoji
- Noto CJK
- Liberation, DejaVu and Croscore fonts
- Carlito and Caladea

**Multimedia**
- VLC
- FFmpeg
- GStreamer plugins: Base, Good, Bad, Ugly and Libav
- Optional VLC plugin bundle

**Desktop applications**
- FileZilla (FTP/SFTP client)
- Steam (native Arch package from Multilib; not Flatpak)
- LibreOffice
- GIMP
- Inkscape
- Discord
- Vivaldi
- Google Chrome
- LibreWolf (AUR, with Flatpak fallback)
- Pamac (`pamac-all` from the AUR), with support for official repositories, AUR, Flatpak and Snap

### Pamac and software sources

- Installs `pamac-all` from the AUR, providing integration for official Arch repositories, AUR, Flatpak and Snap.
- Enables AUR support and AUR update checks in `/etc/pamac.conf`.
- Enables the socket-activated Snap daemon with `snapd.socket` and creates `/snap` for classic Snap packages when that path does not already exist.
- Removes conflicting older Pamac frontend/library packages installed by earlier versions of this script before installing `pamac-all`.

### Hardware detection and drivers

The script detects installed hardware and selects packages accordingly.

- Detects Intel, AMD and NVIDIA graphics hardware.
- Installs Mesa and Vulkan drivers for Intel and AMD GPUs.
- Installs Intel media and AMD video acceleration packages when available.
- Detects Intel and AMD CPUs and installs the corresponding microcode.
- Detects installed kernel package bases.
- Checks for matching kernel headers when DKMS drivers are needed.
- Supports NVIDIA open kernel modules for Turing and newer GPUs.
- Offers the NVIDIA 580xx legacy driver branch for Maxwell, Pascal and Volta GPUs.

NVIDIA driver installation is interactive by default. Check your GPU generation before selecting a driver.

### Dark theme and desktop customization

The script configures a system-wide dark appearance:

- Installs the CBlack Cinnamon theme.
- Configures GTK3 applications to prefer dark mode.
- Sets the GNOME/libadwaita dark appearance preference.
- Configures Cinnamon/XApp's dark color-scheme preference.
- Installs XDG desktop portal backends for Cinnamon compatibility.
- Configures Qt5 and Qt6 through qt5ct, qt6ct and Kvantum.
- Installs the Adwaita Dark GTK3 Flatpak theme extension.
- Applies system-wide dconf settings and locks selected appearance preferences.

The goal is to provide a consistent dark appearance across GTK, libadwaita, Qt and Flatpak applications. Individual applications may still require their own theme support or configuration.

### Privacy settings

- Sets private home directory permissions.
- Configures a restrictive default umask (`077`).
- Disables recent-file tracking.
- Disables thumbnail caching through dconf settings.
- Removes the current user's recent-files list.

## Requirements

- A working Arch Linux installation.
- Cinnamon already installed.
- Internet connection.
- `sudo` privileges.
- An x86_64 system for the NVIDIA driver options provided by the script.

## Usage

Clone the repository:

```bash
git clone https://github.com/estevaojneto/arch-cinnamon-postinstall.git
cd arch-cinnamon-postinstall
```

Make the script executable:

```bash
chmod +x arch-cinnamon-postinstall.sh
```

Run it as your normal user:

```bash
./arch-cinnamon-postinstall.sh
```

Do **not** run it with `sudo`. The script requests administrative privileges when needed.

You may be prompted to select an NVIDIA driver and whether to reboot at the end.

## Configuration

A few options can be changed near the beginning of the script:

```bash
NVIDIA_MODE="ask"
DARK_MODE=true
DISABLE_RECENT_FILES=true
SPICES_THEME="CBlack"
```

- `NVIDIA_MODE`: NVIDIA driver selection (`ask`, `open`, `legacy580` or `none`).
- `DARK_MODE`: Enable or disable dark-theme configuration.
- `DISABLE_RECENT_FILES`: Enable or disable recent-file privacy settings.
- `SPICES_THEME`: Cinnamon theme name. Set to an empty string to skip theme installation.

## Important notes

- This is a personal post-installation script, not an official Arch Linux installer.
- It modifies system-wide configuration files and installs packages.
- It enables Multilib and installs software from both official repositories and the AUR.
- Review the script before running it.
- Some optional packages may not be available in every repository configuration.
- A reboot or logout may be necessary for all changes to take effect.

## Disclaimer

This project was created for personal use with assistance from AI. It is provided as-is, without guarantees or official support.

**Use at your own risk, I'm not responsible if anything blows up. Always keep backups of important data and configuration files.**
