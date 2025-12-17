#!/bin/bash
set -e  # Exit on error
set -x  # Debug mode

# Log everything
exec > >(tee -a /var/log/user-data.log) 2>&1

echo "=== User-data script started at $(date) ==="

# Wait for nvme volume with timeout and better detection
echo "Waiting for /dev/nvme1n1..."
TIMEOUT=300
ELAPSED=0
while [ ! -e /dev/nvme1n1 ] && [ $ELAPSED -lt $TIMEOUT ]; do
  sleep 1
  ELAPSED=$((ELAPSED + 1))
  if [ $((ELAPSED % 10)) -eq 0 ]; then
    echo "Still waiting... ($ELAPSED seconds)"
  fi
done

if [ ! -e /dev/nvme1n1 ]; then
  echo "ERROR: /dev/nvme1n1 not found after $TIMEOUT seconds"
  exit 1
fi

echo "Found /dev/nvme1n1 after $ELAPSED seconds"

# Check if already mounted
if mountpoint -q /workspace 2>/dev/null; then
  echo "Volume already mounted at /workspace"
else
  echo "Mounting volume..."
  mkdir -p /workspace
  mount /dev/nvme1n1 /workspace || {
    echo "ERROR: Failed to mount /dev/nvme1n1"
    exit 1
  }
  echo "Volume mounted successfully"
fi

# chown -R ubuntu:ubuntu /workspace
# echo "Ownership set"

# Run dotfiles setup for ubuntu user
HOME_DIR="/home/ubuntu"
echo "Setting up symlinks for $HOME_DIR..."

# Create symlinks
ln -sf /workspace/git/theconnman/claude-settings "$HOME_DIR/.claude"
ln -sf /workspace/.aws "$HOME_DIR/.aws"
rm -rf "$HOME_DIR/.ssh"
ln -sf /workspace/.ssh "$HOME_DIR/.ssh"
ln -sf /workspace/.bashrc "$HOME_DIR/.bashrc"
mkdir -p "$HOME_DIR/.config"
ln -sf /workspace/.config/gh "$HOME_DIR/.config/gh"
ln -sf /workspace/.cursor "$HOME_DIR/.cursor"
# Ensure .cursor-server directory structure exists on persistent volume
rm -rf "$HOME_DIR/.cursor-server"
ln -sf /workspace/.cursor-server "$HOME_DIR/.cursor-server"

# Setup bash history on /workspace
rm -f "$HOME_DIR/.bash_history"
ln -sf /workspace/.bash_history "$HOME_DIR/.bash_history"

# Add swap
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

# File watcher limit
sysctl fs.inotify.max_user_watches=524288

# Tailscale API key (injected by launch-spot.sh)
TAILSCALE_API_KEY="__TAILSCALE_API_KEY__"

# Install and configure Tailscale
echo "Setting up Tailscale..."
if ! command -v tailscale &> /dev/null; then
  echo "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
fi

# Connect to Tailscale
tailscale up --authkey="$TAILSCALE_API_KEY" --hostname="remote-dev"

echo "Tailscale configured and started"

# Upgrade and install packages
echo "Post-setup installs"
apt-get update
apt-get upgrade -y
apt-get install -y \
  gh \
  git-lfs \
  dos2unix \
  libpq-dev \
  zip \
  docker-compose \
  at

newgrp docker
usermod -aG docker ubuntu

# Install k8 utilities
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
snap install kubectl --classic

# Final upgrade
apt-get update
apt-get upgrade -y
apt-get autoremove -y

# Schedule auto-shutdown after 16 hours (960 minutes) as a safety measure
# This prevents instances from running indefinitely if forgotten
# Using 'at' instead of 'shutdown' to avoid broadcasting messages
echo "Scheduling auto-shutdown in 16 hours..."
systemctl enable atd
systemctl start atd
echo "shutdown -h now" | at now + 960 minutes

echo "=== User-data script completed at $(date) ==="
