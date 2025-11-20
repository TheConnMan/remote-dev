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

chown -R ubuntu:ubuntu /workspace
echo "Ownership set"

# Run dotfiles setup for ubuntu user
HOME_DIR="/home/ubuntu"
echo "Setting up symlinks for $HOME_DIR..."

# Create symlinks
ln -sf /workspace/git/theconnman/claude-settings "$HOME_DIR/.claude"
ln -sf /workspace/git "$HOME_DIR/git"
rm -rf "$HOME_DIR/.ssh"
ln -sf /workspace/.ssh "$HOME_DIR/.ssh"

echo "=== User-data script completed at $(date) ==="
