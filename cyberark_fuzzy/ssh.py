"""SSH and SCP connection handling."""

import os
import subprocess
import shutil
from typing import Optional
from pathlib import Path

from rich.console import Console

from .config import Config
from .accounts import Account

console = Console()


class SSHManager:
    """Manages SSH and SCP connections through CyberArk PSM."""
    
    def __init__(self, config: Config):
        self.config = config
        self._ssh_path: Optional[str] = None
        self._scp_path: Optional[str] = None
    
    @property
    def ssh_path(self) -> str:
        """Get path to SSH executable."""
        if self._ssh_path:
            return self._ssh_path
        
        # Try to find ssh
        if os.name == "nt":
            # Windows - check common locations
            candidates = [
                shutil.which("ssh"),
                r"C:\Windows\System32\OpenSSH\ssh.exe",
                r"C:\Program Files\Git\usr\bin\ssh.exe",
            ]
            for candidate in candidates:
                if candidate and Path(candidate).exists():
                    self._ssh_path = candidate
                    return self._ssh_path
        else:
            self._ssh_path = shutil.which("ssh") or "ssh"
        
        return self._ssh_path or "ssh"
    
    @property
    def scp_path(self) -> str:
        """Get path to SCP executable."""
        if self._scp_path:
            return self._scp_path
        
        if os.name == "nt":
            candidates = [
                shutil.which("scp"),
                r"C:\Windows\System32\OpenSSH\scp.exe",
                r"C:\Program Files\Git\usr\bin\scp.exe",
            ]
            for candidate in candidates:
                if candidate and Path(candidate).exists():
                    self._scp_path = candidate
                    return self._scp_path
        else:
            self._scp_path = shutil.which("scp") or "scp"
        
        return self._scp_path or "scp"
    
    def build_connection_string(self, account: Account) -> str:
        """
        Build the CyberArk PSM connection string.
        
        Format: username@account_user@address@endpoint
        """
        return f"{self.config.username}@{account.username}@{account.address}@{self.config.endpoint}"
    
    def connect(self, account: Account, use_key: bool = True) -> int:
        """
        SSH to an account via CyberArk PSM.
        
        Returns the exit code of the SSH process.
        """
        connection_string = self.build_connection_string(account)
        
        cmd = [self.ssh_path]
        
        # Add SSH key if available
        if use_key and Path(self.config.ssh_key_path).exists():
            cmd.extend(["-i", self.config.ssh_key_path])
        
        cmd.append(connection_string)
        
        console.print(f"[cyan]Connecting to {account.username}@{account.address}...[/cyan]")
        
        # Run interactively
        result = subprocess.run(cmd)
        return result.returncode
    
    def scp_send(
        self,
        account: Account,
        local_path: str,
        remote_path: str = "~/",
        use_key: bool = True,
    ) -> int:
        """
        SCP file to remote host via CyberArk PSM.
        
        Returns the exit code of the SCP process.
        """
        connection_string = self.build_connection_string(account)
        
        cmd = [self.scp_path, "-O"]  # -O for legacy protocol compatibility
        
        if use_key and Path(self.config.ssh_key_path).exists():
            cmd.extend(["-i", self.config.ssh_key_path])
        
        cmd.extend([local_path, f"{connection_string}:{remote_path}"])
        
        console.print(f"[cyan]Sending {local_path} to {account.address}:{remote_path}...[/cyan]")
        
        result = subprocess.run(cmd)
        
        if result.returncode == 0:
            console.print("[green]Transfer complete[/green]")
        else:
            console.print(f"[red]Transfer failed (exit code: {result.returncode})[/red]")
        
        return result.returncode
    
    def scp_receive(
        self,
        account: Account,
        remote_path: str,
        local_path: str = "./",
        use_key: bool = True,
    ) -> int:
        """
        SCP file from remote host via CyberArk PSM.
        
        Returns the exit code of the SCP process.
        """
        connection_string = self.build_connection_string(account)
        
        cmd = [self.scp_path, "-O"]
        
        if use_key and Path(self.config.ssh_key_path).exists():
            cmd.extend(["-i", self.config.ssh_key_path])
        
        cmd.extend([f"{connection_string}:{remote_path}", local_path])
        
        console.print(f"[cyan]Receiving {remote_path} from {account.address}...[/cyan]")
        
        result = subprocess.run(cmd)
        
        if result.returncode == 0:
            console.print(f"[green]Transfer complete: {local_path}[/green]")
        else:
            console.print(f"[red]Transfer failed (exit code: {result.returncode})[/red]")
        
        return result.returncode

