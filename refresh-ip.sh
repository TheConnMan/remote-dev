#!/bin/bash

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Disable AWS CLI pager to prevent interactive editors
export AWS_PAGER=""

echo "============================================"
echo "Refreshing IP in all locations and updating security group"
echo "============================================"
echo ""

# Step 1: Update security group with current IP
echo "Step 1: Updating security group..."
"$SCRIPT_DIR/update-ip.sh"

echo ""

# Step 2: Update SSH config in all locations
echo "Step 2: Updating SSH config in all locations..."
"$SCRIPT_DIR/update-ssh-config.sh"

echo ""
echo "============================================"
echo "All IP updates complete!"
echo "============================================"

