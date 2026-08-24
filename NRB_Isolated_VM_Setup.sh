#!/bin/bash
set -e

# NRB Isolated VM - Debian 11 host
# Creates a separate QEMU VM:
#   30 vCPUs (virtual CPUs)
#   31 GB RAM
#   57 GB virtual disk
# It does NOT use or modify the host filesystem as the guest disk.
#
# IMPORTANT:
# - 30 vCPUs are virtual/oversubscribed if the host has only 3 physical cores.
# - 31 GB RAM can only be allocated if the host has at least that much available RAM.
# - The 57 GB disk is a virtual disk file and needs up to 57 GB of host storage.
# - The first run installs the guest OS from the Debian netinst ISO.

VM_DIR="$HOME/NRB-Isolated-VM"
DISK="$VM_DIR/nrb-vm.qcow2"
ISO="$VM_DIR/debian-11.11.0-amd64-netinst.iso"
START="$VM_DIR/START-NRB.desktop"
RUN="$VM_DIR/start-nrb-vm.sh"

mkdir -p "$VM_DIR"

echo "=== NRB Isolated VM Setup ==="
echo "VM directory: $VM_DIR"

if ! command -v qemu-system-x86_64 >/dev/null 2>&1 || ! command -v qemu-img >/dev/null 2>&1; then
    echo "[+] Installing QEMU..."
    sudo apt update
    sudo apt install -y qemu-system-x86 qemu-utils qemu-system-gui wget
fi

# Show host resources before allocating the requested VM resources.
HOST_CPU=$(nproc)
HOST_RAM_MB=$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)
HOST_DISK_KB=$(df -Pk "$VM_DIR" | awk 'NR==2 {print $4}')
HOST_DISK_GB=$((HOST_DISK_KB / 1024 / 1024))

echo
echo "Host CPU cores : $HOST_CPU"
echo "Host RAM        : ${HOST_RAM_MB} MB"
echo "Free disk       : ${HOST_DISK_GB} GB"
echo
echo "Requested VM    : 30 vCPU / 31 GB RAM / 57 GB disk"
echo

if [ "$HOST_RAM_MB" -lt 32768 ]; then
    echo "WARNING: The host has less than 32 GB RAM available."
    echo "The VM is configured for 31 GB, but it may fail to start or heavily swap."
fi

if [ "$HOST_DISK_GB" -lt 60 ]; then
    echo "WARNING: Less than 60 GB is free where the VM is stored."
    echo "A 57 GB virtual disk needs sufficient host storage."
fi

if [ ! -f "$ISO" ]; then
    echo "[+] Downloading Debian 11 installer..."
    wget -O "$ISO" \
      "https://cdimage.debian.org/cdimage/archive/11.11.0/amd64/iso-cd/debian-11.11.0-amd64-netinst.iso"
fi

if [ ! -f "$DISK" ]; then
    echo "[+] Creating isolated 57 GB virtual disk..."
    qemu-img create -f qcow2 "$DISK" 57G
fi

cat > "$RUN" <<'EOF'
#!/bin/bash
set -e
VM_DIR="$HOME/NRB-Isolated-VM"
DISK="$VM_DIR/nrb-vm.qcow2"
ISO="$VM_DIR/debian-11.11.0-amd64-netinst.iso"

cd "$VM_DIR"

# First boot: attach the installer ISO.
if [ ! -f "$VM_DIR/.installed" ]; then
    echo "Starting Debian installer..."
    echo "Install Debian inside the VM. The guest disk is: $DISK"
    qemu-system-x86_64 \
        -machine accel=kvm:tcg \
        -cpu max \
        -smp 30 \
        -m 31G \
        -drive file="$DISK",if=virtio,format=qcow2 \
        -cdrom "$ISO" \
        -boot order=d \
        -nic user,model=virtio-net-pci \
        -display gtk
    echo
    read -r -p "After completing Debian installation, press Enter to mark the VM installed..."
    touch "$VM_DIR/.installed"
else
    echo "Starting installed NRB VM..."
    qemu-system-x86_64 \
        -machine accel=kvm:tcg \
        -cpu max \
        -smp 30 \
        -m 31G \
        -drive file="$DISK",if=virtio,format=qcow2 \
        -nic user,model=virtio-net-pci \
        -display gtk
fi
EOF

chmod +x "$RUN"

cat > "$START" <<EOF
[Desktop Entry]
Type=Application
Name=START NRB Isolated VM
Comment=Start the separate NRB QEMU VM (30 vCPU, 31 GB RAM, 57 GB disk)
Exec=$RUN
Terminal=true
Icon=utilities-terminal
Categories=System;Utility;
EOF

chmod +x "$START"

echo
echo "DONE."
echo "VM files are in: $VM_DIR"
echo "Launcher created: $START"
echo
echo "To make the launcher double-clickable in many Debian file managers:"
echo "  Right-click START-NRB.desktop -> Properties -> Permissions -> Allow executing as program"
echo "Then double-click it and choose 'Trust and Launch' if Debian asks."
echo
echo "The VM is separate from the host's normal filesystem."
echo "Do not delete $DISK unless you want to delete the VM."
