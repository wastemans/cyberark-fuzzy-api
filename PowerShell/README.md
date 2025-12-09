# CyberArk Fuzzy API - PowerShell Version

Interactive CyberArk account management with fuzzy search selection, written in PowerShell.

## Features

- Fuzzy search for CyberArk accounts
- Interactive account selection using Out-GridView
- SSH/SCP via CyberArk PSM
- MFA caching SSH key management
- Automatic session keepalive via Windows Scheduled Task (handles 20-minute inactivity timeout)
- Windows Credential Manager integration for password storage
- Cross-platform PowerShell Core support (with some Windows-specific features)

## Requirements

- PowerShell 5.1+ (Windows PowerShell) or PowerShell 7+ (PowerShell Core)
- Windows Credential Manager (for password storage) - available on Windows by default
- OpenSSH client (usually pre-installed on Windows 10/11, or available via Git for Windows)
- CyberArk Password Vault API access

## Installation

1. **Clone or copy the PowerShell directory** to your desired location

2. **Configure the application:**
   ```powershell
   # Copy the example config file
   Copy-Item ..\config.ini.example ..\config.ini
   
   # Edit config.ini with your settings
   notepad ..\config.ini
   ```

3. **Set execution policy** (if needed):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## Usage

```powershell
# Interactive mode
.\Main.ps1

# With initial search term
.\Main.ps1 webserver01

# Use alternate endpoint
.\Main.ps1 -Endpoint cyberark-dr

# Save password to credential store
.\Main.ps1 -SavePassword
```

## Project Structure

```
PowerShell/
├── Modules/
│   ├── Config.psm1      # Configuration management
│   ├── Api.psm1         # CyberArk REST API client
│   ├── Auth.psm1        # Authentication, scheduled task keepalive
│   ├── Accounts.psm1    # Account operations
│   ├── SSH.psm1         # SSH/SCP connection handling
│   └── UI.psm1          # Interactive UI (Out-GridView)
├── Main.ps1             # CLI entry point
├── Keepalive.ps1         # Keepalive script (run by scheduled task)
└── README.md             # This file
```

## Session Keepalive

CyberArk REST API tokens expire after 20 minutes of inactivity (configured in
`C:\inetpub\wwwroot\PasswordVault\web.config`, `<sessionState timeout="20" />`).

The keepalive runs as a **Windows Scheduled Task** that:
- **Survives the main application exiting** - keeps your token alive even after you close the script
- Pings the API every 15-19 minutes (randomized intervals)
- Has a hard timeout of 9 hours (configurable) - matches SSH key validity
- Auto-terminates if the token expires or becomes invalid
- Logs to `<project>/keepalive.log`

### Monitoring the Keepalive

```powershell
# Check if scheduled task is running
Get-ScheduledTask -TaskName "CyberArkFuzzy-Keepalive-cyberark"

# View logs
Get-Content ..\keepalive.log -Tail 20

# View task history (PowerShell 5.1+)
Get-WinEvent -LogName Microsoft-Windows-TaskScheduler/Operational | 
    Where-Object {$_.Message -like "*CyberArkFuzzy*"} | 
    Select-Object -First 10
```

### Manually Stopping the Keepalive

```powershell
# Stop the scheduled task
Unregister-ScheduledTask -TaskName "CyberArkFuzzy-Keepalive-cyberark" -Confirm:$false
```

## Configuration

The configuration file (`config.ini`) is shared with the Python version and located in the project root.

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
ssh_key_path = key.openssh
key_max_age_hours = 9

[keepalive]
min_seconds = 901     # 15:01
max_seconds = 1139    # 18:59
timeout_hours = 9     # Hard timeout for scheduled task

[ui]
rich_output = true
default_search = 
```

CLI parameters override config file settings:
```powershell
.\Main.ps1 -Endpoint cyberark-dr -Username MY_ADMIN_USERNAME
```

## Password Storage

The PowerShell version uses **Windows Credential Manager** to store passwords securely:
- Passwords are stored encrypted in the Windows Credential Store
- Accessible via `Get-StoredCredential` / `Set-StoredCredential` (requires `CredentialManager` module)
- If the module is not available, it falls back to prompting for password each time

To install the CredentialManager module (optional but recommended):
```powershell
Install-Module -Name CredentialManager -Scope CurrentUser
```

## Differences from Python Version

1. **UI**: Uses `Out-GridView` instead of `questionary` for account selection
2. **Keepalive**: Uses Windows Scheduled Task instead of detached subprocess
3. **Credentials**: Uses Windows Credential Manager instead of `keyring`
4. **Platform**: Optimized for Windows, but PowerShell Core works on Linux/macOS (with limitations)

## Troubleshooting

### Scheduled Task Creation Fails

If you get an error creating the scheduled task, you may need to run PowerShell as Administrator:
```powershell
# Run as Administrator
Start-Process powershell -Verb RunAs
```

### Out-GridView Not Available

If `Out-GridView` is not available (e.g., on Linux/macOS with PowerShell Core), the script will fall back to a simple numbered list selection.

### SSL Certificate Warnings

If you see SSL certificate warnings, set `verify_ssl = false` in your `config.ini` (not recommended for production).

## License

Internal use only.

