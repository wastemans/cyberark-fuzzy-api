# CyberArk Fuzzy API

Interactive CyberArk account management with fuzzy search selection.

Python port of the bash `cys` function, designed to be cross-platform (Linux, Windows, macOS).

## Features

- Fuzzy search for CyberArk accounts
- Interactive account selection
- SSH/SCP via CyberArk PSM
- MFA caching SSH key management
- Automatic session keepalive (handles 20-minute inactivity timeout)
- Cross-platform credential storage

## Installation

```bash
# Clone/copy to your projects directory
cd ~/projects/cyberark-fuzzy-api

# Create virtual environment (optional but recommended)
python -m venv venv
source venv/bin/activate  # Linux/macOS
# or: venv\Scripts\activate  # Windows

# Install dependencies
pip install -r requirements.txt
```

## Usage

```bash
# Interactive mode
python main.py

# With initial search term
python main.py webserver01

# Use alternate endpoint
python main.py --endpoint cyberark-dr

# Save password to credential store
python main.py --save-password
```

## Project Structure

```
cyberark-fuzzy-api/
├── cyberark_fuzzy/
│   ├── __init__.py     # Package init
│   ├── config.py       # Configuration management
│   ├── api.py          # CyberArk REST API client
│   ├── auth.py         # Authentication, session keepalive
│   ├── accounts.py     # Account operations
│   ├── ssh.py          # SSH/SCP connection handling
│   ├── ui.py           # Interactive UI (questionary)
│   └── keepalive.py    # Detached keepalive subprocess
├── main.py             # CLI entry point
├── requirements.txt    # Dependencies
└── README.md           # This file
```

## Session Keepalive

CyberArk REST API tokens expire after 20 minutes of inactivity (configured in
`C:\inetpub\wwwroot\PasswordVault\web.config`, `<sessionState timeout="20" />`).

The keepalive runs as a **detached subprocess** that:
- **Survives the main application exiting** - keeps your token alive even after you close `cys`
- Pings the API every 15-19 minutes (randomized intervals)
- Has a hard timeout of 9 hours (configurable) - matches SSH key validity
- Auto-terminates if the token expires or becomes invalid
- Works on both **Linux/macOS** (via `start_new_session`) and **Windows** (via `DETACHED_PROCESS`)

### Monitoring the Keepalive

```bash
# Check if running
cat keepalive.pid

# View logs
tail -f keepalive.log

# Example log output:
# [2024-01-15 10:30:00] Keepalive started for endpoint: cyberark
# [2024-01-15 10:30:00] Hard timeout: 32400s (9.0 hours)
# [2024-01-15 10:30:00] PID: 12345
# [2024-01-15 10:45:32] Keepalive ping successful (elapsed: 0.3h)
```

### Manually Stopping the Keepalive

```bash
# Linux/macOS
kill $(cat keepalive.pid)

# Windows (PowerShell)
Stop-Process -Id (Get-Content keepalive.pid)
```

## Configuration

Copy `config.ini.example` to `config.ini` and edit as needed:

```bash
cp config.ini.example config.ini
```

Config file locations (checked in order):
1. `./config.ini` (current directory)
2. `<project>/config.ini`
3. `<project>/config.ini.example` (fallback)

```ini
[cyberark]
endpoint = cyberark
username = MY_ADMIN_USERNAME
verify_ssl = false

[ssh]
ssh_key_path = 
key_max_age_hours = 9

[keepalive]
# Randomized interval to avoid 20-minute timeout
min_seconds = 901     # 15:01
max_seconds = 1139    # 18:59
timeout_hours = 9     # Hard timeout for detached keepalive process

[ui]
rich_output = true
default_search = 
```

CLI flags override config file settings:
```bash
python main.py --endpoint cyberark-dr --username MY_ADMIN_USERNAME
```

## Dependencies

- `requests` - HTTP client
- `questionary` - Interactive prompts and fuzzy selection
- `rich` - Terminal formatting
- `keyring` - Cross-platform credential storage (optional)

## License

Internal use only.

