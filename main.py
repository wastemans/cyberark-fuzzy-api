#!/usr/bin/env python3
"""
CyberArk Fuzzy API - Interactive CyberArk account management.

Usage:
    python main.py [hostname] [--endpoint ENDPOINT] [--username USERNAME]

Examples:
    python main.py                     # Interactive mode, default endpoint
    python main.py webserver01         # Search for 'webserver01'
    python main.py --endpoint cyberark-dr  # Use alternate endpoint
"""

import sys
import argparse
import json

from rich.console import Console

from cyberark_fuzzy.config import get_config
from cyberark_fuzzy.api import CyberArkAPI
from cyberark_fuzzy.auth import AuthManager
from cyberark_fuzzy.accounts import AccountManager, Account
from cyberark_fuzzy.ssh import SSHManager
from cyberark_fuzzy.ui import (
    select_account,
    select_action,
    prompt_search,
    prompt_path,
    confirm,
    AccountAction,
)

console = Console()


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Interactive CyberArk account management",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "search",
        nargs="?",
        help="Initial search term (optional)",
    )
    parser.add_argument(
        "--endpoint", "-e",
        default="cyberark",
        help="CyberArk endpoint (default: cyberark)",
    )
    parser.add_argument(
        "--username", "-u",
        default=None,
        help="Username for authentication (default: from config.ini)",
    )
    parser.add_argument(
        "--save-password",
        action="store_true",
        help="Save password to credential store",
    )
    return parser.parse_args()


def handle_action(
    action: AccountAction,
    account: Account,
    account_mgr: AccountManager,
    ssh_mgr: SSHManager,
) -> bool:
    """
    Handle the selected action.
    
    Returns True if should continue with action menu, False to go back to search.
    """
    match action:
        case AccountAction.SSH:
            ssh_mgr.connect(account)
        
        case AccountAction.GET_PASSWORD:
            password = account_mgr.get_password(account)
            if password:
                console.print(f"[green]Password:[/green] {password}")
        
        case AccountAction.INFO:
            info = account_mgr.get_info(account)
            if info:
                console.print_json(json.dumps(info, indent=2))
        
        case AccountAction.VERIFY:
            account_mgr.verify(account)
        
        case AccountAction.SCP_SEND:
            local_path = prompt_path("Local source path:")
            if local_path:
                remote_path = prompt_path("Remote destination path:", default="~/")
                if remote_path:
                    ssh_mgr.scp_send(account, local_path, remote_path)
        
        case AccountAction.SCP_RECEIVE:
            remote_path = prompt_path("Remote source path:")
            if remote_path:
                local_path = prompt_path("Local destination path:", default="./")
                if local_path:
                    ssh_mgr.scp_receive(account, remote_path, local_path)
        
        case AccountAction.CHANGE:
            if confirm(f"Change password for {account.username}@{account.address}?"):
                account_mgr.change(account)
        
        case AccountAction.DELETE:
            account_mgr.delete(account)
        
        case AccountAction.BACK:
            return False
    
    return True


def main() -> int:
    """Main entry point."""
    args = parse_args()
    
    # Initialize components
    config = get_config(endpoint=args.endpoint, username=args.username)
    config.ensure_config_dir()
    
    api = CyberArkAPI(config)
    auth_mgr = AuthManager(config, api)
    account_mgr = AccountManager(api)
    ssh_mgr = SSHManager(config)
    
    # Authenticate
    if not auth_mgr.check_and_refresh():
        if not auth_mgr.authenticate(save_password=args.save_password):
            console.print("[red]Authentication failed. Exiting.[/red]")
            return 1
    
    # Start keepalive
    auth_mgr.start_keepalive()
    
    # Download SSH key for default endpoint
    if config.endpoint == "cyberark":
        auth_mgr.download_ssh_key()
    else:
        console.print("[yellow]Alternate endpoint - skipping SSH key download[/yellow]")
    
    try:
        # Main loop
        search_term = args.search
        
        while True:
            # Get search term if not provided
            if not search_term:
                search_term = prompt_search()
                if not search_term:
                    break
            
            # Check auth is still valid
            if not auth_mgr.check_and_refresh():
                console.print("[red]Authentication lost. Exiting.[/red]")
                return 1
            
            # Search for accounts
            console.print(f"[cyan]Searching for: {search_term}[/cyan]")
            accounts = account_mgr.search(search_term)
            
            if not accounts:
                console.print("[yellow]No accounts found[/yellow]")
                search_term = None
                continue
            
            # Select account
            account = select_account(accounts)
            if not account:
                search_term = None
                continue
            
            # Action loop for selected account
            while True:
                action = select_action()
                if not action:
                    break
                
                if not handle_action(action, account, account_mgr, ssh_mgr):
                    break
                
                # Check auth after action
                if not auth_mgr.check_and_refresh():
                    console.print("[red]Authentication lost.[/red]")
                    break
                
                input("\nPress Enter to continue...")
            
            # Reset search for next iteration
            search_term = None
    
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrupted[/yellow]")
    
    # Note: We intentionally don't stop the keepalive here.
    # It runs as a detached process with a ~9 hour hard timeout,
    # keeping the token alive even after this script exits.
    # To manually stop it: kill the PID in keepalive.pid
    
    return 0


if __name__ == "__main__":
    sys.exit(main())

