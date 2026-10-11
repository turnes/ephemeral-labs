#!/usr/bin/env bash
# Install KVM/QEMU + libvirt on Ubuntu and grant the invoking user access.
# Usage: sudo ./install-kvm-ubuntu.sh [--with-gui] [--check-only]
#   --check-only  Run the hardware preflight and exit without installing (no root needed).
# Hardware thresholds (warnings only) can be overridden via env:
#   MIN_CPUS (default 2), MIN_RAM_GB (default 4), MIN_DISK_GB (default 20)
set -euo pipefail

WITH_GUI=false
CHECK_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --with-gui) WITH_GUI=true ;;
        --check-only) CHECK_ONLY=true ;;
        -h|--help) echo "Usage: sudo $0 [--with-gui] [--check-only]"; exit 0 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

log()  { echo -e "\e[1;32m==>\e[0m $*"; }
warn() { echo -e "\e[1;33m!!\e[0m $*" >&2; }
die()  { echo -e "\e[1;31mxx\e[0m $*" >&2; exit 1; }

MIN_CPUS="${MIN_CPUS:-2}"
MIN_RAM_GB="${MIN_RAM_GB:-4}"
MIN_DISK_GB="${MIN_DISK_GB:-20}"

ok() { echo -e "   \e[32mok\e[0m   $*"; }

# Hardware preflight. Missing CPU virtualization is fatal; everything else warns.
check_hardware() {
    log "Checking hardware"
    local failed=false

    local arch; arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        ok "Architecture: $arch"
    else
        warn "Architecture $arch is untested; this script targets x86_64."
    fi

    if grep -Eq '(vmx|svm)' /proc/cpuinfo; then
        ok "CPU virtualization: $(grep -Eo -m1 '(vmx|svm)' /proc/cpuinfo | sed 's/vmx/Intel VT-x/;s/svm/AMD-V/')"
    else
        warn "CPU does not expose VT-x/AMD-V. Enable virtualization in BIOS/UEFI (or nested virt on the host)."
        failed=true
    fi

    if [[ -e /dev/kvm ]]; then
        ok "/dev/kvm present"
    else
        warn "/dev/kvm missing; KVM may be disabled in BIOS/UEFI or the kvm module is not loaded."
    fi

    local virt; virt=$(systemd-detect-virt 2>/dev/null || true)
    if [[ -n "$virt" && "$virt" != "none" ]]; then
        warn "Running inside a VM ($virt); KVM requires nested virtualization on the host."
    fi

    local cpus; cpus=$(nproc)
    if (( cpus >= MIN_CPUS )); then ok "CPUs: $cpus"
    else warn "CPUs: $cpus (recommended >= $MIN_CPUS)"; fi

    local ram_gb; ram_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
    if (( ram_gb >= MIN_RAM_GB )); then ok "RAM: ${ram_gb}G"
    else warn "RAM: ${ram_gb}G (recommended >= ${MIN_RAM_GB}G)"; fi

    # VM images live under /var/lib/libvirt; check the nearest existing parent
    local dir=/var/lib/libvirt
    while [[ ! -d "$dir" ]]; do dir=$(dirname "$dir"); done
    local disk_gb; disk_gb=$(df -Pk "$dir" | awk 'NR==2 {printf "%d", $4/1024/1024}')
    if (( disk_gb >= MIN_DISK_GB )); then ok "Free disk at $dir: ${disk_gb}G"
    else warn "Free disk at $dir: ${disk_gb}G (recommended >= ${MIN_DISK_GB}G)"; fi

    if [[ -n "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]]; then
        ok "IOMMU enabled (PCI passthrough possible)"
    else
        echo "   --   IOMMU not enabled (only needed for PCI passthrough)"
    fi

    $failed && return 1
    return 0
}

if $CHECK_ONLY; then
    check_hardware || die "Hardware check failed."
    log "Hardware check passed."
    exit 0
fi

[[ $EUID -eq 0 ]] || die "Run as root (sudo $0)."
grep -qi ubuntu /etc/os-release || warn "This script targets Ubuntu; continuing anyway."

# The user who invoked sudo, to be added to the kvm/libvirt groups
TARGET_USER="${SUDO_USER:-}"

check_hardware || die "Hardware check failed."

log "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
PACKAGES=(
    qemu-system-x86
    qemu-utils
    libvirt-daemon-system
    libvirt-clients
    bridge-utils
    virtinst
    cpu-checker
    ovmf
    dnsmasq-base
)
$WITH_GUI && PACKAGES+=(virt-manager)
apt-get install -y --no-install-recommends "${PACKAGES[@]}"

log "Verifying KVM acceleration"
kvm-ok || die "KVM acceleration is not available."

log "Enabling libvirtd"
systemctl enable --now libvirtd

log "Ensuring the default NAT network is active"
if virsh net-info default &>/dev/null; then
    virsh net-autostart default >/dev/null
    virsh net-list --name | grep -qx default || virsh net-start default
else
    warn "libvirt 'default' network not found; skipping."
fi

if [[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]]; then
    log "Adding $TARGET_USER to kvm and libvirt groups"
    usermod -aG kvm,libvirt "$TARGET_USER"
fi

log "Done."
virsh version || true
if [[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]]; then
    echo "Log out and back in (or run 'newgrp libvirt') for group changes to take effect for $TARGET_USER."
fi
