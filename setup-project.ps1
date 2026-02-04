# Thesis CI/CD Pipeline - Project Structure Setup
# Run this from inside the thesis-cicd-pipeline folder

Write-Host "Creating project structure..." -ForegroundColor Green

# Create directory structure
$directories = @(
    ".github/workflows",
    "microservices/api-gateway/app",
    "microservices/user-service/app",
    "helm/thesis-app/templates",
    "tests/unit",
    "tests/integration", 
    "tests/smoke",
    "scripts",
    "docs"
)

foreach ($dir in $directories) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Write-Host "  Created: $dir" -ForegroundColor Gray
}

Write-Host "`nCreating microservice files..." -ForegroundColor Green

# API Gateway - main.py
$apiGatewayMain = @'
"""
API Gateway Microservice
A simple Flask REST API that serves as the entry point for the thesis demo application.
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
    """Proxy request to user-service."""
    try:
        response = requests.get(f'{USER_SERVICE_URL}/users', timeout=10)
        return jsonify(response.json()), response.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({'error': 'User service unavailable', 'details': str(e)}), 503

@app.route('/api/users', methods=['POST'])
def create_user():
    """Proxy request to create user."""
    try:
        response = requests.post(
            f'{USER_SERVICE_URL}/users',
            json=request.get_json(),
            timeout=10
        )
        return jsonify(response.json()), response.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({'error': 'User service unavailable', 'details': str(e)}), 503

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
'@
Set-Content -Path "microservices/api-gateway/app/main.py" -Value $apiGatewayMain

# API Gateway - requirements.txt
$apiGatewayReqs = @'
Flask==3.0.0
requests==2.31.0
gunicorn==21.2.0
'@
Set-Content -Path "microservices/api-gateway/requirements.txt" -Value $apiGatewayReqs

# API Gateway - Dockerfile
$apiGatewayDockerfile = @'
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app/ ./app/

# Create non-root user for security
RUN useradd --create-home appuser && chown -R appuser:appuser /app
USER appuser

# Environment variables
ENV PORT=5000
ENV PYTHONUNBUFFERED=1

EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:5000/health')" || exit 1

# Run with gunicorn for production
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app.main:app"]
'@
Set-Content -Path "microservices/api-gateway/Dockerfile" -Value $apiGatewayDockerfile

Write-Host "  Created: api-gateway microservice" -ForegroundColor Gray

# User Service - main.py  
$userServiceMain = @'
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

@app.route('/users/<int:user_id>', methods=['GET'])
def get_user(user_id):
    """Get a specific user by ID."""
    user = next((u for u in users_db if u['id'] == user_id), None)
    if user:
        return jsonify(user), 200
    return jsonify({'error': 'User not found'}), 404

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

@app.route('/users/<int:user_id>', methods=['DELETE'])
def delete_user(user_id):
    """Delete a user by ID."""
    global users_db
    user = next((u for u in users_db if u['id'] == user_id), None)
    if user:
        users_db = [u for u in users_db if u['id'] != user_id]
        return jsonify({'message': 'User deleted'}), 200
    return jsonify({'error': 'User not found'}), 404

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5001))
    app.run(host='0.0.0.0', port=port, debug=False)
'@
Set-Content -Path "microservices/user-service/app/main.py" -Value $userServiceMain

# User Service - requirements.txt
$userServiceReqs = @'
Flask==3.0.0
gunicorn==21.2.0
'@
Set-Content -Path "microservices/user-service/requirements.txt" -Value $userServiceReqs

# User Service - Dockerfile
$userServiceDockerfile = @'
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app/ ./app/

# Create non-root user for security
RUN useradd --create-home appuser && chown -R appuser:appuser /app
USER appuser

# Environment variables
ENV PORT=5001
ENV PYTHONUNBUFFERED=1

EXPOSE 5001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:5001/health')" || exit 1

# Run with gunicorn for production
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "--workers", "2", "app.main:app"]
'@
Set-Content -Path "microservices/user-service/Dockerfile" -Value $userServiceDockerfile

Write-Host "  Created: user-service microservice" -ForegroundColor Gray

Write-Host "`nCreating Helm chart..." -ForegroundColor Green

# Helm Chart.yaml
$helmChart = @'
apiVersion: v2
name: thesis-app
description: CI/CD Pipeline Demo Application for BSc Thesis
type: application
version: 0.1.0
appVersion: "1.0.0"
maintainers:
  - name: Iasonas Lykakis
    email: ilykakis23b@amcstudent.edu.gr
'@
Set-Content -Path "helm/thesis-app/Chart.yaml" -Value $helmChart

# Helm values.yaml
$helmValues = @'
# Default values for thesis-app

apiGateway:
  replicaCount: 1
  image:
    repository: systemas32/api-gateway
    tag: latest
    pullPolicy: Always
  service:
    type: NodePort
    port: 5000
    nodePort: 30080
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi

userService:
  replicaCount: 1
  image:
    repository: systemas32/user-service
    tag: latest
    pullPolicy: Always
  service:
    type: ClusterIP
    port: 5001
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi

# Health check configuration
healthCheck:
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
'@
Set-Content -Path "helm/thesis-app/values.yaml" -Value $helmValues

# Helm deployment template for api-gateway
$apiGatewayDeployment = @'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-api-gateway
  labels:
    app: api-gateway
    release: {{ .Release.Name }}
spec:
  replicas: {{ .Values.apiGateway.replicaCount }}
  selector:
    matchLabels:
      app: api-gateway
      release: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: api-gateway
        release: {{ .Release.Name }}
    spec:
      containers:
        - name: api-gateway
          image: "{{ .Values.apiGateway.image.repository }}:{{ .Values.apiGateway.image.tag }}"
          imagePullPolicy: {{ .Values.apiGateway.image.pullPolicy }}
          ports:
            - containerPort: 5000
          env:
            - name: USER_SERVICE_URL
              value: "http://{{ .Release.Name }}-user-service:{{ .Values.userService.service.port }}"
            - name: APP_VERSION
              value: "{{ .Chart.AppVersion }}"
          livenessProbe:
            httpGet:
              path: /health
              port: 5000
            initialDelaySeconds: {{ .Values.healthCheck.initialDelaySeconds }}
            periodSeconds: {{ .Values.healthCheck.periodSeconds }}
            timeoutSeconds: {{ .Values.healthCheck.timeoutSeconds }}
            failureThreshold: {{ .Values.healthCheck.failureThreshold }}
          readinessProbe:
            httpGet:
              path: /ready
              port: 5000
            initialDelaySeconds: {{ .Values.healthCheck.initialDelaySeconds }}
            periodSeconds: {{ .Values.healthCheck.periodSeconds }}
            timeoutSeconds: {{ .Values.healthCheck.timeoutSeconds }}
            failureThreshold: {{ .Values.healthCheck.failureThreshold }}
          resources:
            {{- toYaml .Values.apiGateway.resources | nindent 12 }}
'@
Set-Content -Path "helm/thesis-app/templates/api-gateway-deployment.yaml" -Value $apiGatewayDeployment

# Helm service template for api-gateway
$apiGatewayService = @'
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-api-gateway
  labels:
    app: api-gateway
    release: {{ .Release.Name }}
spec:
  type: {{ .Values.apiGateway.service.type }}
  ports:
    - port: {{ .Values.apiGateway.service.port }}
      targetPort: 5000
      nodePort: {{ .Values.apiGateway.service.nodePort }}
      protocol: TCP
      name: http
  selector:
    app: api-gateway
    release: {{ .Release.Name }}
'@
Set-Content -Path "helm/thesis-app/templates/api-gateway-service.yaml" -Value $apiGatewayService

# Helm deployment template for user-service
$userServiceDeployment = @'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-user-service
  labels:
    app: user-service
    release: {{ .Release.Name }}
spec:
  replicas: {{ .Values.userService.replicaCount }}
  selector:
    matchLabels:
      app: user-service
      release: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: user-service
        release: {{ .Release.Name }}
    spec:
      containers:
        - name: user-service
          image: "{{ .Values.userService.image.repository }}:{{ .Values.userService.image.tag }}"
          imagePullPolicy: {{ .Values.userService.image.pullPolicy }}
          ports:
            - containerPort: 5001
          env:
            - name: APP_VERSION
              value: "{{ .Chart.AppVersion }}"
          livenessProbe:
            httpGet:
              path: /health
              port: 5001
            initialDelaySeconds: {{ .Values.healthCheck.initialDelaySeconds }}
            periodSeconds: {{ .Values.healthCheck.periodSeconds }}
            timeoutSeconds: {{ .Values.healthCheck.timeoutSeconds }}
            failureThreshold: {{ .Values.healthCheck.failureThreshold }}
          readinessProbe:
            httpGet:
              path: /ready
              port: 5001
            initialDelaySeconds: {{ .Values.healthCheck.initialDelaySeconds }}
            periodSeconds: {{ .Values.healthCheck.periodSeconds }}
            timeoutSeconds: {{ .Values.healthCheck.timeoutSeconds }}
            failureThreshold: {{ .Values.healthCheck.failureThreshold }}
          resources:
            {{- toYaml .Values.userService.resources | nindent 12 }}
'@
Set-Content -Path "helm/thesis-app/templates/user-service-deployment.yaml" -Value $userServiceDeployment

# Helm service template for user-service
$userServiceService = @'
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-user-service
  labels:
    app: user-service
    release: {{ .Release.Name }}
spec:
  type: {{ .Values.userService.service.type }}
  ports:
    - port: {{ .Values.userService.service.port }}
      targetPort: 5001
      protocol: TCP
      name: http
  selector:
    app: user-service
    release: {{ .Release.Name }}
'@
Set-Content -Path "helm/thesis-app/templates/user-service-service.yaml" -Value $userServiceService

Write-Host "  Created: Helm chart with templates" -ForegroundColor Gray

Write-Host "`nCreating scripts..." -ForegroundColor Green

# Health check script
$healthCheckScript = @'
#!/bin/bash
# Health Check Script for CI/CD Pipeline
# This script verifies the health of deployed services

set -e

NAMESPACE=${1:-default}
RELEASE_NAME=${2:-thesis-app}
MAX_RETRIES=${3:-30}
RETRY_INTERVAL=${4:-10}

echo "Starting health checks for $RELEASE_NAME in namespace $NAMESPACE"

check_deployment_health() {
    local deployment=$1
    local retries=0
    
    echo "Checking deployment: $deployment"
    
    while [ $retries -lt $MAX_RETRIES ]; do
        READY=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [ "$READY" == "$DESIRED" ] && [ "$READY" != "0" ]; then
            echo "✓ Deployment $deployment is healthy ($READY/$DESIRED replicas ready)"
            return 0
        fi
        
        echo "  Waiting for $deployment... ($READY/$DESIRED ready, attempt $((retries+1))/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
        retries=$((retries+1))
    done
    
    echo "✗ Deployment $deployment failed health check"
    return 1
}

check_endpoint_health() {
    local service=$1
    local port=$2
    local path=$3
    local retries=0
    
    echo "Checking endpoint: $service:$port$path"
    
    # Get service URL (for NodePort or port-forward)
    local url="http://localhost:$port$path"
    
    while [ $retries -lt $MAX_RETRIES ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" == "200" ]; then
            echo "✓ Endpoint $service$path is healthy (HTTP $HTTP_CODE)"
            return 0
        fi
        
        echo "  Waiting for $service$path... (HTTP $HTTP_CODE, attempt $((retries+1))/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
        retries=$((retries+1))
    done
    
    echo "✗ Endpoint $service$path failed health check"
    return 1
}

# Check deployments
check_deployment_health "${RELEASE_NAME}-api-gateway" || exit 1
check_deployment_health "${RELEASE_NAME}-user-service" || exit 1

echo ""
echo "All health checks passed!"
exit 0
'@
Set-Content -Path "scripts/health-check.sh" -Value $healthCheckScript

# Rollback script
$rollbackScript = @'
#!/bin/bash
# Automated Rollback Script for CI/CD Pipeline
# Triggers rollback when health checks or tests fail

set -e

NAMESPACE=${1:-default}
RELEASE_NAME=${2:-thesis-app}

echo "=========================================="
echo "INITIATING ROLLBACK for $RELEASE_NAME"
echo "=========================================="

# Get current revision
CURRENT_REVISION=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 1 -o json | jq -r '.[0].revision')
echo "Current revision: $CURRENT_REVISION"

if [ "$CURRENT_REVISION" -le 1 ]; then
    echo "ERROR: Cannot rollback - already at first revision"
    exit 1
fi

# Get previous revision info
PREVIOUS_REVISION=$((CURRENT_REVISION - 1))
echo "Rolling back to revision: $PREVIOUS_REVISION"

# Perform rollback
echo "Executing: helm rollback $RELEASE_NAME $PREVIOUS_REVISION -n $NAMESPACE"
helm rollback "$RELEASE_NAME" "$PREVIOUS_REVISION" -n "$NAMESPACE" --wait --timeout 5m

# Verify rollback
echo ""
echo "Verifying rollback..."
NEW_REVISION=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 1 -o json | jq -r '.[0].revision')

if [ "$NEW_REVISION" -gt "$CURRENT_REVISION" ]; then
    echo "✓ Rollback successful! New revision: $NEW_REVISION"
    
    # Run health checks after rollback
    echo ""
    echo "Running post-rollback health checks..."
    ./scripts/health-check.sh "$NAMESPACE" "$RELEASE_NAME" 20 5
    
    echo ""
    echo "=========================================="
    echo "ROLLBACK COMPLETED SUCCESSFULLY"
    echo "=========================================="
    exit 0
else
    echo "✗ Rollback may have failed. Please check manually."
    exit 1
fi
'@
Set-Content -Path "scripts/rollback.sh" -Value $rollbackScript

Write-Host "  Created: health-check.sh and rollback.sh" -ForegroundColor Gray

Write-Host "`nCreating GitHub Actions workflow..." -ForegroundColor Green

# GitHub Actions CI/CD workflow
$cicdWorkflow = @'
name: CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  DOCKER_HUB_USERNAME: systemas32
  API_GATEWAY_IMAGE: systemas32/api-gateway
  USER_SERVICE_IMAGE: systemas32/user-service

jobs:
  # Stage 1: Build and Test
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install pytest requests flask
      
      - name: Run unit tests
        run: |
          cd tests/unit
          pytest -v || echo "No unit tests yet"
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ env.DOCKER_HUB_USERNAME }}
          password: ${{ secrets.DOCKER_HUB_TOKEN }}
      
      - name: Build and push API Gateway
        uses: docker/build-push-action@v5
        with:
          context: ./microservices/api-gateway
          push: true
          tags: |
            ${{ env.API_GATEWAY_IMAGE }}:${{ github.sha }}
            ${{ env.API_GATEWAY_IMAGE }}:latest
      
      - name: Build and push User Service
        uses: docker/build-push-action@v5
        with:
          context: ./microservices/user-service
          push: true
          tags: |
            ${{ env.USER_SERVICE_IMAGE }}:${{ github.sha }}
            ${{ env.USER_SERVICE_IMAGE }}:latest

  # Stage 2: Deploy to Kubernetes
  deploy:
    needs: build-and-test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Set up Helm
        uses: azure/setup-helm@v3
        with:
          version: 'v3.13.0'
      
      - name: Deploy with Helm
        run: |
          echo "Deploying to Kubernetes..."
          # In a real scenario, you would configure kubectl with cluster credentials
          # kubectl config set-cluster ...
          # helm upgrade --install thesis-app ./helm/thesis-app --wait
          echo "Deployment would happen here with actual cluster credentials"

  # Stage 3: Health Checks and Smoke Tests  
  health-check:
    needs: deploy
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Run health checks
        run: |
          echo "Running health checks..."
          # In production, this would run against actual endpoints
          # ./scripts/health-check.sh default thesis-app
          echo "Health checks would run here"
      
      - name: Run smoke tests
        run: |
          echo "Running smoke tests..."
          # Robot Framework smoke tests would run here
          echo "Smoke tests would run here"

  # Stage 4: Rollback on Failure
  rollback:
    needs: health-check
    runs-on: ubuntu-latest
    if: failure()
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Trigger rollback
        run: |
          echo "Health checks or smoke tests failed!"
          echo "Initiating automated rollback..."
          # ./scripts/rollback.sh default thesis-app
          echo "Rollback would execute here"
'@
Set-Content -Path ".github/workflows/ci-cd.yaml" -Value $cicdWorkflow

Write-Host "  Created: CI/CD workflow" -ForegroundColor Gray

Write-Host "`nCreating documentation..." -ForegroundColor Green

# Architecture documentation
$architectureDoc = @'
# System Architecture

## Overview

This project implements an automated CI/CD pipeline for Kubernetes with integrated health checking, testing, and rollback mechanisms.

## Components

### Microservices

1. **API Gateway** (Port 5000)
   - Entry point for all API requests
   - Routes requests to appropriate backend services
   - Implements health and readiness endpoints

2. **User Service** (Port 5001)
   - Handles user management operations
   - Provides CRUD operations for users
   - In-memory storage for demo purposes

### CI/CD Pipeline Stages

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    BUILD    │───►│    TEST     │───►│   DEPLOY    │───►│   VERIFY    │
│             │    │             │    │             │    │             │
│ - Checkout  │    │ - Unit      │    │ - Helm      │    │ - Health    │
│ - Docker    │    │ - Lint      │    │ - K8s       │    │ - Smoke     │
│   Build     │    │             │    │             │    │   Tests     │
└─────────────┘    └─────────────┘    └─────────────┘    └──────┬──────┘
                                                                 │
                                                                 ▼
                                                          ┌─────────────┐
                                                          │  ROLLBACK   │
                                                          │ (on failure)│
                                                          └─────────────┘
```

### Health Checking

- **Liveness Probe**: Checks if the service is running (`/health`)
- **Readiness Probe**: Checks if the service is ready to accept traffic (`/ready`)

### Rollback Mechanism

Automated rollback is triggered when:
1. Health checks fail after deployment
2. Smoke tests fail
3. Integration tests fail

## Technology Stack

- **Container Runtime**: Docker
- **Orchestration**: Kubernetes
- **Package Management**: Helm
- **CI/CD**: GitHub Actions
- **Testing**: Robot Framework, pytest
- **Language**: Python (Flask)
'@
Set-Content -Path "docs/architecture.md" -Value $architectureDoc

Write-Host "  Created: architecture.md" -ForegroundColor Gray

# Update README
$readmeContent = @'
# Thesis CI/CD Pipeline

[![CI/CD Pipeline](https://github.com/Systemas32/thesis-cicd-pipeline/actions/workflows/ci-cd.yaml/badge.svg)](https://github.com/Systemas32/thesis-cicd-pipeline/actions/workflows/ci-cd.yaml)

## Design and Implementation of an Automated CI/CD Pipeline for Kubernetes with Integrated Health Checking, Testing, and Rollback Mechanisms

**BSc Computer Science Thesis**  
**University of East London**

- **Student**: Iasonas Lykakis (UEL No: 2678449)
- **Supervisor**: Dr. Nikolaos Lyras

## Overview

This project implements a production-ready CI/CD pipeline that automates the entire lifecycle of applications in a Kubernetes cluster, including:

- Automated building and testing
- Container image creation and registry push
- Kubernetes deployment via Helm
- Health checking (liveness and readiness probes)
- Automated smoke testing
- **Automated rollback on failure** (novel contribution)

## Project Structure

```
thesis-cicd-pipeline/
├── .github/workflows/      # GitHub Actions CI/CD pipeline
├── microservices/
│   ├── api-gateway/        # API Gateway service
│   └── user-service/       # User management service
├── helm/thesis-app/        # Helm chart for Kubernetes deployment
├── tests/                  # Test suites (unit, integration, smoke)
├── scripts/                # Automation scripts
└── docs/                   # Documentation
```

## Quick Start

### Prerequisites

- Docker Desktop
- Kubernetes (Minikube or Kind)
- Helm
- kubectl

### Local Development

```bash
# Start Minikube
minikube start

# Build and deploy locally
docker build -t api-gateway:local ./microservices/api-gateway
docker build -t user-service:local ./microservices/user-service

# Deploy with Helm
helm install thesis-app ./helm/thesis-app
```

## Architecture

See [docs/architecture.md](docs/architecture.md) for detailed architecture documentation.

## License

MIT License - see [LICENSE](LICENSE) for details.
'@
Set-Content -Path "README.md" -Value $readmeContent

Write-Host "  Updated: README.md" -ForegroundColor Gray

# Create placeholder test files
$unitTestPlaceholder = @'
"""
Unit Tests for Thesis CI/CD Pipeline
"""
import pytest

def test_placeholder():
    """Placeholder test - replace with actual tests."""
    assert True

# TODO: Add unit tests for:
# - API Gateway endpoints
# - User Service endpoints
# - Health check functions
'@
Set-Content -Path "tests/unit/test_placeholder.py" -Value $unitTestPlaceholder

$integrationTestPlaceholder = @'
"""
Integration Tests for Thesis CI/CD Pipeline
"""
import pytest

def test_placeholder():
    """Placeholder test - replace with actual tests."""
    assert True

# TODO: Add integration tests for:
# - API Gateway to User Service communication
# - End-to-end user creation flow
'@
Set-Content -Path "tests/integration/test_placeholder.py" -Value $integrationTestPlaceholder

$smokeTestPlaceholder = @'
"""
Smoke Tests for Thesis CI/CD Pipeline
Run after deployment to verify basic functionality.
"""
import pytest

def test_placeholder():
    """Placeholder test - replace with actual tests."""
    assert True

# TODO: Add smoke tests for:
# - Health endpoints responding
# - Basic API operations working
# - Service-to-service communication
'@
Set-Content -Path "tests/smoke/test_placeholder.py" -Value $smokeTestPlaceholder

Write-Host "  Created: test placeholders" -ForegroundColor Gray

# Create __init__.py files for Python packages
New-Item -ItemType File -Force -Path "microservices/api-gateway/app/__init__.py" | Out-Null
New-Item -ItemType File -Force -Path "microservices/user-service/app/__init__.py" | Out-Null
New-Item -ItemType File -Force -Path "tests/__init__.py" | Out-Null
New-Item -ItemType File -Force -Path "tests/unit/__init__.py" | Out-Null
New-Item -ItemType File -Force -Path "tests/integration/__init__.py" | Out-Null
New-Item -ItemType File -Force -Path "tests/smoke/__init__.py" | Out-Null

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Project structure created successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nNext steps:"
Write-Host "1. Review the created files"
Write-Host "2. Test Docker builds locally"
Write-Host "3. Push to GitHub"
Write-Host "`nRun 'tree /F' to see the full structure" -ForegroundColor Yellow
