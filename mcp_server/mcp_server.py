from typing import Optional, List
from pathlib import Path
from fastmcp import FastMCP
import json
import asyncio
import aiohttp

from config import (
    OPENVIKING_ENTERPRISE_URL,
    USE_AUTH,
    USE_LANGFUSE,
    AZURE_CLIENT_ID,
    LANGFUSE_HOST,
    LANGFUSE_PUBLIC_KEY,
    LANGFUSE_SECRET_KEY,
)

mcp = FastMCP("smartie_prm")

user_token: Optional[str] = None
user_info: Optional[dict] = None


@mcp.tool()
async def authenticate() -> dict:
    """
    Initiate Microsoft Entra ID authentication using device code flow.
    """
    global user_token, user_info
    
    if not USE_AUTH:
        return {"status": "error", "message": "Authentication is not configured."}
    
    from msal import PublicClientApplication
    from config import AZURE_TENANT_ID
    
    app = PublicClientApplication(
        client_id=AZURE_CLIENT_ID,
        authority=f"https://login.microsoftonline.com/{AZURE_TENANT_ID}"
    )
    
    flow = app.initiate_device_flow(scopes=["User.Read", "GroupMember.Read.All"])
    
    if "user_code" not in flow:
        return {"status": "error", "message": "Failed to initiate auth flow."}
    
    return {
        "status": "pending",
        "message": flow.get("message", "Please authenticate"),
        "user_code": flow.get("user_code"),
        "device_code": flow.get("device_code"),
        "instructions": "1. Go to https://microsoft.com/devicelogin\n2. Enter the code above\n3. Approve\n4. Run complete_authentication"
    }


@mcp.tool()
async def complete_authentication(flow_data: dict) -> dict:
    """
    Complete Microsoft Entra ID authentication.
    """
    global user_token, user_info
    
    from msal import PublicClientApplication
    from config import AZURE_TENANT_ID
    import jwt
    
    app = PublicClientApplication(
        client_id=AZURE_CLIENT_ID,
        authority=f"https://login.microsoftonline.com/{AZURE_TENANT_ID}"
    )
    
    result = app.acquire_token_by_device_flow(flow_data)
    
    if "access_token" not in result:
        return {"status": "error", "error": result.get("error")}
    
    user_token = result["access_token"]
    decoded = jwt.decode(user_token, options={"verify_signature": False})
    
    user_info = {
        "email": decoded.get("preferred_username", decoded.get("email")),
        "oid": decoded.get("oid"),
        "name": decoded.get("name")
    }
    
    return {"status": "success", "user": user_info}


@mcp.tool()
async def search_enterprise_documents(
    query: str,
    limit: int = 10
) -> dict:
    """
    Search enterprise documents via OpenViking Knowledge Service.
    OpenViking handles query embedding and vector similarity search against its local VectorDB.
    """
    try:
        async with aiohttp.ClientSession() as session:
            payload = {"query": query, "limit": limit}
            async with session.post(f"{OPENVIKING_ENTERPRISE_URL}/api/v1/search", json=payload) as response:
                if response.status != 200:
                    return {"error": f"OpenViking search failed with status {response.status}"}
                
                result_data = await response.json()
                results = result_data.get("results", [])
                
        return {
            "query": query,
            "source": "openviking_enterprise",
            "count": len(results),
            "results": results,
        }
    except Exception as e:
        return {"error": f"OpenViking search failed: {str(e)}"}


@mcp.tool()
async def get_status() -> dict:
    """
    Get system status including OpenViking health.
    """
    ov_healthy = False
    ov_status = {}
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{OPENVIKING_ENTERPRISE_URL}/health", timeout=5) as health_resp:
                if health_resp.status == 200:
                    ov_healthy = True
            if ov_healthy:
                async with session.get(f"{OPENVIKING_ENTERPRISE_URL}/api/v1/system/status", timeout=5) as stat_resp:
                    if stat_resp.status == 200:
                        ov_status = await stat_resp.json()
    except Exception:
        pass

    return {
        "service": "smartie_prm",
        "version": "1.0.0-mvp1",
        "authenticated": user_token is not None,
        "user": user_info,
        "openviking": {
            "status": "healthy" if ov_healthy else "unreachable",
            "url": OPENVIKING_ENTERPRISE_URL,
            "details": ov_status
        }
    }


if __name__ == "__main__":
    mcp.run()
