#!/bin/bash

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Disable AWS CLI pager to prevent interactive editors
export AWS_PAGER=""

# Parse size flag (default: use launch-spec.json value)
INSTANCE_TYPE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --large)
      INSTANCE_TYPE="t3.large"
      shift
      ;;
    --medium)
      INSTANCE_TYPE="t3.medium"
      shift
      ;;
    --micro)
      INSTANCE_TYPE="t3.micro"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--large|--medium|--micro]"
      exit 1
      ;;
  esac
done

# Configuration
AMI_ID="ami-0d3d27397471af253"
VOLUME_ID="vol-0d49d85263648ccbb"
KEY_NAME="Remote Dev"
KEY_FILE="${HOME}/.aws/pem/remote-dev.pem"
LAUNCH_SPEC="$SCRIPT_DIR/launch-spec.json"

# Update security group with current IP
"$SCRIPT_DIR/update-ip.sh"

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

# Create temporary launch spec with encoded user data (and optional instance type override)
TEMP_LAUNCH_SPEC=$(mktemp)
if [ -n "$INSTANCE_TYPE" ]; then
  echo "Using instance type: $INSTANCE_TYPE"
  jq --arg userdata "$USER_DATA_B64" --arg instancetype "$INSTANCE_TYPE" \
    '.UserData = $userdata | .InstanceType = $instancetype' $LAUNCH_SPEC > $TEMP_LAUNCH_SPEC
else
  jq --arg userdata "$USER_DATA_B64" '.UserData = $userdata' $LAUNCH_SPEC > $TEMP_LAUNCH_SPEC
fi

# Check volume state before launching
echo "Checking volume state..."
VOLUME_STATE=$(aws ec2 describe-volumes \
  --volume-ids $VOLUME_ID \
  --query 'Volumes[0].State' \
  --output text 2>/dev/null)

if [ "$VOLUME_STATE" != "available" ]; then
  echo "ERROR: Volume $VOLUME_ID is not available (current state: $VOLUME_STATE)"
  echo "Please ensure the volume is available before launching an instance"
  rm -f $TEMP_LAUNCH_SPEC
  exit 1
fi
echo "Volume is available"

# Create spot request
echo "Requesting spot instance..."
SPOT_REQUEST=$(aws ec2 request-spot-instances \
  --spot-price "0.10" \
  --instance-count 1 \
  --type "one-time" \
  --tag-specifications 'ResourceType=spot-instances-request,Tags=[{Key=Project,Value=remote-dev}]' \
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

# Tag the instance
echo "Tagging instance..."
aws ec2 create-tags \
  --resources $INSTANCE_ID \
  --tags Key=Project,Value=remote-dev Key=Name,Value="Remote Dev" >/dev/null 2>&1

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
"$SCRIPT_DIR/update-ssh-config.sh" "$IP"

# Save instance ID for stop script
echo $INSTANCE_ID > $SCRIPT_DIR/.instance-id

echo ""
echo "Launch successful!"
echo "You can connect with: ssh aws-dev"
