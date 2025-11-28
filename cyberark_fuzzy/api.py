"""CyberArk REST API client."""

import requests
from typing import Optional, Any
from dataclasses import dataclass

from .config import Config


@dataclass
class APIError(Exception):
    """API request failed."""
    status_code: int
    message: str
    error_code: Optional[str] = None


class CyberArkAPI:
    """CyberArk REST API client."""
    
    def __init__(self, config: Config):
        self.config = config
        self.session = requests.Session()
        self.session.verify = config.verify_ssl
        self._token: Optional[str] = None
        
        # Suppress SSL warnings if not verifying
        if not config.verify_ssl:
            import urllib3
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    @property
    def base_url(self) -> str:
        return f"{self.config.base_url}/PasswordVault/API"
    
    @property
    def token(self) -> Optional[str]:
        """Get current session token."""
        if self._token:
            return self._token
        # Try loading from file
        if self.config.token_path.exists():
            self._token = self.config.token_path.read_text().strip()
        return self._token
    
    @token.setter
    def token(self, value: str) -> None:
        """Set and persist session token."""
        self._token = value
        self.config.ensure_config_dir()
        self.config.token_path.write_text(value)
    
    def clear_token(self) -> None:
        """Clear session token."""
        self._token = None
        if self.config.token_path.exists():
            self.config.token_path.unlink()
    
    def _headers(self) -> dict:
        """Get request headers."""
        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = self.token
        return headers
    
    def _request(
        self,
        method: str,
        endpoint: str,
        data: Optional[dict] = None,
        params: Optional[dict] = None,
    ) -> Any:
        """Make an API request."""
        url = f"{self.base_url}/{endpoint}"
        
        response = self.session.request(
            method=method,
            url=url,
            headers=self._headers(),
            json=data,
            params=params,
        )
        
        if response.status_code >= 400:
            error_msg = response.text
            error_code = None
            try:
                error_data = response.json()
                error_msg = error_data.get("ErrorMessage", error_msg)
                error_code = error_data.get("ErrorCode")
            except:
                pass
            raise APIError(response.status_code, error_msg, error_code)
        
        if response.text:
            return response.json()
        return None
    
    def get(self, endpoint: str, params: Optional[dict] = None) -> Any:
        """GET request."""
        return self._request("GET", endpoint, params=params)
    
    def post(self, endpoint: str, data: Optional[dict] = None) -> Any:
        """POST request."""
        return self._request("POST", endpoint, data=data)
    
    def delete(self, endpoint: str) -> Any:
        """DELETE request."""
        return self._request("DELETE", endpoint)
    
    # ---------------------------------------------------------------------
    # Authentication
    # ---------------------------------------------------------------------
    
    def logon_radius(self, username: str, password: str, concurrent: bool = True) -> str:
        """
        Authenticate using RADIUS.
        
        Returns the session token.
        """
        data = {
            "username": username,
            "password": password,
            "concurrentSession": concurrent,
        }
        
        # RADIUS auth endpoint
        url = f"{self.config.base_url}/PasswordVault/API/Auth/RADIUS/Logon"
        response = self.session.post(url, json=data, headers={"Content-Type": "application/json"})
        
        if response.status_code >= 400:
            raise APIError(response.status_code, response.text)
        
        # Token is returned as a quoted string
        token = response.text.strip().strip('"')
        self.token = token
        return token
    
    def logoff(self) -> None:
        """Log off and invalidate the session."""
        if self.token:
            try:
                self.post("Auth/Logoff")
            except:
                pass
            self.clear_token()
    
    def verify_session(self) -> bool:
        """Check if the current session is valid."""
        if not self.token:
            return False
        try:
            self.get("Safes", params={"limit": 1})
            return True
        except APIError:
            return False
    
    # ---------------------------------------------------------------------
    # Safes
    # ---------------------------------------------------------------------
    
    def list_safes(self, search: Optional[str] = None, limit: int = 100) -> list[dict]:
        """List safes."""
        params = {"limit": limit}
        if search:
            params["search"] = search
        result = self.get("Safes", params=params)
        return result.get("value", [])
    
    # ---------------------------------------------------------------------
    # Accounts
    # ---------------------------------------------------------------------
    
    def search_accounts(self, search: str, limit: int = 100) -> list[dict]:
        """Search for accounts."""
        params = {"search": search, "limit": limit}
        result = self.get("Accounts", params=params)
        return result.get("value", [])
    
    def get_account(self, account_id: str) -> dict:
        """Get account details."""
        return self.get(f"Accounts/{account_id}")
    
    def get_account_password(self, account_id: str) -> str:
        """Retrieve account password."""
        result = self.post(f"Accounts/{account_id}/Password/Retrieve")
        return result
    
    def verify_account(self, account_id: str) -> None:
        """Trigger password verification."""
        self.post(f"Accounts/{account_id}/Verify")
    
    def change_account(self, account_id: str) -> None:
        """Trigger password change."""
        self.post(f"Accounts/{account_id}/Change")
    
    def delete_account(self, account_id: str) -> None:
        """Delete an account."""
        self.delete(f"Accounts/{account_id}")
    
    # ---------------------------------------------------------------------
    # SSH Keys (MFA Caching)
    # ---------------------------------------------------------------------
    
    def get_ssh_key(self) -> Optional[str]:
        """
        Request MFA caching SSH key.
        
        Returns the private key in OpenSSH format.
        """
        url = f"{self.config.base_url}/PasswordVault/API/Users/Secret/SSHKeys/Cache/"
        data = {"keyPassword": "", "formats": ["OpenSSH"]}
        
        response = self.session.post(
            url,
            json=data,
            headers=self._headers(),
        )
        
        if response.status_code >= 400:
            raise APIError(response.status_code, response.text)
        
        result = response.json()
        for key_format in result.get("value", []):
            if key_format.get("format") == "OpenSSH":
                return key_format.get("privateKey")
        
        return None

