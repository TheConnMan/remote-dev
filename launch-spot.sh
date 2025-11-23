#!/bin/bash

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Disable AWS CLI pager to prevent interactive editors
export AWS_PAGER=""

# Configuration
AMI_ID="ami-0d3d27397471af253"
VOLUME_ID="vol-0d49d85263648ccbb"
KEY_NAME="Remote Dev"
SECURITY_GROUP="sg-0221ed06c817b633c"
KEY_FILE="${HOME}/.aws/pem/remote-dev.pem"
LAUNCH_SPEC="$SCRIPT_DIR/launch-spec.json"

# Get current public IP
echo "Getting your current IP..."
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo "Your IP: $MY_IP"

# Update security group - remove all SSH rules, then add current IP
echo "Updating security group..."

# Get all existing SSH rules and remove them
EXISTING_RULES=$(aws ec2 describe-security-groups \
  --group-ids $SECURITY_GROUP \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]' \
  --output json 2>/dev/null)

if [ "$EXISTING_RULES" != "[]" ]; then
  echo "Removing all existing SSH rules..."
  aws ec2 revoke-security-group-ingress \
    --group-id $SECURITY_GROUP \
    --ip-permissions "$EXISTING_RULES" >/dev/null 2>&1 || true
fi

# Add current IP and 100.93.196.40/32
echo "Adding SSH access for $MY_IP and 100.93.196.40/32..."
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP \
  --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges="[{CidrIp=$MY_IP/32,Description='Current IP'},{CidrIp=100.93.196.40/32,Description='Persistent IP'}]" >/dev/null 2>&1

echo "Security group updated to allow SSH from $MY_IP and 100.93.196.40/32"

# Load Tailscale API key from local .env file
ENV_FILE="$SCRIPT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env file not found at $ENV_FILE"
  echo "Please create it from .env.example and set your TAILSCALE_API_KEY"
  exit 1
fi

# Source .env file to get TAILSCALE_API_KEY
set -a
source "$ENV_FILE"
set +a

if [ -z "$TAILSCALE_API_KEY" ]; then
  echo "ERROR: TAILSCALE_API_KEY not set in .env file"
  exit 1
fi

# Create temporary user-data script with injected API key
TEMP_USER_DATA=$(mktemp)
sed "s|__TAILSCALE_API_KEY__|$TAILSCALE_API_KEY|g" "$SCRIPT_DIR/user-data.sh" > "$TEMP_USER_DATA"

# Base64 encode user-data.sh with injected key
USER_DATA_B64=$(base64 -w 0 "$TEMP_USER_DATA")
rm -f "$TEMP_USER_DATA"

# Create temporary launch spec with encoded user data
TEMP_LAUNCH_SPEC=$(mktemp)
jq --arg userdata "$USER_DATA_B64" '.UserData = $userdata' $LAUNCH_SPEC > $TEMP_LAUNCH_SPEC

# Create spot request
echo "Requesting spot instance..."
SPOT_REQUEST=$(aws ec2 request-spot-instances \
  --spot-price "0.15" \
  --instance-count 1 \
  --type "persistent" \
  --launch-specification file://$TEMP_LAUNCH_SPEC \
  --query 'SpotInstanceRequests[0].SpotInstanceRequestId' \
  --output text 2>/dev/null)

# Clean up temp file
rm -f $TEMP_LAUNCH_SPEC

echo "Spot request: $SPOT_REQUEST"
echo "Waiting for fulfillment..."

# Wait for fulfillment
aws ec2 wait spot-instance-request-fulfilled --spot-instance-request-ids $SPOT_REQUEST >/dev/null 2>&1

# Get instance ID
INSTANCE_ID=$(aws ec2 describe-spot-instance-requests \
  --spot-instance-request-ids $SPOT_REQUEST \
  --query 'SpotInstanceRequests[0].InstanceId' \
  --output text 2>/dev/null)

echo "Instance ID: $INSTANCE_ID"
echo "Waiting for instance to be running..."

# Wait for running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID >/dev/null 2>&1

# Attach data volume (if not already attached)
echo "Checking volume attachment..."
CURRENT_ATTACHMENT=$(aws ec2 describe-volumes \
  --volume-ids $VOLUME_ID \
  --query 'Volumes[0].Attachments[0].InstanceId' \
  --output text 2>/dev/null)

if [ "$CURRENT_ATTACHMENT" != "$INSTANCE_ID" ]; then
  echo "Attaching data volume..."
  aws ec2 attach-volume \
    --volume-id $VOLUME_ID \
    --instance-id $INSTANCE_ID \
    --device /dev/sdf >/dev/null 2>&1 || true

  # Explicitly ensure DeleteOnTermination is false for the data volume
  aws ec2 modify-instance-attribute \
    --instance-id $INSTANCE_ID \
    --block-device-mappings "[{\"DeviceName\":\"/dev/sdf\",\"Ebs\":{\"DeleteOnTermination\":false}}]" >/dev/null 2>&1 || true
else
  echo "Volume already attached to this instance"
fi

# Wait a bit for volume to attach
sleep 10

# Get IP - wait for it to be assigned
echo "Waiting for public IP assignment..."
IP=""
MAX_ATTEMPTS=30
ATTEMPT=0

while [ -z "$IP" ] || [ "$IP" == "None" ]; do
  if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo "Error: Public IP not assigned after $MAX_ATTEMPTS attempts"
    exit 1
  fi
  IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null)
  if [ -z "$IP" ] || [ "$IP" == "None" ]; then
    ATTEMPT=$((ATTEMPT + 1))
    sleep 2
  fi
done

echo "============================================"
echo "Instance ready at: $IP"
echo "Instance ID: $INSTANCE_ID"
echo "============================================"
echo ""

# Update SSH config
echo "Updating SSH config for aws-dev..."
python3 << EOF
import re
import os

ip = "$IP"
config_files = [
    "${HOME}/.ssh/config",
    "/mnt/c/Users/bccon/.ssh/config"
]

for config_path in config_files:
    if not os.path.exists(config_path):
        continue

    with open(config_path, "r") as f:
        lines = f.readlines()

    in_aws_dev = False
    updated = False

    for i, line in enumerate(lines):
        if line.strip() == "Host aws-dev":
            in_aws_dev = True
        elif line.startswith("Host ") and in_aws_dev:
            in_aws_dev = False
        elif in_aws_dev and re.match(r'^\s+HostName\s+', line):
            # Preserve indentation
            indent = len(line) - len(line.lstrip())
            lines[i] = " " * indent + "HostName " + ip + "\n"
            updated = True

    if updated:
        with open(config_path, "w") as f:
            f.writelines(lines)
        print(f"Updated {config_path}")
EOF

# Save instance ID for stop script
echo $INSTANCE_ID > $SCRIPT_DIR/.instance-id

echo ""
echo "Launch successful!"
echo "You can connect with: ssh aws-dev"
