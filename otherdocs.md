## Prerequisites

Install the following tools before starting. Every command in this workshop depends on them.

### 1. OpenShift CLI (`oc`)

The primary interface for interacting with your OpenShift cluster. Also provides a built-in `oc create -k` / `oc delete -k` shorthand for Kustomize.

```bash
# macOS (Homebrew)
brew install openshift-cli

# Windows (Winget)
winget install -e --id RedHat.OpenShift-Client

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
# macOS (Homebrew)
brew install helm

# Windows (Winget)
winget install Helm.Helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

### 3. Kustomize (standalone)

Kustomize layers environment-specific patches on top of base Kubernetes YAML without ever touching the originals.

```bash
# macOS (Homebrew)
brew install kustomize

# Windows (Winget)
winget install Kubernetes.kustomize

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

# Windows (PowerShell)
Invoke-WebRequest -Uri "https://github.com/carvel-dev/vendir/releases/latest/download/vendir-windows-amd64.exe" -OutFile "vendir.exe"
# Move to a directory in your PATH, e.g., C:\Windows\System32
Move-Item -Path "vendir.exe" -Destination "C:\Windows\System32\vendir.exe"

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
# macOS (Homebrew)
brew install skopeo

# Windows (via WSL - Windows Subsystem for Linux)
wsl --install
# After reboot, open your WSL terminal and run:
sudo apt update && sudo apt install skopeo -y

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
# macOS (Homebrew)
brew install make

# Windows (Chocolatey)
choco install make
# Or via Winget: winget install GnuWin32.Make

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