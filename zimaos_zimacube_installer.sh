#!/bin/bash

# Proxmox ZimaOS Installer
# Script now dynamically fetches the latest ZimaOS release version

# Variables for GitHub
GITHUB_RELEASES_URL="https://github.com/IceWhaleTech/ZimaOS/releases"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Functions
validate_number() {
    if ! [[ $1 =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Please enter a valid number${NC}"
        exit 1
    fi
}

check_vmid() {
    if ! qm status "$1" >/dev/null 2>&1; then
        echo -e "${RED}Error: VMID $1 does not exist${NC}"
        exit 1
    fi
}

check_volume() {
    if ! pvesm status | grep -q "^$1"; then
        echo -e "${RED}Error: Storage volume $1 does not exist${NC}"
        exit 1
    fi
}

# 1. Fetch the latest release version from GitHub
echo -e "${YELLOW}Fetching the latest ZimaOS release version...${NC}"
LATEST=$(curl -sSL "$GITHUB_RELEASES_URL" \
           | grep -Eo '## [0-9]+\.[0-9]+\.[0-9]+' \
           | head -n1 \
           | awk '{print $2}')

if [[ -z "$LATEST" ]]; then
    echo -e "${RED}Error: Unable to determine the latest release version.${NC}"
    exit 1
fi

# 2. Ask the user to choose a version (default: latest)
echo -e "${GREEN}Latest available ZimaOS version: $LATEST${NC}"
read -p "Enter ZimaOS version to use [default: $LATEST]: " VERSION
VERSION=${VERSION:-$LATEST}

# Sanity check basic format (very simplistic)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo -e "${RED}Error: Invalid version format.${NC}"
    exit 1
fi

# 3. Construct download URL & other variables
URL="https://github.com/IceWhaleTech/ZimaOS/releases/download/$VERSION/zimaos_zimacube-${VERSION}_installer.img"
IMAGE=$(basename "$URL")
IMAGE_PATH="/var/lib/vz/images/$IMAGE"
DISK_NUMBER="2"
DISK="scsi1"

clear
echo -e "${YELLOW}=== Proxmox ZimaOS Installer ===${NC}"
echo -e "${GREEN}Using version: $VERSION${NC}\n"

# Pre-run warnings
echo -e "!! Before running this script, make sure you have:${NC}\n"
echo -e "Created a new VM with:"
echo -e " - OS -> Do not use any media"
echo -e " - System -> BIOS -> OVMF (UEFI)"
echo -e " - EFI Storage configured (e.g. local-lvm)"
echo -e " - Disks, CPU, Memory, Network configured"
echo -e "!! Do NOT start the VM after creation !!${NC}"

# VMID input
while true; do
    read -p "Enter VM ID (100‑999): " VMID
    validate_number "$VMID"
    if [[ $VMID -ge 100 && $VMID -le 999 ]]; then
        check_vmid "$VMID"
        break
    else
        echo -e "${RED}Error: VMID must be between 100 and 999${NC}"
    fi
done

# Storage volume input
while true; do
    read -p "Enter storage volume [local-lvm]: " VOLUME
    VOLUME=${VOLUME:-local-lvm}
    if check_volume "$VOLUME"; then
        break
    fi
done

mkdir -p /var/lib/vz/images

# Cleanup old images
echo "Cleaning up any existing image files..."
rm -f /var/lib/vz/images/zimaos_zimacube*.img /var/lib/vz/images/zimaos_zimacube*.img.xz

# Download
echo -e "\n${YELLOW}Downloading the image...${NC}"
wget -q --show-progress -O "$IMAGE_PATH" "$URL"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Failed to download the image.${NC}"
    exit 1
fi

# Import the disk
echo -e "\n${YELLOW}Importing the disk...${NC}"
qm importdisk "$VMID" "$IMAGE_PATH" "$VOLUME"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Failed to import the disk.${NC}"
    rm -f "$IMAGE_PATH"
    exit 1
fi

# Attach disk to the VM
echo -e "\n${YELLOW}Attaching the disk...${NC}"
qm set "$VMID" --"$DISK" "$VOLUME:vm-$VMID-disk-$DISK_NUMBER" \
    --boot c --scsihw virtio-scsi-pci --boot order="$DISK"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Failed to set the disk.${NC}"
    exit 1
fi

# Cleanup downloaded image
rm -f "$IMAGE_PATH"

# Success message & instructions
echo -e "\n${GREEN}Success! ZimaOS installer image has been added to VM $VMID${NC}\n"
echo -e "${YELLOW}READ THIS CLOSELY BEFORE STARTING THE VM:${NC}"
echo -e "To ensure successful booting, you have to disable Secure Boot within the VM."
echo -e "1. Go to ${YELLOW}Console${NC} and start the VM."
echo -e "2. Click ${YELLOW}Start Now${NC} and press ${YELLOW}ESC ESC ESC${NC} (multiple times) to load the virtual BIOS."
echo -e "3. Go to ${YELLOW}Secure Boot Configuration${NC} under ${YELLOW}Device Manager${NC} and disable ${YELLOW}Secure Boot${NC}.\n"
echo -e "Quick steps summary:"
echo -e " Device Manager > Secure Boot Configuration > Disable Secure Boot > Save & Exit\n"
