# OCP Deployment Workshop: Helm Charts on OpenShift

A hands-on workshop for deploying applications to OpenShift using Helm charts. You will build charts from scratch, deploy across environments, and debug real-world failures — all from inside Red Hat OpenShift Dev Spaces.

---

## The Story

You are a developer joining the **ParksMap** team. The application displays national parks on a map, backed by a REST API and a MongoDB database. Your team has been deploying using the OpenShift web console — but it is time to move to infrastructure-as-code using **Helm**.

Over the next one hours, you will deploy a Helm chart to multiple environments with different restrictions, and debug the kinds of failures that happen in real production deployments.

---

## Prerequisites

Before you begin, make sure you have:

- Completed the **OpenShift Basics** class (Kubernetes / OCP fundamentals)
- Completed the **ParksMap clickops lab** (deploying via the web console)
- Access to your assigned namespaces — `userN-dev` and `userN-sit`
- A Red Hat OpenShift account with Dev Spaces enabled

---

## Workshop Structure

| Section | Estimated Time | Description |
|---------|---------------|-------------|
| [Part 1: Helm Foundations](01-helm-foundations/) | ~30 min | Build a Helm chart from scratch by completing skeleton templates and creating missing files |
| [Part 2: Production Readiness](02-production-readiness/) | ~30 min | Debug and fix a pre-broken chart covering common deployment pitfalls |
| [Bonus: Docker Compose Migration](bonus-compose-migration/) | If time permits | Translate a `docker-compose.yaml` into Helm chart resources |

Work through the sections in order. Each section has its own step-by-step instructions.

---

## Step 1 — Launch Your Dev Spaces Workspace

You will be writing and running all commands from inside **Red Hat OpenShift Dev Spaces**, which gives you a fully configured browser-based VS Code environment with `helm` and `oc` pre-installed.

### 1.1 — Open Dev Spaces from the OpenShift Console

1. Log in to your OpenShift web console.
2. Click the **grid / application launcher icon** (⋮⋮⋮) in the top-right corner of the navigation bar.
3. Select **Red Hat OpenShift Dev Spaces** from the drop-down menu.

> If you do not see Dev Spaces in the launcher, ask your workshop conductor to confirm it has been enabled for your user.

### 1.2 — Create a New Workspace from the Workshop Git Repository

1. Once Dev Spaces opens, click **Create Workspace**.
2. In the **Choose an Editor** tab, select VS Code - Opensource
3. In the **Import from Git** field, paste the following link:

   ```
   https://github.com/betterthanbot/ocp-deployment-workshop.git
   ```

4. Leave all other settings as default and click **Create & Open**.

Dev Spaces will clone the repository and launch a VS Code environment with all the workshop files already available in the file explorer on the left.

> **What is the `devfile.yaml`?**  
> The repository includes a `devfile.yaml` at its root. This file tells Dev Spaces which container image to use for your workspace (the Universal Developer Image with `helm`, `oc`, and other tools pre-installed). Dev Spaces reads it automatically — you do not need to configure anything.

---

## Step 2 — Open a Terminal in Dev Spaces

Once your workspace has loaded in VS Code:

1. Click **Terminal** in the top menu bar.
2. Select **New Terminal**.
3. A terminal panel will open at the bottom of the screen.

### 2.1 — Verify Your Tools

Run the following to confirm everything is installed and you are logged in:

```bash
helm version
oc version
oc whoami
```

### 2.2 — Check Your Namespaces

```bash
oc projects
```

You should see two namespaces assigned to you: `userN-dev` and `userN-sit` (where `N` is your user number). Write these down — you will use them throughout the workshop.

---

## Step 3 — The ParksMap Application

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
                                              | Pod(s)    |
                                              +-----------+
```

**How the pieces connect:**

- The browser hits the OpenShift Router, which terminates TLS and forwards traffic to the matching Service based on the Route hostname.
- Each Service selects pods using label selectors (e.g., `app: parksmap`).
- The parksmap frontend discovers backends by querying the Kubernetes API for Services labelled `type: parksmap-backend`.
- The nationalparks backend connects to MongoDB using the Service DNS name (`mongodb`) passed via the `MONGODB_SERVER_HOST` environment variable.
- MongoDB has no Route because it must only be reachable from within the cluster.

---

## Step 4 — Dev vs SIT Environments

You have been assigned two namespaces that simulate a real promotion pipeline:

| Aspect | DEV | SIT |
|--------|-----|-----|
| Purpose | Rapid testing and iteration | Stable integration testing |
| Namespace | `userN-dev` | `userN-sit` |
| Frontend image | `quay.io/rhn-support-gong/parksmap:latest` | Uses image digest (see below) |
| ACS image policy | Not enforced | **`latest` tags are blocked** |

### ⚠️ SIT Environment: ACS Image Policy

The SIT namespace has **Red Hat Advanced Cluster Security (ACS)** enabled with a policy that **blocks deployment of images tagged `:latest`**. This is a real-world security control that prevents unversioned, potentially unstable images from reaching integration environments.

When you try to deploy to SIT with `tag: latest`, you will see an error similar to:

```
Error: container has runAsNonRoot and image has non-numeric user (mongo-init), cannot verify user is non-root
# or an ACS admission controller rejection such as:
admission webhook "policyeval.stackrox.io" denied the request
```

**How to fix it:** Open `values-sit.yaml` and **uncomment the `digest` lines** for each image, and **remove or comment out the `tag` line**. For example:

```yaml
# Before (will be rejected by ACS):
frontend:
  image:
    repository: quay.io/rhn-support-gong/parksmap
    tag: latest

# After (fixed — use the digest instead):
frontend:
  image:
    repository: quay.io/rhn-support-gong/parksmap
    # tag: latest
    digest: sha256:89d1e324846cb431df9039e1a7fd0ed2ba0c51aafbae73f2abd70a83d5fa173b
```

Do the same for `backend`, `database`, and `databaseinit`. The digests are already pre-filled in `values-sit.yaml` — they just need to be uncommented.

> **Why digests instead of tags?** A tag like `:latest` is mutable — the image it points to can change at any time. A digest (`sha256:...`) is a cryptographic fingerprint that uniquely identifies a specific image layer. ACS enforces digests in the SIT environment to guarantee reproducibility and prevent supply-chain surprises.

---

## Step 5 — Visualise Before You Deploy (Helm Template)

**Always run `helm template` before `helm install`.** This renders your chart to plain YAML without contacting the cluster, so you can catch mistakes early.

### 5.1 — Render for DEV

```bash
# From the 01-helm-foundations directory:
cd /projects/ocp-deployment-workshop/01-helm-foundations

helm template parksmap ./ -f values-dev.yaml
```

Pipe to `less` if you want to scroll through the output:

```bash
helm template parksmap ./ -f values-dev.yaml | less
```

Or save it to a file to inspect it in the VS Code editor:

```bash
helm template parksmap ./ -f values-dev.yaml > /tmp/rendered-dev.yaml
```

### 5.1.1 — Deploy for DEV
When you have check your template and are ready to deploy run the following command:

```bash
helm install parksmap ./ --values=values-dev.yaml
```

Check if your pods are ready. 

```bash
oc get pods -n=userN-dev
oc get jobs -n=userN-dev
oc get routes -n=userN-dev
```

> **Why are we checking for jobs?** Remember seeding the database with `https://nationalparks-wksp-userX.apps.cluster.example.com/ws/data/load`? Since we are running helm now, and would like to even automate this, we have a database init! and that is done via a `kind: job`. If you open your map and do not see the national parks, you may want to check the logs of the pod or job to see if it managed to render all the data! :D 

### 5.1.2 — Uninstall helm for DEV

```bash
helm uninstall parksmap -n=userN-dev
```

### 5.2 — Render for SIT

```bash
# From the 02-production-readiness directory:
cd /projects/ocp-deployment-workshop/02-production-readiness

helm template parksmap ./ -f values-sit.yaml > 
```

### 5.2.1 — Deploy for SIT
When you have check your template and are ready to deploy run the following command:

```bash
helm install parksmap ./ --values=values-sit.yaml
```

Check if your pods are ready. 

```bash
oc get pods -n=userN-sit
oc get jobs -n=userN-sit
oc get routes -n=userN-sit
```

BOO! You should have received an error! If you read the start, you would have remembered that we needed to change the tags to a specific version or a digest! Lets do that right now.. 

### 5.2.2 — Fixing values-sit.yaml and redeploying the helm

In the folder, you should see `values-sit.yaml` click on it.. Looking at the value file, you can see the digest are being comment out. Remove the # hash and # the `tag:` or you can remove it entirely. 


Before...
```yaml
  image:
    repository: quay.io/rhn-support-gong/parksmap
    tag: latest
    # digest: sha256:89d1e324846cb431df9039e1a7fd0ed2ba0c51aafbae73f2abd70a83d5fa173b
    pullPolicy: IfNotPresent

```

After...
```yaml
  image:
    repository: quay.io/rhn-support-gong/parksmap
    # tag: latest
    digest: sha256:89d1e324846cb431df9039e1a7fd0ed2ba0c51aafbae73f2abd70a83d5fa173b
    pullPolicy: IfNotPresent

```
> Please continue to do it for all images... 


### 5.2.3 — Redeploying for SIT
When you have check your template and are ready to deploy run the following command:

Lets first, uninstall the helm and do a fresh working installation. 

```bash
helm uninstall parksmap -n=userN-dev

```

Then next, we will do a template, do check for the images now, it should be showing ...@sha256:xxx and not `tag: latest`
```bash
helm template parksmap ./ -f values-sit.yaml
```

If your template is good, lets do the deployment. 
```bash
helm install parksmap ./ --values=values-sit.yaml
```

Check if your pods are ready. 

```bash
oc get pods -n=userN-sit
oc get jobs -n=userN-sit
oc get routes -n=userN-sit
```

*YAY! We have completed this helm deployment 101! Now we wait for lunch!*

### Helpful notes! — What to look for

After rendering, scan the output for:

- Are the correct image tags or digests being used?
- Are the right number of replicas set?
- Do the namespace fields match your assigned namespaces?
- Are resource `requests` and `limits` present where expected?
- Are routes created with the correct TLS settings?

---

## Helm Commands Reference

### Core Workflow

```bash
# Validate chart syntax and formatting
helm lint ./

# Render templates to YAML without deploying (always run this first!)
helm template parksmap ./

# Render with a specific values file
helm template parksmap ./ -f values-dev.yaml

# Render with multiple values files (later files override earlier ones)
helm template parksmap ./ -f values-dev.yaml

# Install a chart into a namespace
helm install parksmap ./ -n userN-dev

# Install with a specific values file
helm install parksmap ./ -f values-dev.yaml -n userN-dev

# Upgrade an existing release (use after making changes)
helm upgrade parksmap ./ -f values-dev.yaml -n userN-dev

# Install or upgrade in a single command (idempotent)
helm upgrade --install parksmap ./ -f values-dev.yaml -n userN-dev

# Uninstall a release and delete all created resources
helm uninstall parksmap -n userN-dev
```

### Inspecting Releases

```bash
# List all Helm releases in a namespace
helm list -n userN-dev

# List releases across all namespaces
helm list -A

# Show the current values in use for a release
helm get values parksmap -n userN-dev

# Show ALL values (including defaults) for a release
helm get values parksmap -n userN-dev --all

# Show the rendered YAML of an installed release
helm get manifest parksmap -n userN-dev

# Show release history (useful for rollbacks)
helm history parksmap -n userN-dev
```

### Rollbacks & Debugging

```bash
# Roll back to the previous release revision
helm rollback parksmap -n userN-dev

# Roll back to a specific revision number
helm rollback parksmap 2 -n userN-dev

# Dry-run an install to preview what would happen
helm install parksmap ./ -f values-dev.yaml -n userN-dev --dry-run

# Show computed values without installing
helm install parksmap ./ -f values-dev.yaml -n userN-dev --dry-run --debug

# Lint and show detailed template errors
helm template parksmap ./ --debug
```

### Chart Information

```bash
# Show chart metadata
helm show chart ./

# Show default values
helm show values ./

# Show all chart info (chart + values + README)
helm show all ./
```

---

## OpenShift Commands Reference

### Checking What Is Running

```bash
# List all pods in your namespace
oc get pods -n userN-dev

# Watch pods update in real time
oc get pods -n userN-dev -w

# List services
oc get svc -n userN-dev

# List routes (gives you the URLs to test in a browser)
oc get routes -n userN-dev

# List all resources deployed in a namespace
oc get all -n userN-dev

# List service endpoints (useful to verify pod-to-service wiring)
oc get endpoints -n userN-dev
```

### Debugging Failures

```bash
# Get recent cluster events sorted by time — start here when something breaks
oc get events -n userN-dev --sort-by='.lastTimestamp'

# Describe a pod for detailed status, resource usage, and events
oc describe pod <pod-name> -n userN-dev

# Stream logs from a pod
oc logs <pod-name> -n userN-dev

# Follow logs in real time
oc logs -f <pod-name> -n userN-dev

# Get logs from a previous (crashed) container
oc logs <pod-name> -n userN-dev --previous

# Describe a deployment to check rollout status and events
oc describe deployment <deployment-name> -n userN-dev

# Check the rollout status of a deployment
oc rollout status deployment/<deployment-name> -n userN-dev
```

### Secrets and Config

```bash
# View a secret (base64-encoded)
oc get secret <secret-name> -n userN-dev -o yaml

# Decode a secret value inline
oc get secret <secret-name> -n userN-dev -o jsonpath='{.data.password}' | base64 -d
```

### Context and Authentication

```bash
# Check who you are logged in as
oc whoami

# List all projects / namespaces you have access to
oc projects

# Switch to a specific namespace so you don't have to add -n to every command
oc project userN-dev
```

---

## Deploying the Chart — Step by Step

### Deploy to DEV

```bash
cd /projects/ocp-deployment-workshop/01-helm-foundations

# 1. Validate the chart
helm lint ./

# 2. Preview what will be deployed
helm template parksmap ./ -f values-dev.yaml

# 3. Install (replace userN-dev with your actual namespace)
helm install parksmap ./ -f values-dev.yaml -n userN-dev

# 4. Watch the pods come up
oc get pods -n userN-dev -w

# 5. Get the application URL
oc get routes -n userN-dev
```

### Deploy to SIT

> Remember: fix the `values-sit.yaml` digest issue before running this!

```bash
cd /projects/ocp-deployment-workshop/02-production-readiness

# 1. Open values-sit.yaml and uncomment the digest lines (comment out tag: latest)
# 2. Validate
helm lint ./

# 3. Preview
helm template parksmap ./ -f values-sit.yaml

# 4. Install (replace userN-sit with your actual namespace)
helm install parksmap ./ -f values-sit.yaml -n userN-sit

# 5. Watch the pods
oc get pods -n userN-sit -w

# 6. Get the URL
oc get routes -n userN-sit
```

### Making Changes and Upgrading

After editing any template or values file:

```bash
# Preview changes
helm template parksmap ./ -f values-dev.yaml

# Apply changes to a running release
helm upgrade parksmap ./ -f values-dev.yaml -n userN-dev
```

### Cleaning Up

```bash
# Remove the DEV release
helm uninstall parksmap -n userN-dev

# Remove the SIT release
helm uninstall parksmap -n userN-sit
```

---

## Troubleshooting Common Issues

### Pods are stuck in `Pending`

```bash
oc get events -n userN-dev --sort-by='.lastTimestamp'
oc describe pod <pod-name> -n userN-dev
```

Common causes: insufficient quota, missing PersistentVolume, image pull secret missing.

### Pods are in `CrashLoopBackOff`

```bash
oc logs <pod-name> -n userN-dev
oc logs <pod-name> -n userN-dev --previous
```

Common causes: wrong environment variable, failed database connection, misconfigured health probe path.

### `helm install` fails with "release already exists"

```bash
# Option 1: Upgrade instead
helm upgrade parksmap ./ -f values-dev.yaml -n userN-dev

# Option 2: Uninstall and reinstall
helm uninstall parksmap -n userN-dev
helm install parksmap ./ -f values-dev.yaml -n userN-dev

# Option 3: Use upgrade --install (handles both cases)
helm upgrade --install parksmap ./ -f values-dev.yaml -n userN-dev
```

### ACS blocks deployment in SIT (`admission webhook denied`)

Open `02-production-readiness/values-sit.yaml` and for **each image block**, comment out `tag: latest` and uncomment the corresponding `digest: sha256:...` line. Then re-run `helm upgrade`.

### Route exists but application returns 503

The service has no healthy pods behind it. Check:

```bash
oc get endpoints -n userN-sit
oc get pods -n userN-sit
oc describe pod <pod-name> -n userN-sit
```

### Image pull errors (`ErrImagePull` / `ImagePullBackOff`)

```bash
oc describe pod <pod-name> -n userN-dev
```

Look at the `Events` section. Common causes: wrong repository URL, private registry without pull secret, or a `tag: latest` being blocked by ACS in SIT.

---

## Repository Structure

```
ocp-deployment-workshop/
├── devfile.yaml                     # Dev Spaces workspace definition
├── README.md                        # This file
├── 01-helm-foundations/             # Part 1 — build a chart from scratch
│   ├── Chart.yaml
│   ├── values.yaml                  # Base default values
│   ├── values-dev.yaml              # DEV environment overrides
│   └── templates/                   # Kubernetes resource templates
├── 02-production-readiness/         # Part 2 — fix a broken chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-sit.yaml              # SIT environment overrides (fix the digests!)
│   └── templates/
├── solutions/                       # Reference solutions — try first before looking!
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-dev.yaml
│   ├── values-sit.yaml
│   └── templates/
└── bonus-compose-migration/         # Bonus — translate docker-compose to Helm
    ├── docker-compose.yaml
    └── README.md
```

---

## Solutions

If you get completely stuck, the `solutions/` folder contains a fully working chart with correct values files. Try to solve each exercise using the hints in each section's README before peeking at the solutions.

---

## Tips for a Smooth Workshop

- **Always `helm template` before `helm install`.** Catching YAML errors locally saves time.
- **Check events first when something breaks:** `oc get events -n <namespace> --sort-by='.lastTimestamp'`
- **Use `helm upgrade --install`** to avoid the "release already exists" error when re-running commands.
- **In SIT, `latest` tags will always be blocked.** Use digests — they are pre-filled in `values-sit.yaml`, just uncomment them.
- **Each values file layered on top of the previous one.** `-f values-dev.yaml` means `values-dev.yaml` overrides `values.yaml`.
- **Your namespace is your sandbox.** You will not affect other users' deployments.

---

*Workshop maintained by the Red Hat OpenShift Workshop Team. Repository: [https://github.com/betterthanbot/ocp-deployment-workshop](https://github.com/betterthanbot/ocp-deployment-workshop)*