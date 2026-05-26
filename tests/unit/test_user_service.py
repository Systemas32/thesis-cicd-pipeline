"""Unit tests for the user-service Flask service.

These tests exercise the in-process Flask app directly, with no
Kubernetes involvement.

Run from the repository root with the user-service on PYTHONPATH:
    PYTHONPATH=microservices/user-service pytest tests/unit/test_user_service.py
"""
import pytest

from app import main as user_service_main
from app.main import app as flask_app


@pytest.fixture
def client():
    flask_app.config["TESTING"] = True
    # Reset the module-level in-memory state before each test so the
    # tests are independent of execution order.
    user_service_main.users_db = [
        {"id": 1, "name": "Alice", "email": "alice@example.com"},
        {"id": 2, "name": "Bob", "email": "bob@example.com"},
    ]
    user_service_main.next_id = 3
    with flask_app.test_client() as test_client:
        yield test_client


def test_users_get_returns_seeded_users(client):
    response = client.get("/users")
    assert response.status_code == 200
    body = response.get_json()
    assert body["count"] == 2
    names = [u["name"] for u in body["users"]]
    assert "Alice" in names
    assert "Bob" in names


def test_create_user_missing_name_returns_400(client):
    response = client.post("/users", json={"email": "noname@example.com"})
    assert response.status_code == 400
    assert "error" in response.get_json()


def test_create_user_with_valid_body_returns_201_and_assigns_id(client):
    response = client.post(
        "/users",
        json={"name": "Charlie", "email": "charlie@example.com"},
    )
    assert response.status_code == 201
    body = response.get_json()
    assert body["name"] == "Charlie"
    assert body["email"] == "charlie@example.com"
    assert body["id"] == 3  # next_id was 3 after the fixture reset
