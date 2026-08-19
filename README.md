# Go Container CI Pipeline

A lightweight Go service used to demonstrate hardened container builds,
GitHub Actions continuous integration, immutable GHCR image publishing,
pull-after-push smoke testing, and security-conscious local runtime manifests.

## What this repository demonstrates

- Dockerized Go application
- Docker Compose local runtime
- GitHub Actions CI that builds, publishes, pulls, and smoke-tests the container image
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
| GitHub Actions CI and GHCR image publishing | Implemented | [.github/workflows/ci.yml](.github/workflows/ci.yml) |
| Kubernetes deployment with four replicas | Implemented | [k8s/go-version-app-deployment.yaml](k8s/go-version-app-deployment.yaml), [k8s/go-version-app-service.yaml](k8s/go-version-app-service.yaml) |
| Infrastructure as Code | Baseline implemented | [main.tf](main.tf) |
| HTTPS/TLS | Local self-signed configuration implemented | [src/go-version-app.go](src/go-version-app.go), [docker-compose.yml](docker-compose.yml) |
| Security hardening | Baseline implemented | Docker, Kubernetes, TLS, and CI sections below |

## Implementation details

### Docker and Compose

- Multi-stage image build in [Dockerfile](Dockerfile)
- Static binary build with CGO disabled
- Minimal runtime image using scratch
- Non-root runtime user
- Compose service definition in [docker-compose.yml](docker-compose.yml)

### GitHub Actions CI

The GitHub Actions workflow runs on changes to `main`. It performs continuous
integration and artifact publication; it does not deploy the application to
Kubernetes or ECS.

The workflow:

- build the Docker image
- authenticates to GitHub Container Registry with the repository-scoped
  `GITHUB_TOKEN`
- publishes an immutable image tag derived from the full Git commit SHA
- removes the locally built image and pulls the published image from GHCR
- runs the pulled artifact in a container
- uses `curl` to verify both the HTTP response and injected short commit SHA

For commit `634f20ba6cb53bc38016f8ad8bbf66d04f0dd7d5`, the published
artifact is:

```text
ghcr.io/brogrammer89/go-container-delivery-pipeline:634f20ba6cb53bc38016f8ad8bbf66d04f0dd7d5
```

The image is stored remotely as a GitHub package. Because the workflow uses a
self-hosted runner, the pull-after-push copy also appears in Docker Desktop on
the runner machine. It is a registry artifact, not a GitHub Actions
`upload-artifact` file.

Workflow definition: [.github/workflows/ci.yml](.github/workflows/ci.yml)

### Kubernetes deployment

Files:
- [k8s/go-version-app-deployment.yaml](k8s/go-version-app-deployment.yaml)
- [k8s/go-version-app-service.yaml](k8s/go-version-app-service.yaml)

Implemented:
- 4 replicas
- the exact GHCR image produced and smoke-tested by the CI workflow
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
- The Terraform configuration is a separate ECS infrastructure example. The
  GitHub Actions workflow does not push to its ECR repository or deploy ECS.
- `image_tag` must be supplied as an immutable ECR tag; `latest` is rejected.
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
- codified build and runtime definitions reduce manual drift
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

The CI workflow validates:

- Docker image build
- GHCR image publishing with a full commit SHA tag
- removal and re-pull of the published registry artifact
- HTTP smoke test of the running artifact

The workflow does not perform continuous deployment. Kubernetes and Terraform
remain separately invoked runtime examples.

Kubernetes validation details:

- The Kubernetes deployment includes resource requests and limits in [k8s/go-version-app-deployment.yaml](k8s/go-version-app-deployment.yaml)
- A temporary curl pod was run inside Minikube to verify the Service directly, without port-forwarding
