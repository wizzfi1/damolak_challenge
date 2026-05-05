import os
import logging
import platform
import socket
from datetime import datetime
from flask import Flask, jsonify

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(name)s %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

APP_VERSION = os.environ.get("APP_VERSION", "1.0.0")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "production")


@app.route("/")
def index():
    logger.info("Root endpoint called")
    return jsonify({
        "service": "damolak-devops-app",
        "version": APP_VERSION,
        "environment": ENVIRONMENT,
        "status": "running",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "host": socket.gethostname(),
        "python": platform.python_version()
    })


@app.route("/health")
def health():
    logger.info("Health check called")
    return jsonify({"status": "healthy", "timestamp": datetime.utcnow().isoformat() + "Z"}), 200


@app.route("/ready")
def ready():
    logger.info("Readiness check called")
    return jsonify({"status": "ready"}), 200


@app.route("/metrics")
def metrics():
    logger.info("Metrics endpoint called")
    return jsonify({
        "uptime": "ok",
        "version": APP_VERSION,
        "environment": ENVIRONMENT
    }), 200


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    logger.info(f"Starting app on port {port}")
    app.run(host="0.0.0.0", port=port)
