# Thesis CI/CD Pipeline

[![CI/CD Pipeline](https://github.com/Systemas32/thesis-cicd-pipeline/actions/workflows/ci-cd.yaml/badge.svg)](https://github.com/Systemas32/thesis-cicd-pipeline/actions/workflows/ci-cd.yaml)

## Design and Implementation of an Automated CI/CD Pipeline for Kubernetes with Integrated Health Checking, Testing, and Rollback Mechanisms

**BSc Computer Science Thesis**  
**University of East London**

- **Student**: Iasonas Lykakis (UEL No: 2678449)
- **Supervisor**: Dr. Nikolaos Lyras

## Overview

This project implements an automated CI/CD pipeline for Kubernetes whose core
contribution is an **automated rollback mechanism** triggered by health-check
or smoke-test failures, operating without human intervention.

The pipeline covers:

- Automated image building, testing and registry push (GitHub Actions)
- Kubernetes deployment via Helm
- Health checking (liveness and readiness probes plus an external monitor)
- Automated smoke testing (Robot Framework)
- **Automated rollback on failure** (novel contribution)

Build and push run on GitHub Actions; deployment, health checking and rollback
run locally against a Minikube cluster, matching the thesis's cost-effective,
runs-on-a-personal-computer framing.

## Project Structure

```
thesis-cicd-pipeline/
├── .github/workflows/        # GitHub Actions workflow (build, test, push)
├── microservices/
│   ├── api-gateway/          # API Gateway service
│   │   └── scenarios/        # Dockerfiles for the failure scenarios
│   └── user-service/         # User management service
├── helm/thesis-app/          # Helm chart for Kubernetes deployment
├── tests/
│   ├── smoke/                # Robot Framework smoke tests
│   └── unit/                 # Pytest unit tests (per-service)
├── scripts/                  # Health check, rollback, experiment harnesses
│   └── lib/                  # Shared structured-logging helper
└── docs/                     # Documentation
```

## Quick Start

### Prerequisites

Available on `PATH` (Bash scripts run via Git Bash on Windows):

- Docker Desktop
- Minikube and `kubectl`
- Helm
- `curl` and `jq`
- Python 3.11+ (for Robot Framework and the aggregation script)

### Deploy locally

```
minikube start
helm install thesis-app ./helm/thesis-app
```

The Helm chart pulls the `systemas32/api-gateway` and `systemas32/user-service`
images from Docker Hub.

## Running an experiment

The scenario harness runs one experimental scenario end to end: it deploys the
relevant image, monitors the health check, runs the smoke tests, triggers a
rollback when something fails, and records every timestamp to a JSONL log under
`logs/`.

Install the test dependencies once:

```
pip install -r tests/smoke/requirements.txt
```

Then run a scenario (Minikube must be running):

```
bash scripts/run-scenario.sh <scenario> <iteration>
```

For example:

```
bash scripts/run-scenario.sh broken-image 1
```

| Scenario       | api-gateway tag | Expected outcome                                    |
|----------------|-----------------|-----------------------------------------------------|
| `successful`   | `latest`        | Deployment succeeds, smoke tests pass, no rollback  |
| `broken-image` | `broken-image`  | Health check fails, rollback triggered              |
| `broken-smoke` | `broken-smoke`  | Health check passes, smoke tests fail, rollback     |
| `slow-start`   | `slow-start`    | Health check fails on timeout, rollback triggered   |

Each run writes `logs/run-<scenario>-<iteration>-<epoch>.jsonl`.

## Running the manual baseline

For the Chapter 4 comparison, the manual baseline harness records human-paced
timestamps for an equivalent manual deploy-and-rollback cycle. It automates
nothing: it prompts at each stage and timestamps the events.

```
bash scripts/run-manual-baseline.sh <scenario> <iteration>
```

Each run writes `logs/manual-<scenario>-<iteration>-<epoch>.jsonl` in the same
format as the automated runs.

## Aggregating results

Once the experimental runs are complete, aggregate the raw JSONL logs into
summary statistics (time-to-detect, MTTR, correctness counts):

```
python scripts/aggregate-results.py logs/ > results-summary.json
```

This writes the JSON summary to `results-summary.json` and a Markdown summary
table to `results-summary.md`.

## Architecture

See [docs/architecture.md](docs/architecture.md) for the four-layer
architecture, the scenario images and the event-logging format.

## License

MIT License - see [LICENSE](LICENSE) for details.
