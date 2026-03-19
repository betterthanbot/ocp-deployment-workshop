# OCP Deployment Workshop: Helm Charts

A hands-on workshop for deploying applications to OpenShift using Helm charts.

## The story

You are a developer joining the ParksMap team. The application displays national parks on a map, backed by a REST API and MongoDB database. Your team has been deploying using the OpenShift web console, but it is time to move to infrastructure-as-code using Helm.

Over the next three hours, you will build a Helm chart from scratch, deploy it to multiple environments, and debug the kinds of failures that happen in real production deployments.

## Prerequisites

- Completed the OpenShift Basics class (k8s/OCP fundamentals)
- Completed the ParksMap clickops lab (deploying via the web console)
- DevSpaces workspace provisioned from this repository
- Access to your assigned namespaces (`userN-dev` and `userN-sit`)

## Getting started

1. Open your DevSpaces workspace.
2. Open a terminal and verify your tools:

```bash
helm version
oc version
oc whoami
```

3. Check your available namespaces:

```bash
oc projects
```

Write down your two namespace names. You will need them throughout the workshop.

## Workshop structure

| Section | Time | Description |
|---------|------|-------------|
| [Part 1: Helm Foundations](01-helm-foundations/) | ~90 min | Build a Helm chart from scratch by completing skeleton templates and creating missing files |
| [Part 2: Production Readiness](02-production-readiness/) | ~90 min | Debug and fix a pre-broken chart covering common deployment pitfalls |
| [Bonus: Docker Compose Migration](bonus-compose-migration/) | If time permits | Learn how to translate docker-compose.yaml into Helm charts |

Work through the sections in order. Each section has its own README with step-by-step instructions.

## The ParksMap application

The application consists of three components:

```
                        +------------------+
    Browser --HTTPS-->  |   parksmap       |  (Route: edge TLS)
                        |   (frontend)     |
                        +--------+---------+
                                 |  Service discovery via
                                 |  label: type=parksmap-backend
                                 v
                        +------------------+
                        |  nationalparks   |  (Route: edge TLS + redirect)
                        |   (backend)      |
                        +--------+---------+
                                 |  MONGODB_SERVER_HOST
                                 v
                        +------------------+
                        |    mongodb       |  (ClusterIP only)
                        |   (database)     |
                        +------------------+
```

The frontend discovers backends by querying the Kubernetes API for Services with the label `type: parksmap-backend`. This is why the `view` RoleBinding is required.

## Dev vs SIT environments

Throughout the workshop, you will deploy to two environments:

| Aspect | Dev | SIT |
|--------|-----|-----|
| Purpose | Rapid testing and iteration | Stable integration testing |
| Namespace | `userN-dev` | `userN-sit` |
| Image tags | `latest` (always pull newest) | Pinned version (e.g., `1.3.0`) |
| Replicas | 1 per component | 2 for frontend and backend |
| Resource limits | Relaxed | Strict |
| Map legend label | "National Parks (DEV)" | "National Parks (SIT)" |

This simulates a real development workflow: push to dev first, test, then promote to sit when confident.

## Solutions

If you get completely stuck, the `solutions/` folder contains the fully working chart with correct values files. Try to solve each exercise using the hints before looking at the solutions.

## Useful commands reference

```bash
# Helm commands
helm lint ./                                    # Validate chart syntax
helm template parksmap ./                       # Render templates locally
helm install parksmap ./ -n <namespace>         # Install a release
helm upgrade parksmap ./ -n <namespace>         # Upgrade a release
helm uninstall parksmap -n <namespace>          # Remove a release
helm list -n <namespace>                        # List releases

# OpenShift commands
oc get pods -n <namespace>                      # List pods
oc get svc -n <namespace>                       # List services
oc get routes -n <namespace>                    # List routes
oc get endpoints -n <namespace>                 # List service endpoints
oc get events -n <namespace> --sort-by='.lastTimestamp'  # Recent events
oc describe pod <pod-name> -n <namespace>       # Pod details and events
oc logs <pod-name> -n <namespace>               # Container logs
oc get secret <name> -n <namespace> -o yaml     # Inspect a secret
```
