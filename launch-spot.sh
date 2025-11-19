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

# Update security group - remove ALL existing SSH rules, then add current IP
echo "Updating security group..."

# Get all existing SSH rules and remove them
EXISTING_RULES=$(aws ec2 describe-security-groups \
  --group-ids $SECURITY_GROUP \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]' \
  --output json 2>/dev/null)

if [ "$EXISTING_RULES" != "[]" ]; then
  echo "Removing existing SSH rules..."
  aws ec2 revoke-security-group-ingress \
    --group-id $SECURITY_GROUP \
    --ip-permissions "$EXISTING_RULES" >/dev/null 2>&1 || true
fi

# Add current IP
echo "Adding SSH access for $MY_IP..."
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP \
  --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges="[{CidrIp=$MY_IP/32,Description='Current IP'}]" >/dev/null 2>&1

echo "Security group updated to allow SSH from $MY_IP only"

# Base64 encode user-data.sh from script directory
USER_DATA_B64=$(base64 -w 0 $SCRIPT_DIR/user-data.sh)

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

# Save instance ID for stop script
echo $INSTANCE_ID > $SCRIPT_DIR/.instance-id

# Wait for SSH to be ready
echo "Waiting for SSH to be ready..."
MAX_SSH_ATTEMPTS=30
SSH_ATTEMPT=0
while [ $SSH_ATTEMPT -lt $MAX_SSH_ATTEMPTS ]; do
  if timeout 3 bash -c "echo > /dev/tcp/$IP/22" 2>/dev/null; then
    echo "SSH is ready"
    break
  fi
  SSH_ATTEMPT=$((SSH_ATTEMPT + 1))
  if [ $SSH_ATTEMPT -ge $MAX_SSH_ATTEMPTS ]; then
    echo "Warning: SSH not ready after $MAX_SSH_ATTEMPTS attempts, attempting connection anyway..."
  else
    sleep 2
  fi
done

echo "Connecting with: ssh -i $KEY_FILE ubuntu@$IP"
ssh -i $KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$IP
