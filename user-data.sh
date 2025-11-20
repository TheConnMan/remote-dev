#!/bin/bash

# Wait for nvme volume (t3 instances use nvme)
while [ ! -e /dev/nvme1n1 ]; do sleep 1; done

# Mount data volume
mkdir -p /workspace
mount /dev/nvme1n1 /workspace
chown -R ubuntu:ubuntu /workspace

# Preserve AWS-injected SSH key before dotfiles setup
# (dotfiles setup might overwrite authorized_keys)
if [ -f /home/ubuntu/.ssh/authorized_keys ]; then
  AWS_KEY=$(cat /home/ubuntu/.ssh/authorized_keys)
  mkdir -p /home/ubuntu/.ssh
  chown ubuntu:ubuntu /home/ubuntu/.ssh
fi

# Run dotfiles setup
su - ubuntu -c "/workspace/dotfiles/setup.sh"

# Restore AWS key if it was preserved and dotfiles setup removed it
if [ ! -z "$AWS_KEY" ] && [ -f /home/ubuntu/.ssh/authorized_keys ]; then
  if ! grep -q "$AWS_KEY" /home/ubuntu/.ssh/authorized_keys 2>/dev/null; then
    echo "$AWS_KEY" >> /home/ubuntu/.ssh/authorized_keys
    chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
    chmod 600 /home/ubuntu/.ssh/authorized_keys
  fi
fi
