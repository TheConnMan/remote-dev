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

**Stop all instances (with Project=remote-dev tag):**
```bash
./stop-spot.sh --all
```

Cancels all open spot requests and terminates all instances tagged with `Project=remote-dev`.

**Cleanup orphaned spot requests:**
```bash
./cleanup-spot-requests.sh
```

Lists and cancels all orphaned spot requests and instances tagged with `Project=remote-dev`. Useful for cleaning up multiple spot requests that may have accumulated.

## Requirements

- AWS CLI configured with appropriate credentials
- SSH key at `~/.aws/pem/remote-dev.pem`
- `jq` installed

## Features

- **Ephemeral Spot Instances**: Spot requests are created as "one-time" instead of "persistent", preventing AWS from automatically relaunching terminated instances
- **Resource Tagging**: All spot requests and instances are tagged with `Project=remote-dev` for easy identification and cleanup
- **Automatic Cleanup**: Scripts filter by tags to avoid accidentally affecting other AWS resources

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

