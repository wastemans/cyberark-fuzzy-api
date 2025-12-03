"""Configuration management for CyberArk Fuzzy API."""

import os
import configparser
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Config:
    """Application configuration."""
    
    # CyberArk settings
    endpoint: str = "cyberark"
    username: str = ""  # Set in config.ini or via --username
    verify_ssl: bool = False
    
    # SSH settings
    ssh_key_path: str = ""
    key_max_age_hours: int = 9
    
    # Keepalive settings (CyberArk session timeout is 20 mins)
    keepalive_min_seconds: int = 901   # 15:01
    keepalive_max_seconds: int = 1139  # 18:59
    keepalive_timeout_hours: float = 9.0  # Hard timeout for detached keepalive process
    
    # UI settings
    rich_output: bool = True
    default_search: str = ""
    
    def __post_init__(self):
        if not self.ssh_key_path:
            self.ssh_key_path = str(self.config_dir / "key.openssh")
    
    @property
    def base_url(self) -> str:
        """Get the base URL for API requests."""
        return f"https://{self.endpoint}"
    
    @property
    def config_dir(self) -> Path:
        """Get the config directory path (project root, where main.py lives)."""
        # Use resolve() to get absolute path - works on Windows and Linux
        # regardless of current working directory
        return Path(__file__).resolve().parent.parent
    
    @property
    def token_path(self) -> Path:
        """Path to stored session token."""
        return self.config_dir / "token"
    
    @property
    def keepalive_pid_path(self) -> Path:
        """Path to keepalive PID file."""
        return self.config_dir / "keepalive.pid"
    
    @property
    def keepalive_log_path(self) -> Path:
        """Path to keepalive log file."""
        return self.config_dir / "keepalive.log"
    
    def ensure_config_dir(self) -> None:
        """Create config directory if it doesn't exist."""
        self.config_dir.mkdir(parents=True, exist_ok=True)
        # Set restrictive permissions on Unix
        if os.name != "nt":
            os.chmod(self.config_dir, 0o700)


def _find_config_file() -> Optional[Path]:
    """
    Find the config file, checking multiple locations.
    
    Priority:
    1. ./config.ini (current directory)
    2. <project>/config.ini (where main.py lives)
    3. <project>/config.ini.example (fallback)
    """
    # Project root is where main.py lives (parent of cyberark_fuzzy package)
    project_root = Path(__file__).resolve().parent.parent
    
    candidates = [
        Path("config.ini"),  # CWD - for convenience when running from project dir
        project_root / "config.ini",
        project_root / "config.ini.example",
    ]
    
    for path in candidates:
        if path.exists():
            return path
    
    return None


def _parse_bool(value: str) -> bool:
    """Parse a boolean from string."""
    return value.lower() in ("true", "yes", "1", "on")


def load_config(
    config_file: Optional[Path] = None,
    endpoint: Optional[str] = None,
    username: Optional[str] = None,
) -> Config:
    """
    Load configuration from INI file.
    
    Args:
        config_file: Path to config file (auto-detected if not specified)
        endpoint: Override endpoint from CLI
        username: Override username from CLI
    
    Returns:
        Config object with loaded settings
    """
    config = Config()
    
    # Find and parse config file
    if config_file is None:
        config_file = _find_config_file()
    
    if config_file and config_file.exists():
        parser = configparser.ConfigParser()
        parser.read(config_file)
        
        # [cyberark] section
        if parser.has_section("cyberark"):
            if parser.has_option("cyberark", "endpoint"):
                config.endpoint = parser.get("cyberark", "endpoint")
            if parser.has_option("cyberark", "username"):
                config.username = parser.get("cyberark", "username")
            if parser.has_option("cyberark", "verify_ssl"):
                config.verify_ssl = _parse_bool(parser.get("cyberark", "verify_ssl"))
        
        # [ssh] section
        if parser.has_section("ssh"):
            if parser.has_option("ssh", "ssh_key_path"):
                val = parser.get("ssh", "ssh_key_path").strip()
                if val:
                    config.ssh_key_path = val
            if parser.has_option("ssh", "key_max_age_hours"):
                config.key_max_age_hours = parser.getint("ssh", "key_max_age_hours")
        
        # [keepalive] section
        if parser.has_section("keepalive"):
            if parser.has_option("keepalive", "min_seconds"):
                config.keepalive_min_seconds = parser.getint("keepalive", "min_seconds")
            if parser.has_option("keepalive", "max_seconds"):
                config.keepalive_max_seconds = parser.getint("keepalive", "max_seconds")
            if parser.has_option("keepalive", "timeout_hours"):
                config.keepalive_timeout_hours = parser.getfloat("keepalive", "timeout_hours")
        
        # [ui] section
        if parser.has_section("ui"):
            if parser.has_option("ui", "rich_output"):
                config.rich_output = _parse_bool(parser.get("ui", "rich_output"))
            if parser.has_option("ui", "default_search"):
                config.default_search = parser.get("ui", "default_search").strip()
    
    # CLI overrides take precedence
    if endpoint:
        config.endpoint = endpoint
    if username:
        config.username = username
    
    # Ensure ssh_key_path is set after all loading
    if not config.ssh_key_path:
        config.ssh_key_path = str(config.config_dir / "key.openssh")
    
    return config


# Backwards compatibility alias
def get_config(endpoint: Optional[str] = None, username: Optional[str] = None) -> Config:
    """Get configuration (alias for load_config)."""
    return load_config(endpoint=endpoint, username=username)
