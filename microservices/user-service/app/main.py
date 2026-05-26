"""
User Service Microservice
Handles user management operations for the thesis demo application.
"""
from flask import Flask, jsonify, request
import os
from datetime import datetime

app = Flask(__name__)

# In-memory storage (for demo purposes)
users_db = [
    {'id': 1, 'name': 'Alice', 'email': 'alice@example.com'},
    {'id': 2, 'name': 'Bob', 'email': 'bob@example.com'}
]
next_id = 3

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint for Kubernetes probes."""
    return jsonify({
        'status': 'healthy',
        'service': 'user-service',
        'timestamp': datetime.utcnow().isoformat()
    }), 200

@app.route('/ready', methods=['GET'])
def readiness_check():
    """Readiness check endpoint."""
    return jsonify({
        'status': 'ready',
        'service': 'user-service',
        'database': 'in-memory'
    }), 200

@app.route('/', methods=['GET'])
def root():
    """Root endpoint."""
    return jsonify({
        'service': 'user-service',
        'version': os.getenv('APP_VERSION', '1.0.0'),
        'endpoints': ['/health', '/ready', '/users']
    }), 200

@app.route('/users', methods=['GET'])
def get_users():
    """Get all users."""
    return jsonify({
        'users': users_db,
        'count': len(users_db)
    }), 200

@app.route('/users', methods=['POST'])
def create_user():
    """Create a new user."""
    global next_id
    data = request.get_json()
    
    if not data or 'name' not in data or 'email' not in data:
        return jsonify({'error': 'Name and email are required'}), 400
    
    new_user = {
        'id': next_id,
        'name': data['name'],
        'email': data['email']
    }
    users_db.append(new_user)
    next_id += 1
    
    return jsonify(new_user), 201

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5001))
    app.run(host='0.0.0.0', port=port, debug=False)
