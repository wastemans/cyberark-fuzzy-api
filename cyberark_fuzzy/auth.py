"""Authentication and session management."""

import os
import sys
import time
import signal
import subprocess
from pathlib import Path
from typing import Optional
from getpass import getpass

from rich.console import Console

from .config import Config
from .api import CyberArkAPI, APIError

console = Console()


class AuthManager:
    """Manages CyberArk authentication and session keepalive."""
    
    def __init__(self, config: Config, api: CyberArkAPI):
        self.config = config
        self.api = api
    
    def get_password(self) -> str:
        """Get password from user or credential store."""
        # Try keyring first (cross-platform credential storage)
        try:
            import keyring
            password = keyring.get_password("cyberark-fuzzy", self.config.username)
            if password:
                return password
        except:
            pass
        
        # Fall back to prompt
        return getpass(f"Password for {self.config.username}: ")
    
    def save_password(self, password: str) -> None:
        """Save password to credential store."""
        try:
            import keyring
            keyring.set_password("cyberark-fuzzy", self.config.username, password)
            console.print("[green]Password saved to credential store[/green]")
        except Exception as e:
            console.print(f"[yellow]Could not save password: {e}[/yellow]")
    
    def authenticate(self, save_password: bool = False) -> bool:
        """
        Authenticate to CyberArk.
        
        Returns True if authentication succeeded.
        """
        password = self.get_password()
        
        try:
            console.print(f"[cyan]Authenticating as {self.config.username}...[/cyan]")
            self.api.logon_radius(self.config.username, password)
            console.print("[green]Authentication successful[/green]")
            
            if save_password:
                self.save_password(password)
            
            return True
        except APIError as e:
            console.print(f"[red]Authentication failed: {e.message}[/red]")
            return False
    
    def check_and_refresh(self) -> bool:
        """
        Check if session is valid, re-authenticate if needed.
        
        Returns True if we have a valid session.
        """
        if self.api.verify_session():
            return True
        
        console.print("[yellow]Session expired, re-authenticating...[/yellow]")
        return self.authenticate()
    
    # -------------------------------------------------------------------------
    # Token keepalive (detached subprocess)
    # -------------------------------------------------------------------------
    # Purpose: CyberArk REST API tokens expire after 20 minutes of inactivity
    # Configured in: C:\inetpub\wwwroot\PasswordVault\web.config
    # Parameter: <sessionState timeout="20" /> (value in minutes)
    # Solution: Detached subprocess that pings API every 15-19 minutes
    #
    # Usage:
    #   auth_manager.start_keepalive()  - starts keepalive (survives app exit)
    #   auth_manager.stop_keepalive()   - stops keepalive manually
    #
    # Notes:
    #   - Runs as a detached subprocess (survives main process exit)
    #   - Hard timeout of ~9 hours (configurable)
    #   - Randomized intervals (15:01-18:59 mins) to avoid patterns
    #   - Auto-exits if token dies
    #   - Logs to <project>/keepalive.log
    #   - PID stored in <project>/keepalive.pid
    # -------------------------------------------------------------------------
    
    def _is_keepalive_running(self) -> bool:
        """Check if a keepalive process is already running."""
        pid_path = self.config.keepalive_pid_path
        if not pid_path.exists():
            return False
        
        try:
            pid = int(pid_path.read_text().strip())
            # Check if process exists
            if os.name == "nt":
                # Windows
                import ctypes
                kernel32 = ctypes.windll.kernel32
                handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
                if handle:
                    kernel32.CloseHandle(handle)
                    return True
                return False
            else:
                # Unix: send signal 0 to check if process exists
                os.kill(pid, 0)
                return True
        except (ValueError, OSError, ProcessLookupError):
            # PID file is stale
            pid_path.unlink(missing_ok=True)
            return False
    
    def start_keepalive(self, timeout_hours: Optional[float] = None) -> None:
        """
        Start the keepalive as a detached subprocess.
        
        The subprocess will survive the main process exiting and will
        auto-terminate after the specified timeout.
        
        Args:
            timeout_hours: Hard timeout in hours (default: from config, typically 9)
        """
        if self._is_keepalive_running():
            console.print("[cyan]Keepalive already running[/cyan]")
            return
        
        # Use config value if not specified
        if timeout_hours is None:
            timeout_hours = self.config.keepalive_timeout_hours
        
        # Calculate timeout in seconds
        timeout_seconds = int(timeout_hours * 3600)
        
        # Build command to run the keepalive module
        cmd = [
            sys.executable,
            "-m", "cyberark_fuzzy.keepalive",
            "--endpoint", self.config.endpoint,
            "--timeout", str(timeout_seconds),
            "--min-interval", str(self.config.keepalive_min_seconds),
            "--max-interval", str(self.config.keepalive_max_seconds),
        ]
        
        # Spawn detached subprocess
        if os.name == "nt":
            # Windows: use CREATE_NEW_PROCESS_GROUP and DETACHED_PROCESS
            DETACHED_PROCESS = 0x00000008
            CREATE_NEW_PROCESS_GROUP = 0x00000200
            CREATE_NO_WINDOW = 0x08000000
            creationflags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW
            
            subprocess.Popen(
                cmd,
                cwd=str(self.config.config_dir),
                creationflags=creationflags,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
            )
        else:
            # Unix: use double-fork pattern via start_new_session
            subprocess.Popen(
                cmd,
                cwd=str(self.config.config_dir),
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
            )
        
        # Give it a moment to write its PID
        time.sleep(0.5)
        
        if self._is_keepalive_running():
            pid = self.config.keepalive_pid_path.read_text().strip()
            console.print(f"[green]Token keepalive started (PID: {pid}, timeout: {timeout_hours}h)[/green]")
        else:
            console.print("[yellow]Keepalive may have failed to start - check keepalive.log[/yellow]")
    
    def stop_keepalive(self) -> None:
        """Stop the keepalive subprocess."""
        pid_path = self.config.keepalive_pid_path
        
        if not pid_path.exists():
            console.print("[yellow]No keepalive process running[/yellow]")
            return
        
        try:
            pid = int(pid_path.read_text().strip())
            
            if os.name == "nt":
                # Windows
                subprocess.run(["taskkill", "/F", "/PID", str(pid)], 
                             capture_output=True, check=False)
            else:
                # Unix
                os.kill(pid, signal.SIGTERM)
            
            console.print(f"[yellow]Keepalive stopped (PID: {pid})[/yellow]")
        except (ValueError, OSError, ProcessLookupError) as e:
            console.print(f"[yellow]Could not stop keepalive: {e}[/yellow]")
        finally:
            pid_path.unlink(missing_ok=True)
    
    # -------------------------------------------------------------------------
    # SSH Key Management
    # -------------------------------------------------------------------------
    
    def download_ssh_key(self) -> bool:
        """
        Download MFA caching SSH key if needed.
        
        Returns True if key is available (new or existing).
        """
        key_path = Path(self.config.ssh_key_path)
        
        # Check if existing key is still valid (less than 9 hours old)
        if key_path.exists():
            key_age_hours = (time.time() - key_path.stat().st_mtime) / 3600
            if key_age_hours < self.config.key_max_age_hours:
                console.print(f"[cyan]SSH key is {key_age_hours:.1f} hours old, still valid[/cyan]")
                return True
            console.print(f"[yellow]SSH key is {key_age_hours:.1f} hours old, refreshing...[/yellow]")
        else:
            console.print("[cyan]No SSH key found, downloading...[/cyan]")
        
        try:
            private_key = self.api.get_ssh_key()
            if not private_key:
                console.print("[red]Failed to retrieve SSH key[/red]")
                return False
            
            # Ensure .ssh directory exists
            ssh_dir = key_path.parent
            ssh_dir.mkdir(parents=True, exist_ok=True)
            if os.name != "nt":
                os.chmod(ssh_dir, 0o700)
            
            # Save key with restrictive permissions
            key_path.write_text(private_key)
            if os.name != "nt":
                os.chmod(key_path, 0o600)
            
            console.print(f"[green]SSH key saved to {key_path}[/green]")
            return True
            
        except APIError as e:
            console.print(f"[red]Failed to download SSH key: {e.message}[/red]")
            return False

