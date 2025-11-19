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
  --output json)

if [ "$EXISTING_RULES" != "[]" ]; then
  echo "Removing existing SSH rules..."
  aws ec2 revoke-security-group-ingress \
    --group-id $SECURITY_GROUP \
    --ip-permissions "$EXISTING_RULES" 2>/dev/null || true
fi

# Add current IP
echo "Adding SSH access for $MY_IP..."
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP \
  --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges="[{CidrIp=$MY_IP/32,Description='Current IP'}]"

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
  --output text)

# Clean up temp file
rm -f $TEMP_LAUNCH_SPEC

echo "Spot request: $SPOT_REQUEST"
echo "Waiting for fulfillment..."

# Wait for fulfillment
aws ec2 wait spot-instance-request-fulfilled --spot-instance-request-ids $SPOT_REQUEST

# Get instance ID
INSTANCE_ID=$(aws ec2 describe-spot-instance-requests \
  --spot-instance-request-ids $SPOT_REQUEST \
  --query 'SpotInstanceRequests[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE_ID"
echo "Waiting for instance to be running..."

# Wait for running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Attach data volume
echo "Attaching data volume..."
aws ec2 attach-volume \
  --volume-id $VOLUME_ID \
  --instance-id $INSTANCE_ID \
  --device /dev/sdf

# Wait a bit for volume to attach
sleep 10

# Get IP
IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "============================================"
echo "Instance ready at: $IP"
echo "Instance ID: $INSTANCE_ID"
echo "============================================"
echo ""

# Save instance ID for stop script
echo $INSTANCE_ID > $SCRIPT_DIR/.instance-id

echo "Connecting..."
sleep 5

ssh -i $KEY_FILE ubuntu@$IP
