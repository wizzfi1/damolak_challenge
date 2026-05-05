import pytest
from app import app as flask_app


@pytest.fixture
def app():
    flask_app.config["TESTING"] = True
    yield flask_app


@pytest.fixture
def client(app):
    return app.test_client()


def test_index_returns_200(client):
    response = client.get("/")
    assert response.status_code == 200


def test_index_json_fields(client):
    response = client.get("/")
    data = response.get_json()
    assert data["service"] == "damolak-devops-app"
    assert data["status"] == "running"
    assert "version" in data
    assert "timestamp" in data


def test_health_returns_200(client):
    response = client.get("/health")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "healthy"


def test_ready_returns_200(client):
    response = client.get("/ready")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "ready"


def test_metrics_returns_200(client):
    response = client.get("/metrics")
    assert response.status_code == 200
