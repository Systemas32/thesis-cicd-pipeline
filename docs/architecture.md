# System Architecture

## Overview

This project implements an automated CI/CD pipeline for Kubernetes with
integrated health checking, automated testing, and a rollback mechanism. Its
core contribution is the automatic rollback triggered by health-check or
smoke-test failures, which operates without human intervention.

The system is organised into four layers. Build and image distribution happen
remotely; deployment, health checking and rollback run locally against a
Minikube cluster.

## Four-layer architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 1 - Source code and integration                            │
│   Developer workstation -> GitHub repository -> GitHub Actions    │
│   workflow: build images, run tests, push images to Docker Hub    │
└────────────────────────────────┬──────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│ Layer 2 - Containerization and distribution                      │
│   Docker images distributed through Docker Hub (central registry)│
└────────────────────────────────┬──────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│ Layer 3 - Kubernetes execution                                   │
│   Local Minikube cluster · Helm as package and release manager   │
│   Microservices: api-gateway, user-service                       │
└──────────────┬───────────────────────────────────▲────────────────┘
               │                                    ┊
               ▼                                    ┊ helm rollback
┌──────────────────────────────────────────────────┴────────────────┐
│ Layer 4 - Health checking and automated rollback                  │
│   External orchestrator: health-check.sh + rollback.sh            │
│   Monitors deployments via the Kubernetes API and Robot Framework │
│   smoke tests; triggers rollback automatically on failure         │
└─────────────────────────────────────────────────────────────────────┘
```

The dashed arrow is the rollback feedback path: when Layer 4 detects a failure,
it instructs Helm in Layer 3 to roll the release back to the previous good
revision. This feedback path is the thesis's core contribution.

### Layer 1 - Source code and integration

The developer workstation holds the source code, which is pushed to the GitHub
repository. The GitHub Actions workflow (`.github/workflows/ci-cd.yaml`) builds
the microservice images, syntax-checks the Robot Framework smoke suite, and
pushes the images to Docker Hub. It deliberately does **not** deploy: deployment
and rollback run locally, matching the thesis's cost-effective framing. The
smoke tests themselves are executed for real later, by the local scenario
harness against the Minikube cluster.

### Layer 2 - Containerization and distribution

The microservices are packaged as Docker images. Docker Hub (the `systemas32`
namespace) acts as the central registry that distributes images between the
integration layer and the execution layer.

### Layer 3 - Kubernetes execution

A local Minikube cluster runs the two Flask microservices. Helm is the package
and release manager: each deployment is a Helm release revision, which is what
makes a one-command rollback possible.

### Layer 4 - Health checking and automated rollback

An external orchestrator monitors each deployment:

- `scripts/health-check.sh` polls the Kubernetes API and verifies that the new
  revision has fully rolled out.
- The Robot Framework smoke tests exercise the deployed services through the
  api-gateway.
- `scripts/rollback.sh` runs `helm rollback` to the previous revision when
  either check fails, then re-verifies health.

`scripts/run-scenario.sh` ties these together for a single experimental run.

## Microservices

1. **API Gateway** (port 5000)
   - Entry point for all API requests
   - Proxies requests to the user-service
   - Exposes `/health` (liveness) and `/ready` (readiness) endpoints

2. **User Service** (port 5001)
   - Handles basic user management operations (list and create)
   - In-memory storage for demo purposes
   - Exposes `/health` and `/ready` endpoints

## Health checking

- **Liveness probe**: checks that the service process is running (`/health`).
- **Readiness probe**: checks that the service is ready for traffic (`/ready`).
- **External health check**: `health-check.sh` confirms that a Helm upgrade has
  fully rolled out. It compares `updatedReplicas`, `readyReplicas`,
  `availableReplicas` and `status.replicas` against the desired replica count,
  so a stuck rolling update - where an old healthy pod keeps `readyReplicas` at
  the desired value while a broken new pod crash-loops - is correctly detected
  as a failure.

## Rollback mechanism

Automated rollback is triggered when:

1. The post-deployment health check fails (the rollout does not complete).
2. The Robot Framework smoke tests fail.

On either trigger, `rollback.sh` runs `helm rollback` to the previous release
revision and then runs a post-rollback health check to confirm recovery.

## Scenario images

Four `api-gateway` images exercise the pipeline. Only `api-gateway` carries
scenario tags; `user-service` always uses `latest`.

| Scenario       | Tag            | Behaviour                                                        | Tests                          |
|----------------|----------------|------------------------------------------------------------------|--------------------------------|
| Successful     | `latest`       | Normal, healthy behaviour                                        | No false-positive rollback     |
| Broken image   | `broken-image` | Container exits with code 1 on startup (CrashLoopBackOff)        | Health-check failure detection |
| Broken smoke   | `broken-smoke` | Starts healthy, `/health` returns 200, but `/api/users` returns 500 | Smoke-test failure detection |
| Slow start     | `slow-start`   | Sleeps 90s before binding the port, exceeding the probe timeout  | Timeout-based failure detection|

The scenario Dockerfiles live in `microservices/api-gateway/scenarios/`.

## Event logging format

Every significant pipeline event is appended to a per-run log file under
`logs/` as a single JSON object (JSONL). Each line contains at least:

- `timestamp` - ISO 8601 UTC timestamp with millisecond precision
- `event` - the event name

plus event-specific context fields (release name, scenario, revision numbers,
replica counts, etc.).

Automated runs (`run-<scenario>-<iteration>-<epoch>.jsonl`) emit, in order:

```
deployment_start
health_check_started
health_check_attempt        (repeated per retry)
deployment_ready            (per deployment)
health_check_passed | health_check_failed
smoke_tests_started
smoke_tests_passed | smoke_test_failed
rollback_triggered
rollback_executing
rollback_completed | rollback_failed
post_rollback_health_check_passed
scenario_completed          (outcome: success | rolled_back | rollback_failed)
```

Manual baseline runs (`manual-<scenario>-<iteration>-<epoch>.jsonl`) emit:

```
manual_start
manual_image_ready
manual_deployment_done
manual_health_verified | manual_failure_detected
manual_rollback_start
manual_rollback_done
manual_completed            (outcome: success | rolled_back)
```

`scripts/aggregate-results.py` parses these logs to compute time-to-detect,
MTTR and correctness statistics for Chapter 4.

## Technology stack

- **Container runtime**: Docker
- **Orchestration**: Kubernetes (Minikube)
- **Package management**: Helm
- **CI (build/test/push)**: GitHub Actions
- **Testing**: Robot Framework (smoke), pytest (unit)
- **Language**: Python (Flask)
- **Local orchestration**: Bash scripts (Git Bash on Windows)
