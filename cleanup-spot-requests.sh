#!/bin/bash

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Disable AWS CLI pager to prevent interactive editors
export AWS_PAGER=""

echo "=== Remote-Dev Spot Instance Cleanup ==="
echo ""

# Find all spot requests tagged with Project=remote-dev
echo "Looking for spot requests tagged with Project=remote-dev..."
SPOT_REQUESTS=$(aws ec2 describe-spot-instance-requests \
  --filters "Name=tag:Project,Values=remote-dev" "Name=state,Values=open,active" \
  --query 'SpotInstanceRequests[*].SpotInstanceRequestId' \
  --output text 2>/dev/null)

if [ -z "$SPOT_REQUESTS" ] || [ "$SPOT_REQUESTS" == "None" ]; then
  echo "No open spot requests found with Project=remote-dev tag"
else
  echo "Found spot requests: $SPOT_REQUESTS"
  echo "Cancelling spot requests..."
  aws ec2 cancel-spot-instance-requests --spot-instance-request-ids $SPOT_REQUESTS >/dev/null 2>&1
  echo "Spot requests cancelled"
fi

echo ""

# Find all running instances tagged with Project=remote-dev
echo "Looking for running instances tagged with Project=remote-dev..."
INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=remote-dev" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text 2>/dev/null)

if [ -z "$INSTANCES" ] || [ "$INSTANCES" == "None" ]; then
  echo "No running instances found with Project=remote-dev tag"
else
  echo "Found instances: $INSTANCES"
  echo "Terminating instances..."
  aws ec2 terminate-instances --instance-ids $INSTANCES >/dev/null 2>&1
  echo "Instances terminated"
fi

echo ""
echo "Cleanup complete!"
echo ""
echo "Summary:"
echo "  - Cancelled spot requests: $([ -z "$SPOT_REQUESTS" ] || [ "$SPOT_REQUESTS" == "None" ] && echo "0" || echo "$SPOT_REQUESTS" | wc -w)"
echo "  - Terminated instances: $([ -z "$INSTANCES" ] || [ "$INSTANCES" == "None" ] && echo "0" || echo "$INSTANCES" | wc -w)"

