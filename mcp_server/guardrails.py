import re
from typing import Optional, List
from config import PII_DETECTION_ENABLED

PII_PATTERNS = {
    "email": r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',
    "phone": r'\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b',
    "ssn": r'\b\d{3}-\d{2}-\d{4}\b',
    "credit_card": r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b',
}


def redact_pii(text: str) -> str:
    """
    Redact PII from text.
    """
    if not PII_DETECTION_ENABLED:
        return text
    
    redacted = text
    for pii_type, pattern in PII_PATTERNS.items():
        redacted = re.sub(pattern, f"[{pii_type}_redacted]", redacted)
    
    return redacted


def check_topic_allowed(query: str, allowed_topics: List[str]) -> bool:
    """
    Check if query is within allowed topics.
    """
    query_lower = query.lower()
    for topic in allowed_topics:
        if topic.lower() in query_lower:
            return True
    return False


class Guardrails:
    def __init__(self, allowed_topics: List[str] = None):
        self.allowed_topics = allowed_topics or ["document", "search", "knowledge", "prm"]
    
    def filter_input(self, text: str) -> str:
        """Filter input text for PII."""
        return redact_pii(text)
    
    def filter_output(self, text: str) -> str:
        """Filter output text for PII."""
        return redact_pii(text)
    
    def validate_query(self, query: str) -> dict:
        """Validate if query is allowed."""
        if not check_topic_allowed(query, self.allowed_topics):
            return {
                "allowed": False,
                "reason": "Query outside allowed topics"
            }
        
        filtered = self.filter_input(query)
        return {
            "allowed": True,
            "filtered_query": filtered
        }
