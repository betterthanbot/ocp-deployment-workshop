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

The application consists of three components wired together through OpenShift Routes, Services, and Deployments:

```
  External traffic (browser)
  |
  |   HTTPS
  v
+--------------------------------------------------+
|  OpenShift Router (HAProxy)                      |
+----+------------------------+--------------------+
     |                        |
     | Route: parksmap        | Route: nationalparks
     | (edge TLS)             | (edge TLS + redirect)
     v                        v
+-----------+           +-----------+
| Service   |           | Service   |
| parksmap  |           | national- |
| :8080     |           | parks     |
|           |           | :8080     |
+-----+-----+           | label:    |
      |                 | type=     |
      |                 | parksmap- |
      |                 | backend   |
      |                 +-----+-----+
      v                       v
+-----------+           +-----------+         +-----------+
| Deploy    |  label    | Deploy    |         | Service   |
| parksmap  |  lookup   | national- |  DNS    | mongodb   |
| (frontend)|---------->| parks     |-------->| :27017    |
| Pod(s)    |           | (backend) |         | ClusterIP |
+-----------+           | Pod(s)    |         +-----+-----+
                        +-----------+               |
                                                    v
                                              +-----------+
                                              | Deploy    |
                                              | mongodb   |
                                              | (database)|
                                              | Pod(s)    |
                                              +-----------+
```

**How the pieces connect:**

- The browser hits the OpenShift Router, which terminates TLS and forwards traffic to the matching Service based on the Route hostname.
- Each Service selects pods using label selectors (e.g., `app: parksmap`, `deployment: parksmap`).
- The parksmap frontend discovers backends by querying the Kubernetes API for Services labelled `type: parksmap-backend`.
- The nationalparks backend connects to MongoDB using the Service DNS name (`mongodb`) passed via the `MONGODB_SERVER_HOST` environment variable.
- MongoDB has no Route because it should only be reachable from within the cluster.

## Dev vs SIT environments

Throughout the workshop, you will deploy to two environments:

| Aspect | Dev | SIT |
|--------|-----|-----|
| Purpose | Rapid testing and iteration | Stable integration testing |
| Namespace | `userN-dev` | `userN-sit` |
| Frontend image | `quay.io/openshift-roadshow/parksmap:latest` | `docker.io/iogk/parksmap:1.0-sit` |
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
