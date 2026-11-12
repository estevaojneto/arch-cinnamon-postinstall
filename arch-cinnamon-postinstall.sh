
#!/usr/bin/env bash
# =============================================================================
# Arch Linux + Cinnamon post-install setup
#
# Run as your NORMAL user (not root):
#     chmod +x arch-cinnamon-postinstall.sh
#     ./arch-cinnamon-postinstall.sh
#
# Assumes: base Arch install, working internet, Cinnamon already installed.
# Safe to re-run: uses --needed and idempotent configuration checks.
# =============================================================================
set -uo pipefail

# ------------------------------ CONFIG ---------------------------------------
NVIDIA_MODE="ask"           # ask | open | legacy580 | none
                            # open      = Turing (RTX 20xx / GTX 16xx) and newer
                            # legacy580 = Maxwell / Pascal / Volta (GTX 750/900/10xx etc.), AUR
DARK_MODE=true
DISABLE_RECENT_FILES=true
SPICES_THEME="CBlack"       # Cinnamon Spices theme name; empty to skip
# -----------------------------------------------------------------------------

FAILED=()
c_blue=$'\e[1;34m'; c_yel=$'\e[1;33m'
c_red=$'\e[1;31m'; c_off=$'\e[0m'

info()  { echo "${c_blue}==>${c_off} $*"; }
warn()  { echo "${c_yel}[warn]${c_off} $*"; }
fail()  { echo "${c_red}[fail]${c_off} $*"; FAILED+=("$*"); }

pac()     { sudo pacman -S --needed --noconfirm "$@"; }
pac_try() {
    if pac "$@"; then
        return 0
    fi
    fail "pacman: $*"
    return 1
}

pac_opt() {
    local p
    for p in "$@"; do
        if pacman -Si "$p" &>/dev/null; then
            pac "$p" || fail "pacman: $p"
        else
            warn "package '$p' not in repos, skipping"
        fi
    done
}

aur() {
    yay -S --needed --noconfirm --removemake \
        --answerclean None --answerdiff None "$@"
}
aur_try() {
    if aur "$@"; then
        return 0
    fi
    fail "AUR: $*"
    return 1
}

# Ensure the system dconf database is included in the user profile.
ensure_dconf_profile() {
    sudo mkdir -p /etc/dconf/profile /etc/dconf/db/local.d

    if [[ ! -f /etc/dconf/profile/user ]]; then
        printf 'user-db:user\nsystem-db:local\n' |
            sudo tee /etc/dconf/profile/user >/dev/null
    elif ! grep -qx 'system-db:local' /etc/dconf/profile/user; then
        echo 'system-db:local' |
            sudo tee -a /etc/dconf/profile/user >/dev/null
    fi
}

# --------------------------- sanity checks -----------------------------------
if [[ $EUID -eq 0 ]]; then
    echo "Run as a normal user, not root." >&2
    exit 1
fi

command -v pacman >/dev/null || {
    echo "This is for Arch Linux." >&2
    exit 1
}

ping -c1 -W3 archlinux.org &>/dev/null || {
    echo "No internet connection." >&2
    exit 1
}

sudo -v || exit 1

( while true; do
    sudo -n true
    sleep 50
    kill -0 "$$" 2>/dev/null || exit
done ) &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT

# --------------------------- pacman config -----------------------------------
info "Configuring pacman (Color, multilib)"

sudo sed -i 's/^#Color/Color/' /etc/pacman.conf

if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
fi

info "Full system upgrade"
sudo pacman -Syu --noconfirm || fail "system upgrade"

# --------------------------- base tooling ------------------------------------
info "Installing build tools"
pac_try base-devel git curl unzip pciutils

# --------------------------- yay ---------------------------------------------
if ! command -v yay >/dev/null; then
    info "Bootstrapping yay"

    tmp=$(mktemp -d)

    if git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"; then
        (
            cd "$tmp/yay-bin" &&
            makepkg -si --noconfirm
        ) || fail "yay bootstrap"
    else
        fail "could not clone yay-bin"
    fi

    rm -rf "$tmp"
fi

command -v yay >/dev/null || {
    echo "yay is required. Aborting."
    exit 1
}

# --------------------------- system essentials -------------------------------
info "Filesystem/device support and tools"
pac_try gvfs gvfs-mtp gvfs-smb gvfs-afc ntfs-3g gnome-keyring
pac_try xdg-utils dconf pavucontrol

# Cinnamon-compatible Flatpak portal backends. The XApp backend exposes
# Cinnamon's org.x.apps.portal color-scheme preference to sandboxed apps.
pac_try xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-xapp

if systemctl is-enabled --quiet bluetooth.service 2>/dev/null; then
    info "Bluetooth service detected, adding Blueman"
    pac_try blueman
fi

info "Utilities"
pac_try xorg-xdpyinfo

if pacman -Si neofetch &>/dev/null; then
    pac_try neofetch
else
    aur_try neofetch
fi

info "Tailscale"
pac_try tailscale
sudo systemctl enable --now tailscaled.service || fail "tailscaled service"

# ---------------------- Spicy Clipboard Manager ------------------------------
info "Installing Spicy Clipboard Manager Cinnamon applet"

# Spicy Clipboard Manager is a Cinnamon Spices applet, not an Arch package.
# yad provides its history/editor dialogs; xclip provides X11 clipboard and
# image support. No Wayland-specific tooling is needed for this X11 setup.
pac_try yad xclip python

install_spicy_clipboard_applet() {
    local uuid="spicy-clipboard-applet@Twilight0"
    local url="https://cinnamon-spices.linuxmint.com/files/applets/spicy-clipboard-applet%40Twilight0.zip"
    local tmpz tmpd target

    tmpz=$(mktemp --suffix=.zip) || return 1
    tmpd=$(mktemp -d) || {
        rm -f "$tmpz"
        return 1
    }
    target="$HOME/.local/share/cinnamon/applets/$uuid"

    if ! curl -fL "$url" -o "$tmpz" ||
       ! unzip -oq "$tmpz" -d "$tmpd" ||
       [[ ! -f "$tmpd/$uuid/metadata.json" ]]; then
        rm -rf "$tmpz" "$tmpd"
        fail "could not download or validate Spicy Clipboard Manager"
        return 1
    fi

    mkdir -p "$target" || {
        rm -rf "$tmpz" "$tmpd"
        fail "could not create Cinnamon applet directory"
        return 1
    }

    cp -a "$tmpd/$uuid/." "$target/" || {
        rm -rf "$tmpz" "$tmpd"
        fail "could not install Spicy Clipboard Manager files"
        return 1
    }

    rm -rf "$tmpz" "$tmpd"
    info "Spicy Clipboard Manager installed for user $USER"
}

if install_spicy_clipboard_applet; then
    # Cinnamon stores applet placement in org.cinnamon/enabled-applets.
    # Put this applet first in panel1's right-hand zone (the tray side), while
    # preserving the relative order of the other right-side applets.
    if command -v gsettings >/dev/null &&
       gsettings list-schemas | grep -qx 'org.cinnamon'; then
        if python3 - <<'PY'
import ast
import subprocess
import sys

schema = "org.cinnamon"
key = "enabled-applets"
uuid = "spicy-clipboard-applet@Twilight0"

try:
    raw = subprocess.check_output(
        ["gsettings", "get", schema, key], text=True
    ).strip()
    entries = ast.literal_eval(raw)
    if not isinstance(entries, list) or not all(isinstance(x, str) for x in entries):
        raise ValueError("unexpected enabled-applets value")

    right_side = []
    kept = []
    for entry in entries:
        fields = entry.split(":")
        if len(fields) >= 5 and fields[3] == uuid:
            continue
        if len(fields) >= 5 and fields[0] == "panel1" and fields[1] == "right":
            try:
                order = int(fields[2])
            except ValueError:
                order = 10**9
            right_side.append((order, entry, fields))
        else:
            kept.append(entry)

    # Keep existing right-zone applets in their current order, shifting them
    # one position to make room for Spicy Clipboard at order zero.
    right_side.sort(key=lambda item: item[0])
    shifted = []
    for new_order, (_, _, fields) in enumerate(right_side, start=1):
        fields[2] = str(new_order)
        shifted.append(":".join(fields))

    new_entry = f"panel1:right:0:{uuid}:0"
    updated = kept + [new_entry] + shifted

    subprocess.run(
        ["gsettings", "set", schema, key, repr(updated)],
        check=True
    )
    print("Spicy Clipboard Manager placed first in panel1's right zone.")
except Exception as exc:
    print(f"Could not configure Cinnamon panel placement: {exc}", file=sys.stderr)
    sys.exit(1)
PY
        then
            :
        else
            warn "Spicy Clipboard Manager is installed, but panel placement could not be configured. Add it through System Settings -> Applets."
        fi
    else
        warn "Cinnamon settings are unavailable in this session; add Spicy Clipboard Manager to the panel after logging in."
    fi
else
    warn "Spicy Clipboard Manager installation did not complete."
fi

# --------------------------- fonts -------------------------------------------
info "Fonts"
pac_try noto-fonts noto-fonts-emoji noto-fonts-cjk \
    ttf-liberation ttf-dejavu ttf-croscore ttf-carlito ttf-caladea

# --------------------------- Cinnamon companions -----------------------------
info "Cinnamon companion apps"
pac_try nemo-fileroller file-roller \
    gnome-terminal xed xreader \
    gnome-system-monitor gnome-disk-utility gparted gnome-screenshot

pac_try xviewer gnome-calculator

# --------------------- hardware, kernels + graphics ---------------------------
info "Detecting CPU, GPUs and installed kernels"

GPU_LINES=$(lspci -nn 2>/dev/null |
    grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)
GPU_DETAILS=$(lspci -nnk 2>/dev/null | awk '
    /VGA compatible controller|3D controller|Display controller/ { show=1; n=0 }
    show { print; n++; if (n >= 4) show=0 }
')

if [[ -n "$GPU_LINES" ]]; then
    printf '%s\n' "$GPU_DETAILS"
else
    warn "No PCI display controller was found by lspci."
fi

HAS_INTEL_GPU=false
HAS_AMD_GPU=false
HAS_NVIDIA_GPU=false

grep -Eiq '\[8086:' <<<"$GPU_LINES" && HAS_INTEL_GPU=true
grep -Eiq '\[1002:' <<<"$GPU_LINES" && HAS_AMD_GPU=true
grep -Eiq '\[10de:' <<<"$GPU_LINES" && HAS_NVIDIA_GPU=true

# CPU microcode is independent of the graphics driver. Installing the package
# does not rewrite the bootloader; see the message below for the initrd entry.
CPU_VENDOR=$(awk -F': ' '/^vendor_id[[:space:]]*:/ { print $2; exit }' /proc/cpuinfo 2>/dev/null || true)
case "$CPU_VENDOR" in
    GenuineIntel)
        info "Intel CPU detected; installing Intel microcode"
        pac_try intel-ucode || warn "Intel microcode package did not install"
        warn "Verify early microcode loading: GRUB may need grub-mkconfig; systemd-boot entries need intel-ucode.img before the main initramfs."
        ;;
    AuthenticAMD)
        info "AMD CPU detected; installing AMD microcode"
        pac_try amd-ucode || warn "AMD microcode package did not install"
        warn "Verify early microcode loading: GRUB may need grub-mkconfig; systemd-boot entries need amd-ucode.img before the main initramfs."
        ;;
    *)
        warn "CPU vendor not recognized; skipping CPU microcode package."
        ;;
esac

# Intel and AMD use the in-kernel DRM drivers plus Mesa userspace. No separate
# proprietary kernel driver is required for these GPUs on a normal Arch system.
if $HAS_INTEL_GPU || $HAS_AMD_GPU; then
    info "Installing Mesa and Vulkan userspace for Intel/AMD graphics"
    pac_try mesa vulkan-icd-loader
    pac_try lib32-mesa lib32-vulkan-icd-loader
fi

if $HAS_AMD_GPU; then
    info "AMD GPU detected; installing RADV Vulkan support"
    pac_try vulkan-radeon
    pac_try lib32-vulkan-radeon
    pac_opt libva-mesa-driver mesa-vdpau
fi

if $HAS_INTEL_GPU; then
    info "Intel GPU detected; installing Intel Vulkan and media support"
    pac_try vulkan-intel
    pac_try lib32-vulkan-intel
    pac_opt intel-media-driver
fi

# Read pkgbase from each installed kernel's module directory. This also sees
# third-party kernels (for example linux-cachyos) instead of assuming only the
# four stock Arch kernel package names exist.
KERNEL_BASES=()
detect_kernel_bases() {
    local f base p
    local -A seen=()
    local -a module_pkgbase_files=()

    shopt -s nullglob
    module_pkgbase_files=(/usr/lib/modules/*/pkgbase)
    shopt -u nullglob

    for f in "${module_pkgbase_files[@]}"; do
        [[ -r "$f" ]] || continue
        IFS= read -r base < "$f" || true
        [[ -n "$base" ]] && seen["$base"]=1
    done

    # Fallback for installations where pkgbase files are absent.
    for p in linux linux-lts linux-zen linux-hardened; do
        if pacman -Qq "$p" &>/dev/null; then
            seen["$p"]=1
        fi
    done

    KERNEL_BASES=()
    if ((${#seen[@]})); then
        mapfile -t KERNEL_BASES < <(printf '%s\n' "${!seen[@]}" | sort -u)
    fi
}

ensure_kernel_headers() {
    local base header
    local -a headers_to_install=()

    for base in "${KERNEL_BASES[@]}"; do
        header="${base}-headers"
        if pacman -Qq "$header" &>/dev/null; then
            continue
        fi
        if pacman -Si "$header" &>/dev/null; then
            headers_to_install+=("$header")
        else
            fail "no installed or repository header package found for kernel '$base' ($header)"
            return 1
        fi
    done

    if ((${#headers_to_install[@]})); then
        pac_try "${headers_to_install[@]}" || return 1
    fi

    # Refuse to proceed when a detected kernel still lacks its build link.
    local module_dir
    shopt -s nullglob
    for module_dir in /usr/lib/modules/*; do
        [[ -r "$module_dir/pkgbase" ]] || continue
        if [[ ! -e "$module_dir/build" ]]; then
            warn "Missing kernel build directory: $module_dir/build"
            shopt -u nullglob
            fail "kernel headers are not ready for ${module_dir##*/}"
            return 1
        fi
    done
    shopt -u nullglob
}

install_nvidia() {
    local mode="$1" base all_stock=true
    local -a driver_pkgs=()

    if [[ "$(uname -m)" != "x86_64" ]]; then
        fail "official NVIDIA packages selected here require x86_64"
        return 1
    fi

    detect_kernel_bases
    if ((${#KERNEL_BASES[@]} == 0)); then
        fail "could not identify an installed kernel; refusing to install NVIDIA modules"
        return 1
    fi

    info "Detected kernel package bases: ${KERNEL_BASES[*]}"

    # Prebuilt packages exist for the stock linux and linux-lts kernels. If any
    # other kernel is installed, use DKMS so one driver build covers all kernels.
    for base in "${KERNEL_BASES[@]}"; do
        case "$base" in
            linux|linux-lts) ;;
            *) all_stock=false ;;
        esac
    done

    case "$mode" in
        open)
            info "NVIDIA open kernel modules selected (Turing and newer)"
            if $all_stock; then
                for base in "${KERNEL_BASES[@]}"; do
                    case "$base" in
                        linux) driver_pkgs+=(nvidia-open) ;;
                        linux-lts) driver_pkgs+=(nvidia-open-lts) ;;
                    esac
                done
            else
                ensure_kernel_headers || return 1
                driver_pkgs+=(nvidia-open-dkms)
            fi
            driver_pkgs+=(nvidia-utils lib32-nvidia-utils nvidia-settings)
            pac_try "${driver_pkgs[@]}" || return 1
            ;;

        legacy580)
            info "NVIDIA 580xx proprietary legacy branch selected (Maxwell/Pascal/Volta)"
            ensure_kernel_headers || return 1
            aur_try nvidia-580xx-dkms nvidia-580xx-utils \
                lib32-nvidia-580xx-utils nvidia-580xx-settings || return 1
            ;;

        *)
            warn "Unknown NVIDIA_MODE '$mode'; NVIDIA driver installation skipped"
            return 1
            ;;
    esac

    return 0
}

nvidia_driver_present=false
if pacman -Qq 2>/dev/null | grep -Eq \
    '^(nvidia-open|nvidia-open-lts|nvidia-open-dkms|nvidia-580xx-dkms|nvidia-470xx-dkms|nvidia-dkms|nvidia|nvidia-lts)$'; then
    nvidia_driver_present=true
fi

if $HAS_NVIDIA_GPU; then
    if $nvidia_driver_present; then
        info "An NVIDIA kernel driver package is already installed; leaving it in place"
    else
        if [[ "$NVIDIA_MODE" == "ask" ]]; then
            echo
            echo "NVIDIA GPU detected. Choose a driver branch based on the GPU generation:"
            echo "  1) open      - Turing and newer (RTX 20xx, GTX 16xx, and newer)"
            echo "  2) legacy580 - Maxwell / Pascal / Volta (GTX 750/900/10xx etc.), AUR"
            echo "  3) skip      - leave the open-source nouveau driver in place"
            echo ""
            warn "Check the exact GPU generation before choosing; Kepler and older cards need separate legacy-driver evaluation (the 470xx branch is unsupported)."
            read -rp "Choice [1/2/3, default 3]: " ans

            case "$ans" in
                1) NVIDIA_MODE=open ;;
                2) NVIDIA_MODE=legacy580 ;;
                *) NVIDIA_MODE=none ;;
            esac
        fi

        case "$NVIDIA_MODE" in
            open|legacy580)
                if install_nvidia "$NVIDIA_MODE"; then
                    nvidia_driver_present=true
                else
                    warn "NVIDIA driver was not installed; leaving the current graphics configuration unchanged."
                fi
                ;;
            none)
                info "NVIDIA driver installation skipped by configuration"
                ;;
            *)
                warn "Unsupported NVIDIA_MODE '$NVIDIA_MODE'; skipping NVIDIA driver installation"
                ;;
        esac
    fi

    # DRM modesetting is useful for modern NVIDIA Wayland/X11 paths. Do not
    # edit mkinitcpio HOOKS or blacklist nouveau automatically: that can remove
    # the fallback graphics driver if the proprietary driver fails to load.
    if $nvidia_driver_present; then
        sudo install -d /etc/modprobe.d
        printf 'options nvidia_drm modeset=1\n' |
            sudo tee /etc/modprobe.d/nvidia.conf >/dev/null ||
            fail "writing NVIDIA DRM modesetting configuration"
    fi
else
    info "No NVIDIA GPU detected; skipping NVIDIA driver installation"
fi

# --------------------------- media + codecs ----------------------------------
info "VLC and codecs"
pac_try vlc ffmpeg gst-plugins-base gst-plugins-good \
    gst-plugins-bad gst-plugins-ugly gst-libav
pac_opt vlc-plugins-all

# --------------------------- applications ------------------------------------
info "Office, graphics, chat"
pac_try filezilla
pac_try steam
pac_try libreoffice-fresh hunspell-en_us
pac_try gimp inkscape discord

info "Vivaldi"
pac_try vivaldi
pac_opt vivaldi-ffmpeg-codecs

info "Google Chrome (AUR)"
aur_try google-chrome

info "LibreWolf (AUR, Flatpak fallback)"

if ! aur librewolf-bin; then
    warn "LibreWolf AUR build failed, falling back to Flatpak"
    LIBREWOLF_FLATPAK=true
else
    LIBREWOLF_FLATPAK=false
fi

# --------------------------- Flatpak -----------------------------------------
info "Flatpak + Flathub"

pac_try flatpak

sudo flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo \
    || fail "flathub remote"

if $LIBREWOLF_FLATPAK; then
    sudo flatpak install -y flathub io.gitlab.librewolf-community \
        || fail "flatpak librewolf"
fi

# --------------------------- Pamac -------------------------------------------
info "Pamac (software center: AUR + Flatpak + Snap)"

# Remove older Pamac frontends/libraries before installing pamac-all.
# Do not use -Rdd: normal dependency resolution is safer.
old_pamac=()

for p in pamac-aur libpamac-aur pamac-flatpak libpamac-flatpak; do
    if pacman -Qq "$p" &>/dev/null; then
        old_pamac+=("$p")
    fi
done

pamac_ready=true

if ((${#old_pamac[@]})); then
    if sudo pacman -R --noconfirm "${old_pamac[@]}"; then
        info "Removed conflicting older Pamac packages"
    else
        fail "removing old Pamac packages; skipping pamac-all"
        pamac_ready=false
    fi
fi

# pamac-all provides integration for official repositories, AUR, Flatpak and Snap.
# Its dependencies include the Snap daemon.
if $pamac_ready; then
    if aur pamac-all; then
        info "pamac-all installed"
    else
        fail "AUR: pamac-all"
        pamac_ready=false
    fi
fi

# Enable Snap's socket-activated daemon when the package is installed.
if $pamac_ready && pacman -Qq snapd &>/dev/null; then
    sudo systemctl enable --now snapd.socket ||
        fail "enabling snapd.socket"

    # This conventional path is needed by some classic Snaps.
    if [[ ! -e /snap && ! -L /snap ]]; then
        sudo ln -s /var/lib/snapd/snap /snap ||
            fail "creating /snap symlink"
    elif [[ -L /snap ]] && [[ "$(readlink /snap)" != "/var/lib/snapd/snap" ]]; then
        warn "/snap already points elsewhere; leaving it unchanged"
    fi
else
    warn "Snap daemon was not installed with pamac-all; Snap integration may be unavailable"
fi

# Enable AUR support only when the replacement frontend is available.
if $pamac_ready && [[ -f /etc/pamac.conf ]]; then
    sudo sed -i \
        -e 's/^#\?EnableAUR/EnableAUR/' \
        -e 's/^#\?CheckAURUpdates/CheckAURUpdates/' \
        /etc/pamac.conf || fail "configuring /etc/pamac.conf"
fi

# --------------------------- Default apps ------------------------------------
info "Default image viewer -> Xviewer"

xdg-mime default xviewer.desktop \
    image/png image/jpeg image/gif image/webp image/bmp image/tiff \
    2>/dev/null || warn "could not set image defaults"

# --------------------------- Dark mode ---------------------------------------
if $DARK_MODE; then
    info "Configuring system-wide dark mode"

    # Keep these separate: one unavailable package must not block the others.
    pac_try qt5ct
    pac_try qt6ct
    pac_try kvantum
    pac_try dconf
    pac_opt kvantum-qt5

    GTK_THEME=""

    # Install the selected Cinnamon theme system-wide.
    if [[ -n "$SPICES_THEME" ]]; then
        info "Installing Cinnamon Spices theme: $SPICES_THEME"

        tmpz=$(mktemp --suffix=.zip)
        tmpd=$(mktemp -d)

        if curl -fL \
            "https://cinnamon-spices.linuxmint.com/files/themes/${SPICES_THEME}.zip" \
            -o "$tmpz" &&
            unzip -oq "$tmpz" -d "$tmpd" &&
            [[ -f "$tmpd/${SPICES_THEME}/index.theme" ]]; then

            sudo mkdir -p /usr/share/themes
            sudo rm -rf "/usr/share/themes/${SPICES_THEME}"
            sudo cp -a "$tmpd/${SPICES_THEME}" /usr/share/themes/
            sudo chown -R root:root "/usr/share/themes/${SPICES_THEME}"
            sudo chmod -R a+rX "/usr/share/themes/${SPICES_THEME}"

            GTK_THEME="$SPICES_THEME"
        else
            fail "could not download Spices theme '$SPICES_THEME'"
        fi

        rm -rf "$tmpz" "$tmpd"
    fi

    # Ensure system dconf database is active.
    ensure_dconf_profile

    info "Setting dark preference in system dconf database"

    {
        if [[ -n "$GTK_THEME" ]]; then
            echo "[org/cinnamon/desktop/interface]"
            echo "gtk-theme='${GTK_THEME}'"
            echo
            echo "[org/cinnamon/desktop/wm/preferences]"
            echo "theme='${GTK_THEME}'"
            echo
            echo "[org/cinnamon/theme]"
            echo "name='${GTK_THEME}'"
            echo
        fi

        echo "[org/gnome/desktop/interface]"
        [[ -n "$GTK_THEME" ]] &&
            echo "gtk-theme='${GTK_THEME}'"
        echo "color-scheme='prefer-dark'"
        echo

        # Cinnamon/XApp's color-scheme setting is separate from GNOME's
        # setting. Libadwaita apps such as High Tide can otherwise see no
        # system dark preference, especially when running as Flatpaks.
        echo "[org/x/apps/portal]"
        echo "color-scheme='prefer-dark'"
        echo
    } | sudo tee /etc/dconf/db/local.d/00-dark-theme >/dev/null

    # Enforce dark appearance and the selected Cinnamon theme.
    # System dconf locks prevent individual users overriding these keys.
    sudo mkdir -p /etc/dconf/db/local.d/locks

    {
        echo "/org/gnome/desktop/interface/color-scheme"
        echo "/org/x/apps/portal/color-scheme"

        if [[ -n "$GTK_THEME" ]]; then
            echo "/org/gnome/desktop/interface/gtk-theme"
            echo "/org/cinnamon/desktop/interface/gtk-theme"
            echo "/org/cinnamon/desktop/wm/preferences/theme"
            echo "/org/cinnamon/theme/name"
        fi
    } | sudo tee /etc/dconf/db/local.d/locks/00-dark-theme >/dev/null

    sudo dconf update || fail "dconf update"

    # GTK3 system-wide defaults.
    # GTK4/libadwaita applications should use color-scheme instead.
    sudo mkdir -p /etc/gtk-3.0

    {
        echo "[Settings]"
        [[ -n "$GTK_THEME" ]] &&
            echo "gtk-theme-name=${GTK_THEME}"
        echo "gtk-application-prefer-dark-theme=1"
    } | sudo tee /etc/gtk-3.0/settings.ini >/dev/null

    # GTK4 settings.ini does not reliably force libadwaita dark mode.
    # Its appearance preference comes from the GNOME color-scheme setting
    # and the XDG Settings portal.

    # Configure Kvantum for Qt applications.
    sudo mkdir -p /etc/xdg/Kvantum

    printf '[General]\ntheme=KvGnomeDark\n' |
        sudo tee /etc/xdg/Kvantum/kvantum.kvconfig >/dev/null

    # Defaults for accounts created after this script runs.
    sudo mkdir -p /etc/skel/.config/qt5ct /etc/skel/.config/qt6ct

    for qtdir in qt5ct qt6ct; do
        sudo tee "/etc/skel/.config/${qtdir}/${qtdir}.conf" >/dev/null <<'EOF'
[Appearance]
color_scheme_path=
custom_palette=false
icon_theme=
standard_dialogs=default
style=kvantum
EOF
    done

    # Qt configuration for existing and future accounts.
    set_env() {
        if grep -q "^$1=" /etc/environment 2>/dev/null; then
            sudo sed -i "s|^$1=.*|$1=$2|" /etc/environment
        else
            echo "$1=$2" |
                sudo tee -a /etc/environment >/dev/null
        fi
    }

    # ArchWiki documents the combined selector for Qt 5 and Qt 6.
    set_env QT_QPA_PLATFORMTHEME 'qt5ct:qt6ct'
    set_env QT_STYLE_OVERRIDE kvantum

    # Install a GTK3 Adwaita dark theme extension as an available
    # Flatpak theme. GTK3 apps still need a matching active theme.
    sudo flatpak install -y flathub \
        org.gtk.Gtk3theme.Adwaita-dark ||
        warn "Flatpak Adwaita-dark extension unavailable"

    info "Dark mode configured"
fi

# --------------------------- Private home directories ------------------------
info "Private home directories"

set_login_def() {
    local key="$1" value="$2" line found=0 tmp
    tmp=$(mktemp)

    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line =~ ^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+[0-7]+[[:space:]]*(#.*)?$ ]]; then
            if (( found == 0 )); then
                printf '%s\t%s\n' "$key" "$value"
                found=1
            fi
        else
            printf '%s\n' "$line"
        fi
    done < /etc/login.defs > "$tmp"

    if (( found == 0 )); then
        printf '%s\t%s\n' "$key" "$value" >> "$tmp"
    fi

    sudo tee /etc/login.defs < "$tmp" >/dev/null ||
        fail "could not set $key in /etc/login.defs"

    rm -f "$tmp"
}

if [[ -r /etc/login.defs ]]; then
    set_login_def HOME_MODE 0700
    set_login_def UMASK 077
else
    fail "/etc/login.defs not readable"
fi

sudo mkdir -p /etc/profile.d

if ! sudo tee /etc/profile.d/privacy-umask.sh >/dev/null <<'EOF'
# /etc/profile sets umask 022, which overrides login.defs.
umask 077
EOF
then
    fail "could not write privacy-umask.sh"
fi

sudo chmod 644 /etc/profile.d/privacy-umask.sh ||
    fail "chmod privacy-umask.sh"

tighten_existing_homes() {
    local homedir home
    local -a user_homes=()

    while IFS=: read -r _ _ _ _ _ home _; do
        user_homes+=("${home%/}")
    done < <(getent passwd)

    if ((${#user_homes[@]} == 0)); then
        fail "could not read user database"
        return
    fi

    for homedir in /home/*; do
        [[ -d "$homedir" && ! -L "$homedir" ]] || continue
        [[ ${homedir##*/} == lost+found ]] && continue

        for home in "${user_homes[@]}"; do
            if [[ "$home" == "$homedir" ]]; then
                sudo chmod 700 "$homedir" ||
                    fail "chmod 700 $homedir"
                break
            fi
        done
    done
}

tighten_existing_homes

# --------------------------- Privacy: no recent files ------------------------
if $DISABLE_RECENT_FILES; then
    info "Disabling recent files and thumbnail caching"

    pac_try dconf
    ensure_dconf_profile

    sudo tee /etc/dconf/db/local.d/01-no-recent-files >/dev/null <<'EOF'
[org/cinnamon/desktop/privacy]
remember-recent-files=false

[org/gnome/desktop/privacy]
remember-recent-files=false

[org/gnome/desktop/thumbnailers]
disable-all=true
EOF

    sudo dconf update || fail "dconf update"

    rm -f "$HOME/.local/share/recently-used.xbel"
    nemo -q 2>/dev/null || true
fi

# --------------------------- finish ------------------------------------------
if ! systemctl is-enabled --quiet display-manager.service 2>/dev/null; then
    warn "No display manager is enabled."
fi

echo
info "Done."

if ((${#FAILED[@]})); then
    echo "${c_red}These steps failed and may need attention:${c_off}"
    printf '  - %s\n' "${FAILED[@]}"
fi

$DARK_MODE &&
    echo "Dark appearance is locked system-wide. Log out and back in to apply."

read -rp "Reboot now? [y/N] " r
[[ "$r" =~ ^[Yy]$ ]] && sudo reboot
