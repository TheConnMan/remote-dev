#!/bin/bash

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Disable AWS CLI pager to prevent interactive editors
export AWS_PAGER=""

# Configuration
VOLUME_ID="vol-0d49d85263648ccbb"

# Parse command line arguments
CANCEL_ALL=false
if [ "$1" == "--all" ]; then
  CANCEL_ALL=true
fi

if [ "$CANCEL_ALL" == true ]; then
  echo "Stopping all remote-dev spot instances..."

  # Cancel all spot requests tagged with Project=remote-dev
  echo "Cancelling all remote-dev spot requests..."
  SPOT_REQUESTS=$(aws ec2 describe-spot-instance-requests \
    --filters "Name=tag:Project,Values=remote-dev" "Name=state,Values=open,active" \
    --query 'SpotInstanceRequests[*].SpotInstanceRequestId' \
    --output text 2>/dev/null)

  if [ -n "$SPOT_REQUESTS" ] && [ "$SPOT_REQUESTS" != "None" ]; then
    aws ec2 cancel-spot-instance-requests --spot-instance-request-ids $SPOT_REQUESTS >/dev/null 2>&1
    echo "Cancelled spot requests: $SPOT_REQUESTS"
  else
    echo "No open spot requests found"
  fi

  # Terminate all instances tagged with Project=remote-dev
  echo "Terminating all remote-dev instances..."
  INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=remote-dev" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text 2>/dev/null)

  if [ -n "$INSTANCES" ] && [ "$INSTANCES" != "None" ]; then
    aws ec2 terminate-instances --instance-ids $INSTANCES >/dev/null 2>&1
    echo "Terminated instances: $INSTANCES"
  else
    echo "No running instances found"
  fi

  # Clean up saved instance ID
  rm -f $SCRIPT_DIR/.instance-id

  echo "All remote-dev resources stopped. Volume preserved."
else
  # Read instance ID from saved file
  if [ -f "$SCRIPT_DIR/.instance-id" ]; then
    INSTANCE_ID=$(cat $SCRIPT_DIR/.instance-id)
  else
    echo "Error: No instance ID found. Either run launch-spot.sh first or use --all to stop all remote-dev instances."
    exit 1
  fi

  echo "Stopping spot instance $INSTANCE_ID..."

  # Verify instance has Project=remote-dev tag
  TAG_VALUE=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].Tags[?Key==`Project`].Value' \
    --output text 2>/dev/null)

  if [ "$TAG_VALUE" != "remote-dev" ]; then
    echo "Warning: Instance $INSTANCE_ID is not tagged with Project=remote-dev"
    echo "Proceeding anyway since it was found in .instance-id file..."
  fi

  # Cancel spot request first (so it doesn't relaunch)
  SPOT_REQUEST=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].SpotInstanceRequestId' \
    --output text 2>/dev/null)

  if [ "$SPOT_REQUEST" != "None" ] && [ -n "$SPOT_REQUEST" ]; then
    aws ec2 cancel-spot-instance-requests --spot-instance-request-ids $SPOT_REQUEST >/dev/null 2>&1
    echo "Cancelled spot request: $SPOT_REQUEST"
  fi

  # Terminate instance (volume will be automatically detached)
  aws ec2 terminate-instances --instance-ids $INSTANCE_ID >/dev/null 2>&1

  # Clean up saved instance ID
  rm -f $SCRIPT_DIR/.instance-id

  echo "Instance terminated. Volume preserved."
fi
