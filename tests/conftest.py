# Test configuration and shared fixtures
import pytest
import sys
import os

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


@pytest.fixture
def mock_env():
    """Fixture to set up test environment variables"""
    test_env = {
        'TESTING': 'true',
        'AWS_DEFAULT_REGION': 'us-east-1',
        'SQS_QUEUE_URL': 'https://sqs.us-east-1.amazonaws.com/123456789/test-queue',
    }
    with pytest.MonkeyPatch.context() as m:
        for key, value in test_env.items():
            m.setenv(key, value)
        yield test_env


@pytest.fixture
def sample_document():
    """Fixture for sample document"""
    return {
        "id": "doc-123",
        "content": "This is a test document about company tax policy.",
        "metadata": {
            "source": "test.pdf",
            "uploaded_at": "2026-01-01T00:00:00Z"
        }
    }


@pytest.fixture
def sample_search_results():
    """Fixture for sample search results"""
    return {
        "resources": [
            {
                "id": "resource-1",
                "content": "Tax policy document...",
                "_score": 0.95,
                "metadata": {"source": "tax_policy.pdf"}
            },
            {
                "id": "resource-2",
                "content": "Tax benefits overview...",
                "_score": 0.87,
                "metadata": {"source": "benefits.pdf"}
            }
        ],
        "total": 2
    }


@pytest.fixture
def sample_s3_event():
    """Fixture for sample S3 event"""
    return {
        "Records": [{
            "eventSource": "aws:s3",
            "eventName": "ObjectCreated:Put",
            "s3": {
                "bucket": {"name": "smartie-dev-docs"},
                "object": {"key": "documents/2026_TT-BTC_m_672539.pdf"}
            }
        }]
    }
