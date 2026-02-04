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
