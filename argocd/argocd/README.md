# ArgoCD Configuration Directory

## Overview

The `/argocd` directory contains the **GitOps platform configuration** that defines how Argo CD manages this repository and the target clusters.

This directory acts as the **central control layer** for GitOps operations. It contains declarative configuration that controls:

* Platform permissions
* Project boundaries and access controls
* Application deployment definitions
* ApplicationSet deployment automation
* Policy and governance configuration

All resources inside this directory are automatically managed and synchronized by Argo CD after the bootstrap process is completed.

---

## How This Directory Is Used

After the bootstrap application is deployed, Argo CD continuously monitors the `/argocd` directory and applies all valid Kubernetes manifests stored within it.

Any updates made here will automatically propagate to the cluster once changes are merged into the repository.

This directory serves as the **source of truth** for GitOps platform behavior.

---

## Directory Structure

```
argocd/
├ rbac/
├ projects/
├ applications/
├ applicationsets/
```

Each subdirectory is responsible for a specific area of GitOps platform configuration.

---

## rbac/

Contains Role-Based Access Control definitions required for Argo CD to manage cluster resources.

Examples include:

* ClusterRole definitions
* RoleBindings granting Argo CD permissions
* Operator-specific access requirements
* Cross-namespace permission delegation

RBAC configuration ensures Argo CD has appropriate privileges to deploy and reconcile resources safely and securely.

---

## projects/

Defines Argo CD `AppProject` resources that control:

* Which Git repositories can be used
* Which namespaces or clusters applications may deploy into
* Resource whitelisting and governance boundaries
* Multi-team or multi-environment segmentation

Projects provide security isolation and deployment guardrails.

---

## applications/

Contains Argo CD `Application` resources used to deploy individual workloads or platform components.

Applications typically define:

* Git repository location
* Branch or revision
* Kustomize, Helm, or manifest source path
* Target cluster and namespace
* Synchronization policies

Applications represent direct workload or configuration deployments.

---

## applicationsets/

Contains Argo CD `ApplicationSet` resources used to dynamically generate multiple `Application` resources.

ApplicationSets are useful for:

* Multi-cluster deployments
* Environment scaling
* Site-based deployments
* Automated workload generation patterns

ApplicationSets improve scalability and reduce duplication.

---

## Configuration Flow

The configuration workflow typically follows this order:

```
Bootstrap
   ↓
ArgoCD loads /argocd
   ↓
RBAC permissions applied
   ↓
Projects created
   ↓
Applications / ApplicationSets deployed
   ↓
Workloads and overlays deployed
```

---

## GitOps Workflow

### Updating Platform Configuration

1. Modify configuration files within `/argocd`
2. Commit and submit a Pull Request
3. After merge, Argo CD automatically reconciles the changes

---

### Adding New Workloads

To deploy new workloads:

1. Add new `Application` or `ApplicationSet` definitions
2. Ensure RBAC and Project rules permit deployment
3. Commit changes to Git
4. Argo CD deploys automatically

---

## Design Principles

This directory follows several GitOps and platform engineering principles:

* Declarative configuration
* Version controlled infrastructure
* Least-privilege access model
* Environment and cluster reproducibility
* Separation of platform and workload responsibilities

---

## Best Practices

* Keep platform configuration separate from workload overlays
* Use Pull Requests for all changes
* Maintain RBAC definitions carefully to avoid over-permission
* Document new ApplicationSets and Projects clearly
* Validate synchronization results using Argo CD UI or CLI

---

## Disaster Recovery and Reproducibility

Because all platform configuration is stored here, rebuilding a cluster is simplified:

1. Install OpenShift GitOps Operator
2. Apply bootstrap configuration
3. Argo CD restores all platform configuration from `/argocd`

---

## Summary

The `/argocd` directory represents the GitOps platform control plane for this repository. It defines how Argo CD is configured, what it can deploy, and how deployments are organized and governed across clusters and environments.

---
