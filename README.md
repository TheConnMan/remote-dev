# Remote Dev

Scripts to launch and manage AWS EC2 spot instances for remote development.

## Usage

**Launch instance:**
```bash
./launch-spot.sh
```

Launches a spot instance, updates security group to allow SSH from your current IP, attaches a persistent data volume, and connects via SSH.

**Stop instance:**
```bash
./stop-spot.sh
```

Terminates the running instance and cancels the spot request. The data volume is preserved.

## Requirements

- AWS CLI configured with appropriate credentials
- SSH key at `~/.aws/pem/remote-dev.pem`
- `jq` installed

## Configuration

Edit `launch-spot.sh` to customize:
- AMI ID
- Instance type (in `launch-spec.json`)
- Security group
- Volume ID
- Key name

