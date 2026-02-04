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
