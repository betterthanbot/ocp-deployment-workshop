# Challenge 04 — Kustomize Base + Overlay

This challenge introduces a simple Kustomize workflow on OpenShift:
- Deploy a web app from a reusable `base`
- Apply an environment-specific `overlay` (staging, then production)
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
    └── production/
        └── kustomization.yaml
```

## Step 1 — Deploy with STAGING overlay

```bash
cd /projects/ocp-deployment-workshop/04-kustomize-challenge
oc apply -k overlays/staging
```

Verify:

```bash
oc get pods,svc,routes -n challenge4-staging
```

Open the Route:

```bash
oc get route kustom-web -n challenge4-staging -o jsonpath='https://{.spec.host}{"\n"}'
```

You should see a message showing **STAGING** environment.

## Step 2 — Switch to PRODUCTION overlay

Now apply the production overlay:

```bash
oc apply -k overlays/production
oc rollout status deployment/kustom-web -n challenge4-production
```

Get the production route URL:

```bash
oc get route kustom-web -n challenge4-production -o jsonpath='https://{.spec.host}{"\n"}'
```

Open the production URL. The dashboard should now show **PRODUCTION** environment.

## Optional — Customize your own environment message

Edit either `overlays/staging/kustomization.yaml` or `overlays/production/kustomization.yaml`, change `APP_MESSAGE` or `APP_SUBTITLE`, and re-apply that overlay.

## Why this works

Each overlay uses `configMapGenerator` with a hashed name. When overlay content changes, the generated ConfigMap name changes, Kustomize updates the Deployment reference, and OpenShift rolls out a new pod automatically.
