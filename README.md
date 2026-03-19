# parksmap

A Helm chart that deploys the full **ParksMap** workshop application on OpenShift.

The stack consists of three components:

| Component | Resource name | Description |
|---|---|---|
| **Frontend** | `parksmap` | Spring Boot web UI that renders a map of parks |
| **Backend** | `nationalparks` | REST API that serves national parks data |
| **Database** | `mongodb` | MongoDB instance that stores park coordinates |

The frontend auto-discovers backend services by watching for Services labelled `type: parksmap-backend` — this requires the `view` RoleBinding included in the chart.

---

## Prerequisites

- OpenShift 4.x cluster (the chart uses `route.openshift.io/v1` Routes)
- Helm 3.x
- A namespace / project to deploy into

---

## Installing

```bash
# Add/clone the chart, then install into a namespace
helm install parksmap ./parksmap \
  --namespace <your-namespace> \
  --create-namespace
```

### Override credentials at install time (recommended)

```bash
helm install parksmap ./parksmap \
  --namespace <your-namespace> \
  --set database.credentials.adminPassword=<strong-password> \
  --set database.credentials.appPassword=<strong-password>
```

### Using a custom values file

```bash
helm install parksmap ./parksmap \
  --namespace <your-namespace> \
  -f my-values.yaml
```

---

## Post-install steps

After the pods are running you need to seed the database. MongoDB's `app` user is created via `mongosh` inside the database pod, and the park data is loaded via the backend REST endpoint.

### 1 — Create the application database user

```bash
# Exec into the mongodb pod
kubectl exec -it deploy/mongodb -- \
  mongosh -u admin -p <adminPassword> \
    --authenticationDatabase admin \
    --eval 'use parksapp' \
    --eval 'db.createUser({
      user: "parksapp",
      pwd:  "keepsafe",
      roles: [
        { role: "dbAdmin",    db: "parksapp" },
        { role: "readWrite",  db: "parksapp" }
      ]
    })' \
    --quiet
```

### 2 — Load the national parks data

Navigate to the backend Route URL and hit the load endpoint:

```
https://<nationalparks-route>/ws/data/load
```

A successful load returns:

```
Items inserted in database: 2893
```

---

## Upgrading

```bash
helm upgrade parksmap ./parksmap --namespace <your-namespace>
```

## Uninstalling

```bash
helm uninstall parksmap --namespace <your-namespace>
```

---

## Values reference

### Global

| Key | Default | Description |
|---|---|---|
| `global.partOf` | `workshop` | Value for the `app.kubernetes.io/part-of` label on all resources |

### Frontend (`parksmap`)

| Key | Default | Description |
|---|---|---|
| `frontend.replicaCount` | `1` | Number of frontend replicas |
| `frontend.image.repository` | `quay.io/openshift-roadshow/parksmap` | Container image repository |
| `frontend.image.tag` | `latest` | Image tag |
| `frontend.image.pullPolicy` | `Always` | Image pull policy |
| `frontend.port` | `8080` | Container port |
| `frontend.resources.requests.cpu` | `10m` | CPU request |
| `frontend.resources.requests.memory` | `800Mi` | Memory request |
| `frontend.route.enabled` | `true` | Create an OpenShift Route |
| `frontend.route.host` | `""` | Custom hostname (empty = auto-generated) |
| `frontend.route.tls.termination` | `edge` | TLS termination type |

### Backend (`nationalparks`)

| Key | Default | Description |
|---|---|---|
| `backend.replicaCount` | `1` | Number of backend replicas |
| `backend.image.repository` | `quay.io/openshift-roadshow/nationalparks` | Container image repository |
| `backend.image.tag` | `latest` | Image tag |
| `backend.image.pullPolicy` | `Always` | Image pull policy |
| `backend.port` | `8080` | Primary container port |
| `backend.extraPorts` | `[8443, 8778]` | Additional ports (HTTPS, Jolokia) |
| `backend.resources.requests.cpu` | `10m` | CPU request |
| `backend.resources.requests.memory` | `800Mi` | Memory request |
| `backend.healthPath` | `/ws/healthz/` | Path used for liveness and readiness probes |
| `backend.route.enabled` | `true` | Create an OpenShift Route |
| `backend.route.host` | `""` | Custom hostname (empty = auto-generated) |
| `backend.route.tls.termination` | `edge` | TLS termination type |
| `backend.route.tls.insecureEdgeTerminationPolicy` | `Redirect` | HTTP → HTTPS redirect policy |

### Database (`mongodb`)

| Key | Default | Description |
|---|---|---|
| `database.replicaCount` | `1` | Number of MongoDB replicas |
| `database.image.repository` | `quay.io/centos7/mongodb-60-centos7` | Container image repository |
| `database.image.tag` | `6.0.4` | Image tag |
| `database.image.pullPolicy` | `IfNotPresent` | Image pull policy |
| `database.port` | `27017` | MongoDB port |
| `database.host` | `mongodb` | Hostname used by the backend (matches the Service name) |
| `database.dbName` | `parksapp` | Database name |
| `database.credentials.adminUser` | `admin` | MongoDB root username |
| `database.credentials.adminPassword` | `secret` | ⚠️ MongoDB root password — **change this** |
| `database.credentials.appUser` | `parksapp` | Application DB username |
| `database.credentials.appPassword` | `keepsafe` | ⚠️ Application DB password — **change this** |
| `database.persistence.enabled` | `false` | Enable a PVC for `/data/db` (emptyDir used when false) |
| `database.persistence.storageClass` | `""` | StorageClass for the PVC |
| `database.persistence.size` | `1Gi` | PVC size |

### RBAC

| Key | Default | Description |
|---|---|---|
| `rolebinding.enabled` | `true` | Grant `view` ClusterRole to the `default` ServiceAccount (required for backend discovery) |

---

## Resource estimates

| Component | CPU request | Memory request |
|---|---|---|
| MongoDB | 20m | 60Mi |
| nationalparks | 10m | 800Mi |
| parksmap | 10m | 800Mi |

---

## Architecture

```
                        ┌─────────────────┐
    Browser ──HTTPS──▶  │   parksmap       │  (Route: edge TLS)
                        │   (frontend)     │
                        └────────┬────────┘
                                 │  Service discovery via
                                 │  label: type=parksmap-backend
                                 ▼
                        ┌─────────────────┐
                        │  nationalparks  │  (Route: edge TLS + redirect)
                        │   (backend)     │
                        └────────┬────────┘
                                 │  MONGODB_SERVER_HOST
                                 ▼
                        ┌─────────────────┐
                        │    mongodb      │  (ClusterIP only)
                        │   (database)    │
                        └─────────────────┘
```
