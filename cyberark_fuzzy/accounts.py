"""Account operations."""

from dataclasses import dataclass
from typing import Optional

from rich.console import Console
from rich.table import Table

from .api import CyberArkAPI, APIError

console = Console()


@dataclass
class Account:
    """Represents a CyberArk account."""
    
    id: str
    address: str
    username: str
    platform_id: str
    safe_name: str
    status: str
    
    @classmethod
    def from_api(cls, data: dict) -> "Account":
        """Create Account from API response."""
        return cls(
            id=data.get("id", ""),
            address=data.get("address", ""),
            username=data.get("userName", ""),
            platform_id=data.get("platformId", ""),
            safe_name=data.get("safeName", ""),
            status=data.get("secretManagement", {}).get("status", "unknown"),
        )
    
    @property
    def display_name(self) -> str:
        """Human-readable display name for selection."""
        return f"{self.id} | {self.address} | {self.username} | {self.status}"


class AccountManager:
    """Manages account operations."""
    
    def __init__(self, api: CyberArkAPI):
        self.api = api
    
    def search(self, query: str) -> list[Account]:
        """Search for accounts matching query."""
        try:
            results = self.api.search_accounts(query)
            return [Account.from_api(acc) for acc in results]
        except APIError as e:
            console.print(f"[red]Search failed: {e.message}[/red]")
            return []
    
    def get_password(self, account: Account) -> Optional[str]:
        """Retrieve password for account."""
        try:
            result = self.api.get_account_password(account.id)
            return result
        except APIError as e:
            console.print(f"[red]Failed to get password: {e.message}[/red]")
            return None
    
    def get_info(self, account: Account) -> Optional[dict]:
        """Get detailed account information."""
        try:
            return self.api.get_account(account.id)
        except APIError as e:
            console.print(f"[red]Failed to get account info: {e.message}[/red]")
            return None
    
    def verify(self, account: Account) -> bool:
        """Trigger password verification."""
        try:
            self.api.verify_account(account.id)
            console.print(f"[green]Verification triggered for {account.username}@{account.address}[/green]")
            return True
        except APIError as e:
            console.print(f"[red]Verification failed: {e.message}[/red]")
            return False
    
    def change(self, account: Account) -> bool:
        """Trigger password change."""
        try:
            self.api.change_account(account.id)
            console.print(f"[green]Change triggered for {account.username}@{account.address}[/green]")
            return True
        except APIError as e:
            console.print(f"[red]Change failed: {e.message}[/red]")
            return False
    
    def delete(self, account: Account, confirm: bool = True) -> bool:
        """Delete an account."""
        if confirm:
            console.print(f"[bold red]About to delete: {account.username}@{account.address}[/bold red]")
            response = input("Are you sure? (yes/no): ")
            if response.lower() != "yes":
                console.print("[yellow]Cancelled[/yellow]")
                return False
        
        try:
            self.api.delete_account(account.id)
            console.print(f"[green]Deleted {account.username}@{account.address}[/green]")
            return True
        except APIError as e:
            console.print(f"[red]Delete failed: {e.message}[/red]")
            return False
    
    def display_accounts(self, accounts: list[Account]) -> None:
        """Display accounts in a table."""
        table = Table(title="Accounts")
        table.add_column("ID", style="dim")
        table.add_column("Address", style="cyan")
        table.add_column("Username", style="green")
        table.add_column("Platform", style="yellow")
        table.add_column("Safe", style="blue")
        table.add_column("Status", style="magenta")
        
        for acc in accounts:
            table.add_row(
                acc.id,
                acc.address,
                acc.username,
                acc.platform_id,
                acc.safe_name,
                acc.status,
            )
        
        console.print(table)

