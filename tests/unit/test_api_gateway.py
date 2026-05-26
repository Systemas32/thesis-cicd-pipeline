"""Unit tests for the api-gateway Flask service.

These tests exercise the gateway in isolation, with no Kubernetes or
user-service involvement. The external HTTP call to user-service is
mocked.

Run from the repository root with the gateway on PYTHONPATH:
    PYTHONPATH=microservices/api-gateway pytest tests/unit/test_api_gateway.py
"""
from unittest.mock import patch

import pytest
import requests

from app.main import app as flask_app


@pytest.fixture
def client():
    flask_app.config["TESTING"] = True
    with flask_app.test_client() as test_client:
        yield test_client


def test_health_returns_200_and_healthy_status(client):
    response = client.get("/health")
    assert response.status_code == 200
    body = response.get_json()
    assert body["status"] == "healthy"
    assert body["service"] == "api-gateway"


def test_ready_returns_503_when_user_service_unreachable(client):
    # Force the call to user-service to raise a connection error so the
    # readiness handler falls through to its not_ready branch.
    with patch("app.main.requests.get") as mock_get:
        mock_get.side_effect = requests.exceptions.ConnectionError(
            "user-service unreachable")
        response = client.get("/ready")
    assert response.status_code == 503
    body = response.get_json()
    assert body["status"] == "not_ready"
    assert body["dependencies"]["user-service"] == "unreachable"


def test_root_lists_expected_endpoints(client):
    response = client.get("/")
    assert response.status_code == 200
    body = response.get_json()
    assert body["service"] == "api-gateway"
    for expected in ("/health", "/ready", "/api/users"):
        assert expected in body["endpoints"]
