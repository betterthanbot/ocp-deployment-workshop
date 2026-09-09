# OCP Deployment Workshop: Helm on OpenShift

A hands-on workshop for deploying applications to OpenShift using Helm. You will deploy a chart across two environments with different security restrictions, and debug real-world failures — all from inside Red Hat OpenShift Dev Spaces.

---

## The Story

You are a developer joining the **ParksMap** team. The application displays national parks on a map, backed by a REST API and a MongoDB database. Your team has been deploying using the OpenShift web console — it is time to move to infrastructure-as-code using **Helm**.

---

## Prerequisites

- Completed the **OpenShift Basics** class
- Completed the **ParksMap clickops lab**
- Access to your assigned namespaces — `userN-dev` and `userN-sit`
- A Red Hat OpenShift account with Dev Spaces enabled

---

## Workshop Structure (90 Minutes)

| Section | Time | Description |
|---------|------|-------------|
| Setup: Dev Spaces + Tool Verification | ~15 min | Launch workspace, verify `helm`/`oc`, confirm namespaces |
| [Part 1: Helm Foundations](01-helm-foundations/) | ~30 min | Deploy to DEV using a Helm chart |
| [Part 2: Production Readiness](02-production-readiness/) | ~30 min | Debug and fix a broken deployment in SIT |
| Part 3: Safe Upgrade + Rollback Drill | ~10 min | Practice release revisions and rollback recovery |
| Part 4: Lint + Template Validation Gate | ~5 min | Build a pre-deploy quality check habit |
| [Bonus: Deploy a Web App](03-bonus-deployment/) | If time permits | Deploy a third-party chart with minimal guidance |
| [Challenge 04: Kustomize Base + Overlay](04-kustomize-challenge/) | If time permits | Deploy with Kustomize overlay and update app by changing one variable |

---

## Step 1 — Launch Your Dev Spaces Workspace

### 1.1 — Open Dev Spaces

1. Log in to your OpenShift web console.
2. Click the **grid launcher icon** (⋮⋮⋮) in the top-right corner.
3. Select **Red Hat OpenShift Dev Spaces**.

> If Dev Spaces is not in the launcher, ask your workshop conductor.

### 1.2 — Create a Workspace

1. Click **Create Workspace**.
2. Under **Choose an Editor**, select **VS Code - Opensource**.
3. In the **Import from Git** field, paste:
   ```
   https://gitlab.com/betterthanbot/ocp-deployment-workshop.git
   ```
   
   If you get a rate limit, do try to import from GitHub instead with this link
   ```
   https://github.com/betterthanbot/ocp-deployment-workshop.git
   ```
4. Click **Create & Open**.

Dev Spaces will clone the repository and launch a browser-based VS Code with all workshop files ready in the explorer.

> **What is `devfile.yaml`?** It tells Dev Spaces which container image to use for your workspace — one that already has `helm`, `oc`, and other tools pre-installed. You don't need to touch it.

---

## Step 2 — Open a Terminal & Verify Setup

1. Click **Terminal → New Terminal** in the top menu bar.
2. Run the following to confirm your tools and login:

```bash
helm version
oc version
oc whoami
```

3. Check your assigned namespaces:

```bash
oc projects
```

You should see `userN-dev` and `userN-sit` (where `N` is your user number). **Note these down** — you will use them throughout the workshop.

---

## Step 3 — The ParksMap Application

Three components wired together through OpenShift Routes, Services, and Deployments:

```
  Browser (HTTPS)
       |
  OpenShift Router (HAProxy)
       |                    |
  Route: parksmap      Route: nationalparks
       |                    |
  Service: parksmap    Service: nationalparks  ──▶  Service: mongodb
       |                    |                             |
  Pod: parksmap        Pod: nationalparks           Pod: mongodb
  (frontend)           (backend)                   (database, no Route)
```

- The **frontend** discovers backends by looking up Services labelled `type: parksmap-backend`.
- The **backend** connects to MongoDB via the DNS name `mongodb` using `MONGODB_SERVER_HOST`.
- **MongoDB** is internal only — it has no Route.

---

## Step 4 — Dev vs SIT Environments

| Aspect | DEV | SIT |
|--------|-----|-----|
| Namespace | `userN-dev` | `userN-sit` |
| Purpose | Rapid testing | Stable integration testing |
| Image tags | `latest` allowed | `:latest` **Monitored by ACS** |

### ⚠️ SIT: ACS Image Policy

The SIT namespace has **Red Hat Advanced Cluster Security (ACS)** informing on a policy that **looks for `:latest` image tags**. This is a real-world security control to catch unversioned images from reaching integration environments.

You will encounter this error in Part 2 — and fixing it is the exercise. See [Step 5.2](#52--sit-deployment) for the fix.

---

## Step 5 — Hands-On: Deploy the Chart

> **Golden rule:** Always run `helm template` before `helm install` to catch mistakes before they hit the cluster.

---

### 5.1 — DEV Deployment

Navigate to the Part 1 directory:

```bash
cd /projects/ocp-deployment-workshop/01-helm-foundations
```

**Preview what will be deployed:**

```bash
helm template parksmap ./ -f values-dev.yaml
```

Scan the output and confirm:
- Images are using the expected tags
- Namespace matches `userN-dev`
- Routes have TLS configured

**Deploy:**

```bash
helm install parksmap ./ --values=values-dev.yaml -n userN-dev
```

**Check everything is running:**

```bash
oc get pods -n userN-dev
oc get jobs -n userN-dev
oc get routes -n userN-dev
```

> **Why check jobs?** The chart includes a database init job that seeds the national parks data — the same step you previously ran manually via the `/ws/data/load` endpoint. If the map loads but shows no parks, check the job logs:
> ```bash
> oc logs job/mongo-init -n userN-dev
> ```

Open the route URL in your browser and confirm the map shows national parks. ✅

**When done, uninstall:**

```bash
helm uninstall parksmap -n userN-dev
```

---

### 5.2 — SIT Deployment

Navigate to the Part 2 directory:

```bash
cd /projects/ocp-deployment-workshop/02-production-readiness
```
**Change to your SIT working namespace:**

```bash
oc project userN-sit
```

**Try deploying as-is first:**

```bash
helm install parksmap ./ --values=values-sit.yaml -n userN-sit
```

You will see an ACS admission error — this is expected! The `values-sit.yaml` file still has `tag: latest` set for all images.

---

#### 5.2.1 — Fix `values-sit.yaml`

Open `values-sit.yaml` in the VS Code file explorer. For **each image block**, comment out `tag: latest` and uncomment the `digest` line:

```yaml
# Before:
  image:
    repository: quay.io/rhn-support-gong/parksmap
    tag: latest
    # digest: sha256:89d1e324846cb431df9039e1a7fd0ed2ba0c51aafbae73f2abd70a83d5fa173b

# After:
  image:
    repository: quay.io/rhn-support-gong/parksmap
    # tag: latest
    digest: sha256:89d1e324846cb431df9039e1a7fd0ed2ba0c51aafbae73f2abd70a83d5fa173b
```

Repeat for `backend`, `database`, and `databaseinit`. All digests are pre-filled — just uncomment them.

> **Why digests?** A tag like `:latest` is mutable and can point to a different image at any time. A digest (`sha256:...`) is a cryptographic fingerprint tied to a specific image — it guarantees what you deploy is exactly what was tested.

---

#### 5.2.2 — Verify and Redeploy

Uninstall the failed release:

```bash
helm uninstall parksmap -n userN-sit
```

Preview the fixed templates — images should now show `@sha256:...` instead of `:latest`:

```bash
helm template parksmap ./ -f values-sit.yaml
```

Deploy:

```bash
helm install parksmap ./ --values=values-sit.yaml -n userN-sit
```

**Check everything is running:**

```bash
oc get pods -n userN-sit
oc get jobs -n userN-sit
oc get routes -n userN-sit
```

Open the route URL in your browser and confirm the map shows national parks. ✅

---

🎉 **Great progress!** You have deployed the same application across two environments using Helm, and resolved a real ACS security policy enforcement issue.

Next, continue with two short drills to build real-day-2 Helm operations skills.

---

## Step 6 — Exercise 3: Safe Upgrade + Rollback Drill (~10 min)

This exercise teaches release lifecycle management using `helm upgrade`, `helm history`, and `helm rollback`.

### 6.1 — Reinstall Baseline in DEV

```bash
cd /projects/ocp-deployment-workshop/01-helm-foundations
helm upgrade --install parksmap ./ -f values-dev.yaml -n userN-dev
oc get pods -n userN-dev
```

### 6.2 — Perform a Safe Upgrade

Run a simple upgrade by overriding frontend replicas:

```bash
helm upgrade parksmap ./ -f values-dev.yaml -n userN-dev --set frontend.replicaCount=2
oc rollout status deployment/parksmap -n userN-dev
helm history parksmap -n userN-dev
```

You should now see a new Helm revision.

### 6.3 — Simulate a Bad Upgrade, Then Recover

Trigger a controlled failure by setting an invalid image tag:

```bash
helm upgrade parksmap ./ -f values-dev.yaml -n userN-dev --set frontend.image.tag=does-not-exist
oc get pods -n userN-dev
```

Inspect rollout/pod errors, then roll back to the previous good revision:

```bash
helm history parksmap -n userN-dev
helm rollback parksmap -n userN-dev
oc rollout status deployment/parksmap -n userN-dev
```

**Outcome:** You can recover from bad releases without deleting and reinstalling.

---

## Step 7 — Exercise 4: Lint + Template Validation Gate (~5 min)

This exercise reinforces a pre-deploy quality gate before cluster changes.

### 7.1 — Validate Part 1 Chart

```bash
cd /projects/ocp-deployment-workshop/01-helm-foundations
helm lint ./
helm template parksmap ./ -f values-dev.yaml > /tmp/parksmap-dev-rendered.yaml
```

### 7.2 — Validate Part 2 Chart

```bash
cd /projects/ocp-deployment-workshop/02-production-readiness
helm lint ./
helm template parksmap ./ -f values-sit.yaml > /tmp/parksmap-sit-rendered.yaml
```

### 7.3 — Break/Fix Mini Challenge

Temporarily comment out one required value (for example an image `repository`) in `values-sit.yaml`, re-run `helm template`, observe failure, then restore the value and confirm validation passes again.

**Outcome:** You build a repeatable habit: `helm lint` + `helm template` before every deploy.

---

## Step 8 — Bonus Deployment (If Time Permits)

Use this as an optional challenge after Exercises 1-4.
You will troubleshoot **two intentional errors** in a single file (`values.yaml`), then complete deployment with `helm upgrade --install`.

```bash
cd /projects/ocp-deployment-workshop/03-bonus-deployment
```

### 8.1 — Easy Error: `helm lint` fails (YAML syntax)

Run:

```bash
helm lint ./
```

It should fail due to malformed YAML in `resources.requests` inside `values.yaml`.
Fix this block in `values.yaml`:

```yaml
resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

Re-run `helm lint` until it passes.

### 8.2 — Challenging Error: `helm upgrade` fails (OpenShift Route validation)

Run:

```bash
helm upgrade --install my-web-app ./ -n userN-dev
```

It should fail because `route.tls.termination` is intentionally set to an invalid value in `values.yaml`.
Fix it to one of: `edge`, `passthrough`, `reencrypt` (recommended: `edge`).

### 8.3 — Deploy the fixed chart with upgrade workflow

Re-run:

```bash
helm upgrade --install my-web-app ./ -n userN-dev
oc get pods,svc,routes -n userN-dev
```

Open the route and find the finishing page.

**Goal:** Practice deploying a third-party chart with minimal guidance, like in real project handovers.

---

## Step 9 — Challenge 04: Kustomize Base + Overlay (Optional)

Now deploy a styled web app dashboard using Kustomize and switch configurations between **staging** and **prod**.

```bash
cd /projects/ocp-deployment-workshop/04-kustomize-challenge
oc project userN-dev
oc apply -k overlays/staging
oc get pods,svc,routes -n userN-dev
```

Get the route URL:

```bash
oc get route kustom-web -n userN-dev -o jsonpath='https://{.spec.host}{"\n"}'
```

Apply the prod configuration:

```bash
oc apply -k overlays/prod
oc rollout status deployment/kustom-web -n userN-dev
```

Refresh the same route page and confirm the dashboard changes from **STAGING** to **PRODUCTION**.

**Goal:** Learn Kustomize base/overlay workflow and config-driven rollouts.

---

🎉 **Hands-on complete!** You now practiced:
- Initial deployment in DEV
- Security-driven fix in SIT
- Upgrade and rollback operations
- Local validation gates before cluster changes
- Optional third-party chart deployment challenge
- Optional Kustomize base + overlay deployment

---

## Helm Quick Reference

### Core Commands

```bash
helm lint ./                                                         # Validate chart syntax
helm template parksmap ./ -f values-dev.yaml                        # Render templates locally
helm install parksmap ./ -f values-dev.yaml -n userN-dev            # Install
helm upgrade parksmap ./ -f values-dev.yaml -n userN-dev            # Upgrade existing release
helm upgrade --install parksmap ./ -f values-dev.yaml -n userN-dev  # Install or upgrade (idempotent)
helm uninstall parksmap -n userN-dev                                 # Remove release
```

### Inspect & Debug

```bash
helm list -n userN-dev                                               # List releases in namespace
helm list -A                                                         # List across all namespaces
helm get values parksmap -n userN-dev                               # Show values in use
helm get values parksmap -n userN-dev --all                         # Show all values incl. defaults
helm get manifest parksmap -n userN-dev                             # Show rendered YAML of live release
helm history parksmap -n userN-dev                                  # Show revision history
helm rollback parksmap -n userN-dev                                 # Roll back to previous revision
helm rollback parksmap 2 -n userN-dev                               # Roll back to specific revision
helm install parksmap ./ -f values-dev.yaml -n userN-dev --dry-run --debug  # Dry run with debug
```

---

## OpenShift Quick Reference

```bash
# Status
oc get pods -n userN-dev                                      # List pods
oc get pods -n userN-dev -w                                   # Watch pods live
oc get jobs -n userN-dev                                      # List jobs
oc get svc -n userN-dev                                       # List services
oc get routes -n userN-dev                                    # List routes + URLs
oc get endpoints -n userN-dev                                 # Verify pod-service wiring
oc get all -n userN-dev                                       # All resources at once

# Debugging
oc get events -n userN-dev --sort-by='.lastTimestamp'         # Recent events (start here!)
oc describe pod <pod-name> -n userN-dev                       # Pod details + events
oc logs <pod-name> -n userN-dev                               # Pod logs
oc logs -f <pod-name> -n userN-dev                            # Stream logs live
oc logs <pod-name> -n userN-dev --previous                    # Logs from crashed container
oc rollout status deployment/<name> -n userN-dev              # Deployment rollout status

# Secrets
oc get secret <name> -n userN-dev -o yaml                                           # View secret (base64)
oc get secret <name> -n userN-dev -o jsonpath='{.data.password}' | base64 -d       # Decode value

# Context
oc whoami                    # Current user
oc projects                  # Your namespaces
oc project userN-dev         # Switch default namespace
```

---

## Troubleshooting

### ACS blocks deployment — `admission webhook denied`

**Cause:** One or more images in `values-sit.yaml` still use `tag: latest`.

**Fix:** In `02-production-readiness/values-sit.yaml`, for every image block comment out `tag: latest` and uncomment `digest: sha256:...`. Then:
```bash
helm uninstall parksmap -n userN-sit
helm install parksmap ./ -f values-sit.yaml -n userN-sit
```

---

### `helm install` fails — "release already exists"

**Cause:** A previous install (even a failed one) left a release behind.

**Fix:**
```bash
helm uninstall parksmap -n userN-dev
helm install parksmap ./ -f values-dev.yaml -n userN-dev

# Or use upgrade --install to handle both cases automatically:
helm upgrade --install parksmap ./ -f values-dev.yaml -n userN-dev
```

---

### Pods stuck in `Pending`

**Cause:** Scheduling issue — quota exceeded, missing storage, or node constraints.

**Diagnose:**
```bash
oc get events -n userN-dev --sort-by='.lastTimestamp'
oc describe pod <pod-name> -n userN-dev    # Check the Events section
```

---

### Pods in `CrashLoopBackOff`

**Cause:** Application crashed on startup — bad env var, failed DB connection, or misconfigured health probe.

**Diagnose:**
```bash
oc logs <pod-name> -n userN-dev --previous    # Logs from the last crash
oc describe pod <pod-name> -n userN-dev
```

---

### App loads but map shows no parks

**Cause:** The database init job failed or hasn't finished yet.

**Diagnose:**
```bash
oc get jobs -n userN-dev
oc logs job/mongo-init -n userN-dev
```

---

### Route accessible but returns 503

**Cause:** The route exists but no healthy pods are behind the service.

**Diagnose:**
```bash
oc get endpoints -n userN-sit      # Should show pod IPs — if "<none>", pods aren't ready
oc get pods -n userN-sit
oc describe pod <pod-name> -n userN-sit
```

---

### `ErrImagePull` / `ImagePullBackOff`

**Cause:** Wrong image reference, or `:latest` tag blocked by ACS in SIT.

**Diagnose:**
```bash
oc describe pod <pod-name> -n userN-dev    # Check Events for the exact pull error message
```

---

## Repository Structure

```
ocp-deployment-workshop/
├── devfile.yaml                     # Dev Spaces workspace config (auto-read on import)
├── README.md                        # This file
├── 01-helm-foundations/             # Part 1 — DEV deployment
│   ├── Chart.yaml
│   ├── values.yaml                  # Base defaults
│   ├── values-dev.yaml              # DEV overrides
│   └── templates/
├── 02-production-readiness/         # Part 2 — SIT deployment (fix the digests!)
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-sit.yaml
│   └── templates/
├── 03-bonus-deployment/             # Optional third-party chart challenge
└── solutions/                       # Full working reference — try first before peeking
```

---

## Tips

- **`helm template` first, always.** Catching YAML errors locally saves time.
- **Events are your best friend.** `oc get events -n <namespace> --sort-by='.lastTimestamp'` is the fastest way to diagnose almost any failure.
- **`upgrade --install` is idempotent.** Use it to avoid "release already exists" errors when re-running commands.
- **Your namespace is your sandbox.** You cannot affect other users' deployments.
- **Solutions are in `/solutions`.** Try the exercise first — the fix is usually just one or two lines.

---

*Repository: [https://github.com/betterthanbot/ocp-deployment-workshop](https://github.com/betterthanbot/ocp-deployment-workshop)*