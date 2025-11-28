#!/usr/bin/env python3
"""
Standalone keepalive process for CyberArk session tokens.

This runs as a detached subprocess to keep the API token alive even after
the main application exits. It will auto-terminate after the hard timeout.

Usage:
    python -m cyberark_fuzzy.keepalive --endpoint cyberark --timeout 32400
"""

import os
import sys
import time
import random
import signal
import argparse
from pathlib import Path
from datetime import datetime


def get_project_dir() -> Path:
    """Get the project root directory."""
    return Path(__file__).parent.parent


def log(message: str, log_path: Path) -> None:
    """Append a timestamped message to the log file."""
    with open(log_path, "a") as f:
        f.write(f"[{datetime.now()}] {message}\n")


def ping_api(endpoint: str, token: str, verify_ssl: bool = False) -> bool:
    """Ping the CyberArk API to keep the token alive."""
    import requests
    import urllib3
    
    if not verify_ssl:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    url = f"https://{endpoint}/PasswordVault/API/Safes"
    headers = {
        "Authorization": token,
        "Content-Type": "application/json",
    }
    
    try:
        response = requests.get(
            url,
            headers=headers,
            params={"limit": 1},
            verify=verify_ssl,
            timeout=30,
        )
        return response.status_code < 400
    except Exception:
        return False


def run_keepalive(
    endpoint: str,
    timeout_seconds: int = 32400,  # 9 hours default
    min_interval: int = 901,       # 15:01
    max_interval: int = 1139,      # 18:59
) -> None:
    """
    Run the keepalive loop.
    
    Args:
        endpoint: CyberArk endpoint hostname
        timeout_seconds: Hard timeout after which to exit (default 9 hours)
        min_interval: Minimum seconds between pings
        max_interval: Maximum seconds between pings
    """
    project_dir = get_project_dir()
    token_path = project_dir / "token"
    log_path = project_dir / "keepalive.log"
    pid_path = project_dir / "keepalive.pid"
    
    # Write our PID
    pid_path.write_text(str(os.getpid()))
    
    # Initialize log
    with open(log_path, "w") as f:
        f.write(f"[{datetime.now()}] Keepalive started for endpoint: {endpoint}\n")
        f.write(f"[{datetime.now()}] Hard timeout: {timeout_seconds}s ({timeout_seconds/3600:.1f} hours)\n")
        f.write(f"[{datetime.now()}] PID: {os.getpid()}\n")
    
    start_time = time.time()
    
    # Handle graceful shutdown
    def shutdown(signum, frame):
        log(f"Received signal {signum}, shutting down", log_path)
        cleanup_and_exit(0)
    
    def cleanup_and_exit(code: int):
        if pid_path.exists():
            pid_path.unlink()
        sys.exit(code)
    
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    
    while True:
        elapsed = time.time() - start_time
        remaining = timeout_seconds - elapsed
        
        # Check hard timeout
        if remaining <= 0:
            log(f"Hard timeout reached ({timeout_seconds}s), exiting", log_path)
            cleanup_and_exit(0)
        
        # Random sleep between min and max interval
        sleep_time = min(random.randint(min_interval, max_interval), remaining)
        
        log(f"Sleeping {sleep_time}s (remaining: {remaining/3600:.1f}h)", log_path)
        time.sleep(sleep_time)
        
        # Check timeout again after sleep
        elapsed = time.time() - start_time
        if elapsed >= timeout_seconds:
            log(f"Hard timeout reached after sleep, exiting", log_path)
            cleanup_and_exit(0)
        
        # Read fresh token from file
        if not token_path.exists():
            log("Token file missing, exiting", log_path)
            cleanup_and_exit(1)
        
        token = token_path.read_text().strip()
        if not token:
            log("Token is empty, exiting", log_path)
            cleanup_and_exit(1)
        
        # Ping the API
        if ping_api(endpoint, token):
            log(f"Keepalive ping successful (elapsed: {elapsed/3600:.1f}h)", log_path)
        else:
            log("Keepalive ping failed - token expired or invalid, exiting", log_path)
            cleanup_and_exit(1)


def main():
    parser = argparse.ArgumentParser(description="CyberArk token keepalive daemon")
    parser.add_argument(
        "--endpoint", "-e",
        default="cyberark",
        help="CyberArk endpoint hostname",
    )
    parser.add_argument(
        "--timeout", "-t",
        type=int,
        default=32400,  # 9 hours
        help="Hard timeout in seconds (default: 32400 = 9 hours)",
    )
    parser.add_argument(
        "--min-interval",
        type=int,
        default=901,
        help="Minimum seconds between pings (default: 901)",
    )
    parser.add_argument(
        "--max-interval",
        type=int,
        default=1139,
        help="Maximum seconds between pings (default: 1139)",
    )
    
    args = parser.parse_args()
    
    run_keepalive(
        endpoint=args.endpoint,
        timeout_seconds=args.timeout,
        min_interval=args.min_interval,
        max_interval=args.max_interval,
    )


if __name__ == "__main__":
    main()

