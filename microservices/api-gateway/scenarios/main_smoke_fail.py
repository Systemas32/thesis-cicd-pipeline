"""
API Gateway Microservice - broken-smoke scenario variant.

Identical to app/main.py except that the /api/users endpoint always returns
HTTP 500. The /health and /ready endpoints still behave normally, so the
deployment becomes ready and the Kubernetes health check passes, but the
Robot Framework smoke tests fail and the harness triggers a rollback.
"""
from flask import Flask, jsonify, request
import os
import requests
from datetime import datetime

app = Flask(__name__)

# Configuration
USER_SERVICE_URL = os.getenv('USER_SERVICE_URL', 'http://user-service:5001')

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint for Kubernetes probes."""
    return jsonify({
        'status': 'healthy',
        'service': 'api-gateway',
        'timestamp': datetime.utcnow().isoformat()
    }), 200

@app.route('/ready', methods=['GET'])
def readiness_check():
    """Readiness check - verifies dependencies are available."""
    try:
        # Check if user-service is reachable
        response = requests.get(f'{USER_SERVICE_URL}/health', timeout=5)
        if response.status_code == 200:
            return jsonify({
                'status': 'ready',
                'service': 'api-gateway',
                'dependencies': {'user-service': 'healthy'}
            }), 200
    except requests.exceptions.RequestException:
        pass

    return jsonify({
        'status': 'not_ready',
        'service': 'api-gateway',
        'dependencies': {'user-service': 'unreachable'}
    }), 503

@app.route('/', methods=['GET'])
def root():
    """Root endpoint."""
    return jsonify({
        'service': 'api-gateway',
        'version': os.getenv('APP_VERSION', '1.0.0'),
        'endpoints': ['/health', '/ready', '/api/users']
    }), 200

@app.route('/api/users', methods=['GET'])
def get_users():
    """broken-smoke scenario: always fails."""
    return jsonify({'error': 'Internal server error'}), 500

@app.route('/api/users', methods=['POST'])
def create_user():
    """broken-smoke scenario: always fails."""
    return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
