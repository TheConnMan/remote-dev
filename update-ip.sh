#!/bin/bash

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Disable AWS CLI pager to prevent interactive editors
export AWS_PAGER=""

# Configuration
SECURITY_GROUP="sg-0221ed06c817b633c"

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

