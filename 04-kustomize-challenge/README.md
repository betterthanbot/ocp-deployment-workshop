# Challenge 04 — Kustomize Base + Overlay

This challenge introduces a simple Kustomize workflow on OpenShift:
- Deploy a web app from a reusable `base`
- Apply an environment-specific `overlay` (staging, then prod)
- Watch the app update when switching overlays

## Learning Goal

Use Kustomize to separate common manifests from environment overrides, then redeploy quickly by changing only one overlay value.

## Folder Structure

```text
04-kustomize-challenge/
├── base/
│   ├── deployment.yaml
│   ├── kustomization.yaml
│   ├── route.yaml
│   └── service.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    ├── staging/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
```

## Step 1 — Deploy with STAGING overlay

```bash
cd /projects/ocp-deployment-workshop/04-kustomize-challenge
oc project userN-dev
oc apply -k overlays/staging
```

Verify:

```bash
oc get pods,svc,routes -n userN-dev
```

Open the Route:

```bash
oc get route kustom-web -n userN-dev -o jsonpath='https://{.spec.host}{"\n"}'
```

You should see a message showing **STAGING** environment.

## Step 2 — Switch to PROD overlay

Now apply the production overlay:

```bash
oc apply -k overlays/prod
oc rollout status deployment/kustom-web -n userN-dev
```

Refresh the same route page. The message should now show **PRODUCTION** environment.

## Optional — Customize your own environment message

Edit either `overlays/staging/kustomization.yaml` or `overlays/prod/kustomization.yaml`, change `APP_MESSAGE`, and re-apply that overlay.

## Why this works

Each overlay uses `configMapGenerator` with a hashed name. When overlay content changes, the generated ConfigMap name changes, Kustomize updates the Deployment reference, and OpenShift rolls out a new pod automatically.
