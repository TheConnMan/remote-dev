#!/bin/bash

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Disable AWS CLI pager to prevent interactive editors
export AWS_PAGER=""

# Configuration
HOST_NAME="aws-dev"
INSTANCE_ID_FILE="$SCRIPT_DIR/.instance-id"

# Get IP from argument or auto-discovered running instance
if [ -n "$1" ]; then
  IP="$1"
  echo "Using provided IP: $IP"
else
  echo "Auto-discovering running remote-dev instance via AWS CLI..."

  # Always discover the current running instance instead of trusting .instance-id
  INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=remote-dev" "Name=instance-state-name,Values=running" \
    --query 'sort_by(Reservations[].Instances[], &LaunchTime)[-1].InstanceId' \
    --output text 2>/dev/null)

  if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
    echo "Error: Could not auto-discover a running remote-dev instance."
    echo "Either provide an IP as an argument, or launch a remote-dev instance first."
    exit 1
  fi

  echo "Discovered running instance: $INSTANCE_ID"
  # Persist for other scripts (e.g., stop-spot.sh)
  echo "$INSTANCE_ID" > "$INSTANCE_ID_FILE"

  echo "Getting IP for instance: $INSTANCE_ID"

  # Get public IP from AWS
  IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null)

  if [ -z "$IP" ] || [ "$IP" == "None" ]; then
    echo "Error: Could not get IP for instance $INSTANCE_ID"
    echo "Instance may not be running or may not have a public IP"
    exit 1
  fi

  echo "Found IP: $IP"
fi

# Update SSH config
echo "Updating SSH config for $HOST_NAME..."
python3 << EOF
import re
import os

ip = "$IP"
host_name = "$HOST_NAME"
config_files = [
    "${HOME}/.ssh/config",
    "/mnt/c/Users/bccon/.ssh/config"
]

for config_path in config_files:
    if not os.path.exists(config_path):
        continue

    with open(config_path, "r") as f:
        lines = f.readlines()

    in_host = False
    updated = False

    for i, line in enumerate(lines):
        if line.strip() == f"Host {host_name}":
            in_host = True
        elif line.startswith("Host ") and in_host:
            in_host = False
        elif in_host and re.match(r'^\s+HostName\s+', line):
            # Preserve indentation
            indent = len(line) - len(line.lstrip())
            lines[i] = " " * indent + "HostName " + ip + "\n"
            updated = True

    if updated:
        with open(config_path, "w") as f:
            f.writelines(lines)
        print(f"Updated {config_path}")
    else:
        print(f"No Host {host_name} section found in {config_path}")
EOF

echo "SSH config update complete!"


