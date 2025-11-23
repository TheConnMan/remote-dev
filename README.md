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

### Environment Variables

Create a `.env` file locally from the example template:

```bash
cp .env.example .env
```

Edit `.env` and set your Tailscale API key:
- Get your API key from: https://login.tailscale.com/admin/settings/keys

The `launch-spot.sh` script reads the local `.env` file and injects the `TAILSCALE_API_KEY` into the user-data script before launching the instance. The key is embedded in the user-data script that runs on the instance during boot.

**Note:** The `.env` file is gitignored and will not be committed to the repository.

### Launch Script Settings

Edit `launch-spot.sh` to customize:
- AMI ID
- Instance type (in `launch-spec.json`)
- Security group
- Volume ID
- Key name

