#!/bin/bash

# Wait for nvme volume (t3 instances use nvme)
while [ ! -e /dev/nvme1n1 ]; do sleep 1; done

# Mount data volume
mkdir -p /workspace
mount /dev/nvme1n1 /workspace
chown -R ubuntu:ubuntu /workspace

# Run dotfiles setup
su - ubuntu -c "/workspace/dotfiles/setup.sh"
