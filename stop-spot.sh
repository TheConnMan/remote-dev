#!/bin/bash

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Configuration
VOLUME_ID="vol-0d49d85263648ccbb"

# Read instance ID from saved file
if [ -f "$SCRIPT_DIR/.instance-id" ]; then
  INSTANCE_ID=$(cat $SCRIPT_DIR/.instance-id)
else
  echo "Error: No instance ID found. Either run launch-spot.sh first or manually specify instance ID."
  exit 1
fi

echo "Stopping spot instance $INSTANCE_ID..."

# Cancel spot request first (so it doesn't relaunch)
SPOT_REQUEST=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].SpotInstanceRequestId' \
  --output text)

if [ "$SPOT_REQUEST" != "None" ]; then
  aws ec2 cancel-spot-instance-requests --spot-instance-request-ids $SPOT_REQUEST
fi

# Detach volume (so it persists)
aws ec2 detach-volume --volume-id $VOLUME_ID

# Terminate instance
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

# Clean up saved instance ID
rm -f $SCRIPT_DIR/.instance-id

echo "Instance terminated. Volume preserved."
