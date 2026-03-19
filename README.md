# OCP Deployment Workshop
### Helm + Kustomize + OpenShift 4.x — 101 Guide for New Developers

This workshop walks you through the **full deployment lifecycle** for a containerised web application on OpenShift Container Platform 4.x. You will learn how to:

- Vendor a Helm chart reproducibly using **vendir**
- Render Helm templates into static Kubernetes YAML
- Pin image digests and apply environment-specific patches using **Kustomize**
- Deploy and delete workloads directly from Kustomize using **`oc`**
- Mirror container images for disconnected / air-gapped environments using **skopeo**
- Automate every step with a **Makefile**

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Repository Structure](#repository-structure)
3. [Concepts Overview](#concepts-overview)
4. [Step-by-Step Deployment Guide](#step-by-step-deployment-guide)
   - [Step 1 — Fetch the Helm Chart (vendir)](#step-1--fetch-the-helm-chart-vendir)
   - [Step 2 — Render Helm Templates](#step-2--render-helm-templates)
   - [Step 3 — Build with Kustomize](#step-3--build-with-kustomize)
   - [Step 4 — Deploy to OpenShift](#step-4--deploy-to-openshift)
   - [Step 5 — Tear Down](#step-5--tear-down)
5. [Understanding the Overlay — The Workshop Challenge](#understanding-the-overlay--the-workshop-challenge)
6. [Disconnected / Air-Gapped Image Mirroring](#disconnected--air-gapped-image-mirroring)
7. [Makefile Reference](#makefile-reference)
8. [values.yaml Reference](#valuesyaml-reference)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Install the following tools before starting. Every command in this workshop depends on them.

### 1. OpenShift CLI (`oc`)

The primary interface for interacting with your OpenShift cluster. Also provides a built-in `oc create -k` / `oc delete -k` shorthand for Kustomize.

```bash
# macOS (Homebrew)
brew install openshift-cli

# Linux — download from Red Hat mirror
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
tar -xvf openshift-client-linux.tar.gz
sudo mv oc /usr/local/bin/

# Verify
oc version
```

### 2. Helm 3

In this workshop Helm is used **only for templating** — it never talks to your cluster directly.

```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

### 3. Kustomize (standalone)

Kustomize layers environment-specific patches on top of base Kubernetes YAML without ever touching the originals.

```bash
# macOS
brew install kustomize

# Linux
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/

# Verify
kustomize version
```

> **Note:** `oc` ships with a bundled version of kustomize (`oc kustomize`). The `make build` target in this workshop calls the standalone `kustomize` binary directly. Install the standalone version to avoid version drift.

### 4. vendir

`vendir` ("vendor directory") fetches external resources — Helm charts, Git repos, HTTP files — and pins them to an exact commit in a lock file. Think of it as `go mod` for Kubernetes tooling.

```bash
# macOS (Homebrew via Carvel)
brew tap carvel-dev/carvel
brew install vendir

# Linux
curl -L https://github.com/carvel-dev/vendir/releases/latest/download/vendir-linux-amd64 -o vendir
chmod +x vendir
sudo mv vendir /usr/local/bin/

# Verify
vendir version
```

### 5. skopeo

`skopeo` copies and inspects container images without a running Docker daemon. Used in this workshop to mirror images into offline / air-gapped environments.

```bash
# macOS
brew install skopeo

# RHEL / Fedora
sudo dnf install skopeo -y

# Ubuntu / Debian
sudo apt install skopeo -y

# Verify
skopeo --version
```

### 6. make

`make` glues all the above tools together via the `makefile`.

```bash
# macOS
brew install make

# Linux
sudo apt install make -y   # Debian / Ubuntu
sudo dnf install make -y   # RHEL / Fedora

# Verify
make --version
```

### Log in to Your OpenShift Cluster

Before running any `oc` commands, authenticate:

```bash
oc login --token=<your-token> --server=https://api.<cluster-domain>:6443

# Confirm you are logged in
oc whoami
oc project
```

---

## Repository Structure

```
ocp-deployment-workshop/
│
├── bases/
│   └── my-web-app/
│       ├── makefile              # All automation targets — start here
│       ├── vendir.yml            # Declares Helm chart source (Git repo + pinned tag)
│       ├── vendir.lock.yml       # Exact commit SHA locked by vendir (do not edit)
│       ├── values.yaml           # Your Helm overrides — primary config file
│       ├── skopeo.yaml           # Image list for air-gapped mirroring
│       ├── kustomization.yaml    # Base Kustomize: sets namespace + pins image digest
│       │
│       ├── vendor/               # ← Populated by `make fetch` — the vendored Helm chart
│       │   ├── Chart.yaml
│       │   ├── values.yaml       # Chart defaults (override in bases/my-web-app/values.yaml)
│       │   └── templates/
│       │       ├── deployment.yaml
│       │       ├── service.yaml
│       │       ├── route.yaml
│       │       ├── pvc.yaml
│       │       ├── configmap.yaml
│       │       ├── serviceaccount.yaml
│       │       ├── rolebinding.yaml
│       │       ├── secret.yaml
│       │       ├── hpa.yaml
│       │       ├── vpa.yaml
│       │       └── _helpers.tpl
│       │
│       └── my-web-app.yaml       # ← Generated by `make template` (Helm output)
│                                 #   committed so the base kustomization.yaml can reference it
│
└── overlay/
    ├── nonprod/
    │   ├── kustomization.yaml    # Nonprod overlay — references base + patches
    │   ├── patches/
    │   │   └── my-web-app/
    │   │       └── psm.yaml      # Strategic Merge Patch: replaces index.html content
    │   └── secrets/
    │       ├── kustomization.yaml
    │       └── imagePullSecret.yaml   # Fill in with your registry credentials if needed
    │
    └── prod/
        ├── kustomization.yaml
        ├── patches/
        │   └── my-web-app/
        │       └── psm.yaml      # Same patch mechanism, different HTML content
        └── secrets/
            ├── kustomization.yaml
            └── imagePullSecret.yaml
```

> **`deployable.yaml` is gitignored.** It is produced by `make build` as a local preview of the final manifest. Never commit it — the source of truth is the combination of `my-web-app.yaml` + `kustomization.yaml`.

---

## Concepts Overview

### Why vendir instead of `helm repo add`?

`helm repo add` + `helm upgrade --install` pulls from a remote source at deploy time. This creates three problems for teams:

- Different developers may get different chart versions on the same `ref`
- There is no local audit trail of the exact code that was deployed
- Air-gapped clusters cannot reach the internet at all

`vendir` solves all three by checking out the chart into `vendor/` and locking the exact Git SHA in `vendir.lock.yml`. Every teammate who runs `make fetch` gets byte-for-byte identical files.

In this workshop the chart is pinned to tag **`0.0.1`** of the `betterthanbot/chart-template` repository:

```yaml
# vendir.yml
git:
  url: https://github.com/betterthanbot/chart-template.git
  ref: 0.0.1
```

```yaml
# vendir.lock.yml (auto-generated — do not edit)
git:
  commitTitle: release 0.0.1
  sha: 330637384eb13d5cb4d91c4775f9a0bca285187e
  tags:
    - 0.0.1
```

### Why `helm template` instead of `helm install`?

`helm template` renders the chart to plain Kubernetes YAML **without contacting the cluster**. The output (`my-web-app.yaml`) is then handed to Kustomize. Benefits:

- Every manifest is visible as plain text in Git — no hidden Helm release state
- Kustomize can surgically patch anything before it reaches the cluster
- Works offline after `make fetch` has been run once

### Why Kustomize on top of Helm?

Helm `values.yaml` handles most config. Kustomize adds things Helm cannot easily do:

- **Image digest pinning** — replaces a floating `latest` tag with an immutable `sha256` digest at the Kustomize layer, so the cluster always runs the exact binary you tested
- **Strategic Merge Patches (SMPs)** — override any field of any resource without modifying the Helm chart templates
- **Namespace injection** — stamps a namespace on every resource so the chart stays generic
- **Per-environment content** — in this workshop, each overlay swaps the `index.html` served by Apache using a ConfigMap patch

### Why `oc create -k` instead of `oc apply -f deployable.yaml`?

The `make deploy` target uses `oc create -k .` which tells `oc` to run Kustomize internally and apply the result directly — no intermediate `deployable.yaml` file required. This is the cleanest GitOps-style flow: your working directory **is** the source of truth.

`make build` (`kustomize build . > deployable.yaml`) still exists as a dry-run / inspection step so you can review the final YAML before committing to a deploy.

---

## Step-by-Step Deployment Guide

All commands are run from inside `bases/my-web-app/` unless noted otherwise.

```bash
git clone https://github.com/betterthanbot/ocp-deployment-workshop.git
cd bases/my-web-app
```

Navigate to OCP console page, on the right, click on your username > copy login command 
Apply token in your on your terminal or VScode

```bash
oc login --token=sha256~xxx --server=https://api.cluster-xxx.com:6443
```

---

### Step 1 — Fetch the Helm Chart (vendir)

Download and vendor the chart at the pinned tag:

```bash
make fetch
# Equivalent to: vendir sync -f vendir.yml
```

vendir reads `vendir.yml`, clones the chart at tag `0.0.1`, and writes the files into `vendor/`. The SHA is recorded in `vendir.lock.yml`.

**Verify:**
```bash
ls vendor/
# Chart.yaml   README.md   templates/   values.yaml

cat vendir.lock.yml
# sha: 330637384eb13d5cb4d91c4775f9a0bca285187e
```

> To upgrade the chart later: change `ref:` in `vendir.yml` to the new tag or SHA, re-run `make fetch`, then commit both `vendir.yml` and the updated `vendir.lock.yml`.

---

### Step 2 — Render Helm Templates

Render the vendored chart using your `values.yaml` overrides:

```bash
make template
# Equivalent to:
# helm template my-web-app \
#   --values=values.yaml \
#   vendor/ \
#   > my-web-app.yaml
```

Helm resolves all `{{ .Values.* }}` expressions and writes plain Kubernetes YAML to `my-web-app.yaml`.

**Inspect the output — you should see these resource kinds:**
```bash
grep "^kind:" my-web-app.yaml
# ServiceAccount
# ConfigMap        (app env vars: APP_ENV, LOG_LEVEL)
# ConfigMap        (web content: index.html + servername.conf)
# PersistentVolumeClaim
# RoleBinding
# Service
# Deployment
# Route
```

> Edit `values.yaml` and re-run `make template` any time you change application config. The rendered `my-web-app.yaml` is committed to Git so the base `kustomization.yaml` can reference it without requiring Helm on every machine.

---

### Step 3 — Build with Kustomize

Preview the final manifest that will be sent to the cluster:

```bash
make build
# Equivalent to: kustomize build . > deployable.yaml
```

Kustomize reads `kustomization.yaml` and applies two transformations to `my-web-app.yaml`:

**1. Namespace injection** — stamps `my-web-app` on every resource:
```yaml
namespace: my-web-app
```

**2. Image digest pin** — replaces the floating `latest` tag with an immutable digest:
```yaml
images:
- name: registry.access.redhat.com/ubi9/httpd-24
  newName: registry.access.redhat.com/ubi9/httpd-24
  digest: sha256:38d71a4cf177f39a2bbe745183009943dbbf404de02aa5f879694aa024a4e6ac
```

**Verify the image reference in the output:**
```bash
grep "image:" deployable.yaml
# image: registry.access.redhat.com/ubi9/httpd-24@sha256:38d71a4...
```

The `@sha256:` notation means the cluster will **always** pull the exact image layer you tested — even if the `latest` tag is later overwritten upstream.

---

### Step 4 — Deploy to OpenShift

Create the namespace and deploy:
!For workshop users, Skip `oc new-project xxx`, and use your assigned Project / Namespace.

```bash
# Create the project (namespace) if it does not exist. 
oc new-project my-web-app

# Deploy directly from Kustomize — no intermediate file required
make deploy
# Equivalent to: oc create -k .
```

`oc create -k .` runs Kustomize internally and creates all resources in one shot.

**Monitor the rollout:**
```bash
# Watch pods come up
oc get pods -n <your-assigned-namespace> -w

# Full rollout status
oc rollout status deployment/my-web-app-betterthanbot-redhat -n <your-assigned-namespace>
```

**Verify all resources are healthy:**
```bash
oc get all -n <your-assigned-namespace>
oc get pvc   -n <your-assigned-namespace>
oc get route -n <your-assigned-namespace>
```

**Expected healthy state:**
```
NAME                                              READY   STATUS    RESTARTS
pod/my-web-app-betterthanbot-redhat-xxxxx-xxxxx   1/1     Running   0

NAME                                    HOST/PORT
route/my-web-app-betterthanbot-redhat   my-web-app-betterthanbot-redhat-my-web-app.apps.<cluster>
```

Open the Route URL in your browser. You should see the Apache placeholder page — this confirms the deployment succeeded.

> **Why no `host:` in the Route?** The `route.yaml` template deliberately omits the `host:` field. OpenShift auto-assigns a hostname in the format `<route-name>-<namespace>.apps.<cluster-domain>`, making the chart portable across any cluster without editing.

---

### Step 5 — Tear Down

Remove all resources created in the base directory:

```bash
# From bases/my-web-app/
make delete
# Equivalent to: oc delete -k .
```

Or delete the entire namespace to remove everything at once:

```bash
oc delete project my-web-app
```

---

## Disconnected / Air-Gapped Image Mirroring

If your OpenShift cluster has no internet access, mirror all container images to an internal registry **before** deploying. The Makefile provides a complete 3-step pipeline.

### The image list — `skopeo.yaml`

```yaml
registry.redhat.io:
  images:
    ubi9/httpd-24:
      - sha256:38d71a4cf177f39a2bbe745183009943dbbf404de02aa5f879694aa024a4e6ac
    library/busybox:
      - latest

quay.io:
  images:
    prometheus/node-exporter:
      - v1.6.1
```

Always use **digest pinning** (`sha256:...`) rather than mutable tags for production mirrors — a tag like `latest` can be overwritten at any time.

### Step A — Sync images from registry to local disk

Run on a machine with internet access:

```bash
make save-images
# mkdir -p ./offline-image-data
# skopeo sync --src yaml --dest dir skopeo.yaml ./offline-image-data
```

skopeo deduplicates shared layers — disk usage is typically far smaller than running `docker pull` for each image individually.

### Step B — Pack into a tarball

```bash
make pack-images
# tar -czvf offline-images.tar.gz ./offline-image-data
```

Transfer `offline-images.tar.gz` to the disconnected environment via USB, SFTP, or your approved secure transfer mechanism.

### Step C — Push to your internal mirror registry

Run inside the disconnected environment after extracting the tarball:

```bash
tar -xzvf offline-images.tar.gz

make push-images MIRROR_REGISTRY=registry.disconnected.local:5000/my-project
# skopeo sync \
#   --src dir \
#   --dest docker \
#   --dest-tls-verify=false \
#   ./offline-image-data \
#   registry.disconnected.local:5000/my-project
```

### Update `kustomization.yaml` to point to the mirror

```yaml
images:
- name: registry.access.redhat.com/ubi9/httpd-24
  newName: registry.disconnected.local:5000/my-project/ubi9/httpd-24
  digest: sha256:38d71a4cf177f39a2bbe745183009943dbbf404de02aa5f879694aa024a4e6ac
```

Re-run `make build` then `make deploy`.

---

## Makefile Reference

All targets are defined in `bases/my-web-app/makefile`.

| Target | Command | Description |
|--------|---------|-------------|
| `make fetch` | `vendir sync -f vendir.yml` | Vendor the chart from Git at the pinned ref |
| `make template` | `helm template ... > my-web-app.yaml` | Render Helm → static YAML |
| `make build` | `kustomize build . > deployable.yaml` | Apply Kustomize → preview final manifest |
| `make helm` | `fetch` + `template` + `build` | Full local pipeline in one shot |
| `make deploy` | `oc create -k .` | Deploy to cluster using Kustomize (first time) |
| `make delete` | `oc delete -k .` | Remove all resources from the cluster |
| `make save-images` | `skopeo sync ... --dest dir` | Mirror images from registry to local disk |
| `make pack-images` | `tar -czvf ...` | Compress image dir to tarball (calls save-images first) |
| `make push-images` | `skopeo sync ... --dest docker` | Push local images to mirror registry |
| `make clean` | `rm -rf ...` | Remove local image cache and generated files |

> **First deploy vs re-deploy:** `make deploy` uses `oc create -k .` which fails if resources already exist. For subsequent deploys after a config change, use `oc apply -k .` directly.

**Configurable variables — override on the command line:**

| Variable | Default | Description |
|----------|---------|-------------|
| `SYNC_YAML` | `skopeo.yaml` | Image list file |
| `SYNC_DIR` | `./offline-image-data` | Local image cache directory |
| `TAR_FILE` | `offline-images.tar.gz` | Tarball output name |
| `MIRROR_REGISTRY` | `registry.disconnected.local:5000/my-project` | Target mirror registry |

```bash
# Examples
make push-images MIRROR_REGISTRY=my-registry.corp.com:5000/ocp
make pack-images TAR_FILE=workshop-images-$(date +%Y%m%d).tar.gz
```

---

## values.yaml Reference

`bases/my-web-app/values.yaml` overrides the chart defaults in `vendor/values.yaml`. Only values you want to change need to be present — the chart defaults apply for everything else.

| Key | Default | Description |
|-----|---------|-------------|
| `replicaCount` | `1` | Number of Apache pods |
| `image.repository` | `registry.access.redhat.com/ubi9/httpd-24` | Container image |
| `image.tag` | `latest` | Overridden at deploy time by the Kustomize digest pin |
| `image.pullPolicy` | `IfNotPresent` | Kubernetes image pull policy |
| `service.port` | `8080` | Service port (httpd-24 does not use port 80) |
| `route.enabled` | `true` | Create an OpenShift Route |
| `route.tls.termination` | `edge` | TLS mode: `edge`, `passthrough`, or `reencrypt` |
| `persistence.enabled` | `true` | Mount a PVC at `/var/www/html` |
| `persistence.size` | `1Gi` | PVC storage request |
| `persistence.accessMode` | `ReadWriteOnce` | Use `ReadWriteMany` if `replicaCount > 1` |
| `persistence.storageClass` | `""` | Empty string = cluster default StorageClass |
| `autoscaling.enabled` | `false` | Enable HPA (scales pod count) |
| `autoscaling.maxReplicas` | `2` | HPA upper bound |
| `verticalAutoscaling.enabled` | `false` | Enable VPA — do not combine with HPA on CPU/Mem |
| `config.APP_ENV` | `production` | Injected as env var via ConfigMap |
| `config.LOG_LEVEL` | `info` | Injected as env var via ConfigMap |
| `database.enabled` | `false` | Deploy an in-cluster PostgreSQL or MySQL StatefulSet |

**Why no `route.hostname`?** Intentionally absent. OpenShift auto-assigns:
```
<route-name>-<namespace>.apps.<cluster-domain>
```
To set a custom hostname for a specific environment, add a Route Strategic Merge Patch in the overlay `psm.yaml`.

---

## Troubleshooting

### Pod stuck in `Pending`

```bash
oc describe pod <pod-name> -n <your-assigned-namespace>
```

Common causes: no matching StorageClass for the PVC, namespace resource quota exceeded, or image pull failure.

### Pod in `CrashLoopBackOff`

```bash
oc logs <pod-name> -n <your-assigned-namespace> --previous
```

Check for SCC violations (attempting to run as root), missing ConfigMap references, or health probe failures returning 403.

### 403 on liveness/readiness probe

Apache returns 403 when it serves an empty directory with no `index.html`. This workshop prevents it by mounting a default `index.html` from the `<release>-www` ConfigMap via `subPath`. If you see it anyway, verify the volume mounts are correct:

```bash
grep -A5 "www-defaults" deployable.yaml
```

### `ImagePullBackOff`

```bash
oc describe pod <pod-name> -n <your-assigned-namespace> | grep -A5 "Failed"
```

For private registries, ensure the pull secret is linked to the service account:

```bash
oc secrets link my-web-app-betterthanbot-redhat my-registry-secret --for=pull -n <your-assigned-namespace>
```

### Overlay patch not applying / wrong name error

The patch `metadata.name` must exactly match the resource name in `my-web-app.yaml`. Verify:

```bash
grep "name:.*www" bases/my-web-app/my-web-app.yaml
# name: my-web-app-betterthanbot-redhat-www
```

Ensure both overlays' `psm.yaml` files use that exact name. If you change the Helm release name in `make template`, update all patch files accordingly.

### `oc create -k` fails — resources already exist

`oc create` fails if resources are already present. Use `oc apply` for subsequent updates:

```bash
oc apply -k .
# or for an overlay:
oc apply -k ../../overlay/nonprod/
```

### ConfigMap change not reflected in the browser

ConfigMap volume mounts refresh within ~60 seconds (kubelet sync interval) without a pod restart. If the page is still stale after 2 minutes, force a rollout:

```bash
oc rollout restart deployment/my-web-app-betterthanbot-redhat -n <your-assigned-namespace>
```

### vendir: `ref not found`

The tag or branch in `vendir.yml` does not exist on the remote. List available refs:

```bash
git ls-remote https://github.com/betterthanbot/chart-template.git
```

---

## Further Reading

- [Helm Documentation](https://helm.sh/docs/)
- [Kustomize Documentation](https://kustomize.io/)
- [Kustomize Strategic Merge Patch](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/patches/)
- [vendir Documentation](https://carvel.dev/vendir/docs/latest/)
- [skopeo Documentation](https://github.com/containers/skopeo)
- [OpenShift CLI Reference](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html)
- [OCP Security Context Constraints](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html)
- [OCP Routes](https://docs.openshift.com/container-platform/latest/networking/routes/route-configuration.html)