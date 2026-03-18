from typing import Optional, Any, Dict
from config import LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, USE_LANGFUSE

_langfuse_client: Optional[Any] = None


def get_langfuse_client():
    global _langfuse_client
    if not USE_LANGFUSE:
        return None
    
    if _langfuse_client is None:
        try:
            from langfuse import Langfuse
            _langfuse_client = Langfuse(
                public_key=LANGFUSE_PUBLIC_KEY,
                secret_key=LANGFUSE_SECRET_KEY,
            )
        except Exception:
            return None
    return _langfuse_client


def trace_generation(prompt: str, model: str, completion: str, metadata: Dict = None) -> Optional[Any]:
    """
    Trace an LLM generation with Langfuse.
    """
    langfuse = get_langfuse_client()
    if not langfuse:
        return None
    
    try:
        return langfuse.trace(
            name="smartie_prm_generation",
            metadata=metadata or {},
            input={"prompt": prompt},
            output={"completion": completion}
        )
    except Exception:
        return None


def log_cost(usage: dict, model: str, user_id: str = None) -> None:
    """
    Log token usage and cost to Langfuse.
    """
    langfuse = get_langfuse_client()
    if not langfuse:
        return
    
    try:
        langfuse.capture_event(
            name="cost_tracking",
            metadata={
                "model": model,
                "usage": usage,
                "user_id": user_id
            }
        )
    except Exception:
        pass
