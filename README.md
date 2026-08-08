# go-version-app

A lightweight Go service that returns the `VERSION` environment variable, packaged for Docker, Docker Compose, Kubernetes, GitHub Actions, Terraform, and TLS-enabled local development.

## What this repository demonstrates

- Dockerized Go application
- Docker Compose local runtime
- GitHub Actions CI/CD that builds, publishes, and smoke-tests the container image
- Kubernetes deployment with four replicas and local access
- Terraform baseline for supporting infrastructure
- HTTPS/TLS support with self-signed certificates for local testing
- Documented security-hardening decisions

## Application behavior

The service listens on port 3000 (HTTP mode) or 8443 (HTTPS mode) and returns:

```text
We're up and running!! Rocking Version: <value>
```

Source file:
- [src/go-version-app.go](src/go-version-app.go)

## Prerequisites

Install the tools required for the parts of the project you want to use:

- Docker Desktop with Docker Compose
- `curl` for endpoint checks
- OpenSSL for local self-signed certificates
- `kubectl` and a local Kubernetes cluster such as Minikube for Kubernetes deployment
- Terraform for infrastructure validation and provisioning

## Quick start

### HTTP local run (no TLS)

Use this if you want plain HTTP behavior.

```bash
docker compose down
TLS_CERT_PATH= TLS_KEY_PATH= docker compose up --build -d
curl http://localhost:8080/
```

### HTTPS local run (self-signed TLS)

Current Compose is configured for TLS cert mount and HTTPS on 8443.

1. Generate local certs:

```bash
mkdir -p certs
openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
  -keyout certs/tls.key \
  -out certs/tls.crt \
  -subj "/CN=localhost"
```

2. Start and test:

```bash
docker compose up --build -d
curl -k https://localhost:8443
```

3. Stop:

```bash
docker compose down
```

## Project capabilities

| Capability | Status | Evidence |
|---|---|---|
| Dockerized application | Implemented | [Dockerfile](Dockerfile), [src/go-version-app.go](src/go-version-app.go) |
| Docker Compose runtime | Implemented | [docker-compose.yml](docker-compose.yml) |
| GitHub Actions CI/CD and image publishing | Implemented | [.github/workflows/ci.yml](.github/workflows/ci.yml) |
| Kubernetes deployment with four replicas | Implemented | [k8s/go-version-app-deployment.yaml](k8s/go-version-app-deployment.yaml), [k8s/go-version-app-service.yaml](k8s/go-version-app-service.yaml) |
| Infrastructure as Code | Baseline implemented | [main.tf](main.tf) |
| HTTPS/TLS | Local self-signed configuration implemented | [src/go-version-app.go](src/go-version-app.go), [docker-compose.yml](docker-compose.yml) |
| Security hardening | Baseline implemented | Docker, Kubernetes, TLS, and CI/CD sections below |

## Implementation details

### Docker and Compose

- Multi-stage image build in [Dockerfile](Dockerfile)
- Static binary build with CGO disabled
- Minimal runtime image using scratch
- Non-root runtime user
- Compose service definition in [docker-compose.yml](docker-compose.yml)

### GitHub Actions CI/CD

The GitHub Actions workflow runs on changes to `main` and performs the following steps:

- build the Docker image
- authenticate to a container registry
- publish an image tagged from the commit SHA
- run the application in a container
- use `curl` to verify the HTTP endpoint returns successfully

Workflow definition: [.github/workflows/ci.yml](.github/workflows/ci.yml)

### Kubernetes deployment

Files:
- [k8s/go-version-app-deployment.yaml](k8s/go-version-app-deployment.yaml)
- [k8s/go-version-app-service.yaml](k8s/go-version-app-service.yaml)

Implemented:
- 4 replicas
- resource requests and limits to provide basic CPU/memory guardrails
- NodePort service for local access without port-forward
- pod-level non-root security context

Apply:

```bash
kubectl apply -f k8s/go-version-app-deployment.yaml
kubectl apply -f k8s/go-version-app-service.yaml
kubectl get deploy,pods,svc -l app=go-version-app
```

Validation:

```bash
kubectl run curltest --rm -it --restart=Never --image=curlimages/curl -- \
  curl -fsS http://go-version-app-service:3000/
```

This internal curl test was used to confirm the Service returned the expected application response from inside Minikube without port-forwarding.

### Infrastructure as Code

Terraform baseline in [main.tf](main.tf) includes:

- VPC, subnet, internet gateway, route table, security group
- ECR repository
- IAM roles for ECS execution and task runtime
- CloudWatch log group
- ECS Fargate cluster/task/service

Scope note:
- This is intentionally minimal, sized for a proof-of-concept.
- Production hardening would include finalized remote state backend and more stable ingress.

### HTTPS/TLS

Implemented:
- app enables HTTPS when TLS_CERT_PATH and TLS_KEY_PATH are set
- Compose exposes 8443 and mounts certs from ./certs
- validated with curl -k over localhost:8443

## Security hardening

Security controls implemented:

- container hardening:
  - multi-stage build
  - scratch runtime
  - non-root runtime user in [Dockerfile](Dockerfile)
- Kubernetes hardening:
  - runAsNonRoot, runAsUser, runAsGroup in [k8s/go-version-app-deployment.yaml](k8s/go-version-app-deployment.yaml)
- transport hardening:
  - local HTTPS with self-signed cert flow in [src/go-version-app.go](src/go-version-app.go)
- delivery hardening baseline:
  - reproducible GitHub Actions build, publish, and smoke-test flow in [.github/workflows/ci.yml](.github/workflows/ci.yml)
- IaC discipline:
  - infrastructure defined as code in [main.tf](main.tf)

Security reasoning:

- non-root and minimal runtime reduce attack surface
- codified build/deploy paths reduce manual drift
- TLS path demonstrates transport-security readiness in local environments

Known limitations and next steps:

- self-signed certs are local-test only
- CI image publishing requires repository-level registry permissions
- production deployments should use managed certificates, stricter network boundaries, and image policy enforcement

## Validation summary

Validated locally:

- Docker build and container run
- Compose startup and endpoint response
- HTTPS local response using self-signed certificate
- Kubernetes deployment/service baseline behavior, including the internal curl-pod test without port-forwarding

The CI/CD workflow validates:

- Docker image build
- Container image publishing with a commit SHA tag
- HTTP smoke test of the running application

Kubernetes validation details:

- The Kubernetes deployment includes resource requests and limits in [k8s/go-version-app-deployment.yaml](k8s/go-version-app-deployment.yaml)
- A temporary curl pod was run inside Minikube to verify the Service directly, without port-forwarding
