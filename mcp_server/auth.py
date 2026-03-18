from typing import Optional
import msal
from config import AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, USE_AUTH

_msal_app: Optional[msal.ConfidentialClientApplication] = None


def get_msal_app() -> Optional[msal.ConfidentialClientApplication]:
    global _msal_app
    if not USE_AUTH:
        return None
    
    if _msal_app is None:
        _msal_app = msal.ConfidentialClientApplication(
            client_id=AZURE_CLIENT_ID,
            client_credential=AZURE_CLIENT_SECRET,
            authority=f"https://login.microsoftonline.com/{AZURE_TENANT_ID}"
        )
    return _msal_app


async def authenticate() -> dict:
    """
    Initiate Microsoft Entra ID authentication.
    Returns device code flow details.
    """
    app = get_msal_app()
    if not app:
        return {"status": "disabled", "message": "Auth not configured"}
    
    flow = app.initiate_device_flow(scopes=["User.Read", "GroupMember.Read.All"])
    
    return {
        "status": "pending",
        "message": flow["message"],
        "user_code": flow["user_code"],
        "device_code": flow["device_code"]
    }


async def complete_authentication(flow_data: dict) -> dict:
    """
    Complete authentication after user approves device code.
    """
    app = get_msal_app()
    if not app:
        return {"status": "disabled"}
    
    result = app.acquire_token_by_device_flow(flow_data)
    
    if "access_token" in result:
        return {
            "status": "success",
            "access_token": result["access_token"],
            "expires_in": result.get("expires_in")
        }
    else:
        return {
            "status": "error",
            "error": result.get("error"),
            "error_description": result.get("error_description")
        }


async def get_user_groups(access_token: str) -> list:
    """
    Get user's Entra ID group memberships.
    """
    import aiohttp
    
    async with aiohttp.ClientSession() as session:
        headers = {"Authorization": f"Bearer {access_token}"}
        async with session.get(
            "https://graph.microsoft.com/v1.0/me/memberOf",
            headers=headers
        ) as resp:
            data = await resp.json()
            return data.get("value", [])
