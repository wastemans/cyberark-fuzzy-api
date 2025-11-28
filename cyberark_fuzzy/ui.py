"""Interactive UI components using questionary for fuzzy selection."""

from typing import Optional, TypeVar, Callable
from enum import Enum

import questionary
from questionary import Style
from rich.console import Console

from .accounts import Account

console = Console()

T = TypeVar("T")


# Custom style for questionary
STYLE = Style([
    ("qmark", "fg:cyan bold"),
    ("question", "bold"),
    ("answer", "fg:green bold"),
    ("pointer", "fg:cyan bold"),
    ("highlighted", "fg:cyan bold"),
    ("selected", "fg:green"),
])


class AccountAction(Enum):
    """Available actions for an account."""
    
    SSH = "SSH"
    GET_PASSWORD = "Get Password"
    INFO = "Info"
    VERIFY = "Verify"
    SCP_SEND = "SCP Send"
    SCP_RECEIVE = "SCP Receive"
    CHANGE = "Change"
    DELETE = "Delete"
    BACK = "← Back to search"


def select_account(accounts: list[Account]) -> Optional[Account]:
    """
    Interactive fuzzy selection of an account.
    
    Returns the selected Account or None if cancelled.
    """
    if not accounts:
        console.print("[yellow]No accounts to select from[/yellow]")
        return None
    
    choices = [
        questionary.Choice(
            title=acc.display_name,
            value=acc,
        )
        for acc in accounts
    ]
    
    result = questionary.select(
        "Select an account:",
        choices=choices,
        style=STYLE,
        use_shortcuts=True,
    ).ask()
    
    return result


def select_action() -> Optional[AccountAction]:
    """
    Select an action to perform on an account.
    
    Returns the selected action or None if cancelled.
    """
    # Group actions visually
    choices = [
        questionary.Choice(title="SSH", value=AccountAction.SSH),
        questionary.Separator("── Information ──"),
        questionary.Choice(title="Get Password", value=AccountAction.GET_PASSWORD),
        questionary.Choice(title="Info", value=AccountAction.INFO),
        questionary.Choice(title="Verify", value=AccountAction.VERIFY),
        questionary.Separator("── SCP ──"),
        questionary.Choice(title="SCP Send", value=AccountAction.SCP_SEND),
        questionary.Choice(title="SCP Receive", value=AccountAction.SCP_RECEIVE),
        questionary.Separator("── Modify ──"),
        questionary.Choice(title="Change", value=AccountAction.CHANGE),
        questionary.Choice(title="Delete", value=AccountAction.DELETE),
        questionary.Separator("──────────"),
        questionary.Choice(title="← Back to search", value=AccountAction.BACK),
    ]
    
    result = questionary.select(
        "Select an action:",
        choices=choices,
        style=STYLE,
    ).ask()
    
    return result


def prompt_search() -> Optional[str]:
    """
    Prompt for a search term.
    
    Returns the search term or None if cancelled.
    """
    return questionary.text(
        "Search for accounts:",
        style=STYLE,
    ).ask()


def prompt_path(message: str, default: str = "") -> Optional[str]:
    """
    Prompt for a file path.
    
    Returns the path or None if cancelled.
    """
    return questionary.path(
        message,
        default=default,
        style=STYLE,
    ).ask()


def confirm(message: str, default: bool = False) -> bool:
    """Confirm a yes/no question."""
    result = questionary.confirm(
        message,
        default=default,
        style=STYLE,
    ).ask()
    return result if result is not None else False

