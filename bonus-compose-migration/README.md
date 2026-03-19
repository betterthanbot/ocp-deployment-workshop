# Bonus: Docker Compose to Helm Migration

This section is optional and should be attempted only if you finish Parts 1 and 2 with time remaining.

## Context

Many teams run their applications on VMs using Docker Compose. When migrating to OpenShift, the most common question is: "I have a working docker-compose.yaml. How do I turn this into a Helm chart?"

There is no automated tool that does this perfectly. But if you understand the mapping between Compose and Kubernetes concepts, the translation is straightforward. This section walks through the conversion step by step using the same ParksMap application you deployed in Parts 1 and 2.

---

## Step 1: Read the docker-compose.yaml

Open `docker-compose.yaml` in this folder. Read through it carefully and identify:

- How many services are defined?
- How do they connect to each other?
- Where are credentials stored?
- How are health checks configured?
- How are resource limits set?

Keep this file open side by side as you work through the rest of this section.

---

## Step 2: The mental model

Every Compose `service:` block becomes multiple Kubernetes resources. This is the biggest shift in thinking when migrating. In Compose, one block handles the container, networking, storage, and configuration. In Kubernetes, each of those concerns is a separate resource.

Here is the mapping:

```
docker-compose service
    |
    +---> Deployment      (runs the container as pods)
    +---> Service         (provides internal DNS name and load balancing)
    +---> Route/Ingress   (exposes to external traffic, if needed)
    +---> Secret          (holds credentials, replaces plain-text env vars)
    +---> PVC             (persistent storage, replaces named volumes)
```

---

## Step 3: Side-by-side comparison

For each component, here is exactly how the Compose definition maps to the Helm chart you built.

### MongoDB

**Docker Compose:**

```yaml
  mongodb:
    image: quay.io/centos7/mongodb-60-centos7:6.0.4
    container_name: mongodb
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: secret
    volumes:
      - mongo-data:/data/db
      - mongo-config:/data/configdb
    ports:
      - "27017:27017"
    restart: always
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
        reservations:
          cpus: "0.1"
          memory: 64M
```

**Kubernetes equivalent (what it becomes in Helm):**

| Compose field | Kubernetes resource | Helm template file | What changed |
|--------------|--------------------|--------------------|-------------|
| `image:` | `containers[0].image` in Deployment | `database-deploy.yaml` | Moved into a Deployment spec. Image and tag are parameterized through `values.yaml` |
| `container_name:` | `metadata.name` on the Deployment | `database-deploy.yaml` | In k8s, the Deployment name identifies the workload. The pod name is auto-generated |
| `environment:` | `env:` with `valueFrom.secretKeyRef` | `database-deploy.yaml` + `database-secret.yaml` | Credentials moved to a Secret resource instead of plain text |
| `volumes:` | `volumeMounts:` + `volumes:` in Deployment | `database-deploy.yaml` | Named volumes become either `emptyDir` or PersistentVolumeClaim references |
| `ports:` | `containerPort:` in Deployment + Service | `database-deploy.yaml` + `database-service.yaml` | Compose port mapping splits into: container port (Deployment) and network exposure (Service) |
| `restart: always` | Built into Deployment controller | n/a | Kubernetes restarts crashed containers automatically. No config needed |
| `healthcheck:` | No equivalent added | n/a | Compose healthcheck is for `depends_on` ordering. In k8s, health checks are on the consumer side (liveness/readiness probes on the backend that connects to MongoDB) |
| `deploy.resources` | `resources.requests` + `resources.limits` | `values.yaml` | `reservations` maps to `requests`, `limits` maps to `limits`. Same concept, different names |

**The credentials transformation in detail:**

In Compose, credentials are plain text in the `environment:` block:

```yaml
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: secret
```

In Kubernetes, they are stored in a Secret and referenced by the Deployment:

```yaml
# database-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-credentials
type: Opaque
stringData:
  admin-usr: "admin"
  admin-pwd: "secret"
```

```yaml
# database-deploy.yaml (env section)
env:
  - name: MONGO_INITDB_ROOT_USERNAME
    valueFrom:
      secretKeyRef:
        name: mongodb-credentials
        key: admin-usr
  - name: MONGO_INITDB_ROOT_PASSWORD
    valueFrom:
      secretKeyRef:
        name: mongodb-credentials
        key: admin-pwd
```

This is more verbose, but it keeps credentials out of the Deployment manifest and allows them to be managed separately.

**The volumes transformation in detail:**

In Compose, named volumes are declared at the bottom of the file and referenced by path:

```yaml
    volumes:
      - mongo-data:/data/db
      - mongo-config:/data/configdb

volumes:
  mongo-data:
  mongo-config:
```

In Kubernetes, the Deployment has both `volumeMounts` (where to mount inside the container) and `volumes` (what to mount):

```yaml
# database-deploy.yaml
          volumeMounts:
            - name: mongodb-data
              mountPath: /data/db
            - name: mongodb-configdb
              mountPath: /data/configdb
      volumes:
        - name: mongodb-data
          emptyDir: {}          # or persistentVolumeClaim for durable storage
        - name: mongodb-configdb
          emptyDir: {}
```

For durable storage (equivalent to Compose named volumes surviving a `docker-compose down`), you would use a PersistentVolumeClaim instead of `emptyDir`.

---

### nationalparks (backend)

**Docker Compose:**

```yaml
  nationalparks:
    image: quay.io/openshift-roadshow/nationalparks:latest
    environment:
      MONGODB_SERVER_HOST: mongodb
      MONGODB_DATABASE: parksapp
      MONGODB_USER: parksapp
      MONGODB_PASSWORD: keepsafe
      APPNAME: "National Parks"
    depends_on:
      mongodb:
        condition: service_healthy
    ports:
      - "8080:8080"
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/ws/healthz/"]
      interval: 10s
      timeout: 5s
      retries: 3
```

**Kubernetes equivalent:**

| Compose field | Kubernetes resource | Helm template file | What changed |
|--------------|--------------------|--------------------|-------------|
| `image:` | `containers[0].image` in Deployment | `backend-deploy.yaml` | Parameterized through `values.yaml` so dev can use `latest` and SIT can use a pinned version |
| `environment:` (non-secret) | `env:` with `value:` | `backend-deploy.yaml` | `MONGODB_SERVER_HOST` and `APPNAME` stay as plain values |
| `environment:` (secret) | `env:` with `valueFrom.secretKeyRef` | `backend-deploy.yaml` | `MONGODB_USER` and `MONGODB_PASSWORD` reference the Secret |
| `depends_on:` | No direct equivalent | n/a | See explanation below |
| `ports:` | Service + Route | `backend-service.yaml` + `backend-route.yaml` | Port 8080 is exposed internally via Service and externally via Route |
| `healthcheck:` | `livenessProbe` + `readinessProbe` | `backend-deploy.yaml` | Compose healthcheck becomes two separate Kubernetes probes |

**The depends_on transformation:**

This is one of the biggest differences between Compose and Kubernetes. In Compose, `depends_on` with `condition: service_healthy` guarantees that MongoDB is healthy before the backend starts.

Kubernetes has no built-in startup ordering. Instead, it relies on:

1. **Crash and restart**: If the backend starts before MongoDB is ready, it will fail to connect and crash. Kubernetes will restart it automatically (with exponential backoff). After a few restarts, MongoDB will be ready and the backend will connect successfully.

2. **Readiness probes**: The backend's readiness probe tells Kubernetes when it is ready to receive traffic. Until the probe passes, no traffic is sent to that pod.

3. **Init containers** (optional): For cases where you absolutely need ordering, you can add an init container that waits for MongoDB to be reachable before the main container starts. This is not needed for ParksMap because the application handles reconnection gracefully.

**The healthcheck transformation:**

Compose:

```yaml
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/ws/healthz/"]
      interval: 10s
      timeout: 5s
      retries: 3
```

Kubernetes (in the Deployment):

```yaml
          livenessProbe:
            httpGet:
              path: /ws/healthz/
              port: 8080
              scheme: HTTP
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /ws/healthz/
              port: 8080
              scheme: HTTP
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
```

Notice that Kubernetes splits this into two probes:
- **Liveness probe**: "Is the container alive?" If this fails, Kubernetes kills and restarts the container. This is roughly equivalent to `restart: always` combined with `healthcheck`.
- **Readiness probe**: "Is the container ready to serve traffic?" If this fails, the Service stops sending traffic to this pod, but the container keeps running. Compose has no equivalent for this.

---

### parksmap (frontend)

**Docker Compose:**

```yaml
  parksmap:
    image: quay.io/openshift-roadshow/parksmap:latest
    depends_on:
      - nationalparks
    ports:
      - "8081:8080"
```

**Kubernetes equivalent:**

| Compose field | Kubernetes resource | Helm template file | What changed |
|--------------|--------------------|--------------------|-------------|
| `image:` | `containers[0].image` in Deployment | `frontend-deploy.yaml` | Parameterized through `values.yaml` |
| `depends_on:` | No equivalent needed | n/a | Frontend shows an empty map until the backend is discovered. No crash |
| `ports: "8081:8080"` | Service (port 8080) + Route | `frontend-service.yaml` + `frontend-route.yaml` | In Compose, the host port remapping (8081:8080) avoids port conflicts. In k8s, each Service has its own ClusterIP, so port conflicts do not happen |

**The networking transformation:**

In Compose, all services share a Docker network, and the service name (`mongodb`, `nationalparks`) acts as the DNS hostname. Port conflicts are handled by remapping to different host ports (the frontend maps to 8081 to avoid clashing with the backend's 8080).

In Kubernetes:
- Each Service gets its own ClusterIP address, so two services can both use port 8080 without conflict.
- Service names resolve via internal DNS (e.g., `nationalparks.user5-dev.svc.cluster.local` or just `nationalparks` within the same namespace).
- External access is handled by Routes (OpenShift) or Ingress (vanilla Kubernetes), which provide unique hostnames instead of port remapping.

**Additional resources not in Compose:**

The ParksMap frontend uses a Kubernetes-specific feature: it discovers backends by querying the Kubernetes API for Services with the label `type: parksmap-backend`. This requires:

- A **RoleBinding** (`rolebinding.yaml`) granting the `default` ServiceAccount permission to list Services
- The `type: parksmap-backend` **label** on the backend Service

Compose has no equivalent because Docker does not have an API that containers query at runtime.

---

## Step 4: The resource limits mapping

Compose and Kubernetes both support resource limits, but the terminology is different:

| Compose (`deploy.resources`) | Kubernetes (`resources`) | Meaning |
|-------|------------|---------|
| `reservations.cpus: "0.1"` | `requests.cpu: 100m` | Minimum guaranteed CPU. Note: Compose uses decimal cores, k8s uses millicores (1 core = 1000m) |
| `reservations.memory: 64M` | `requests.memory: 64Mi` | Minimum guaranteed memory. Compose uses M/G, k8s uses Mi/Gi (mebibytes/gibibytes) |
| `limits.cpus: "0.5"` | `limits.cpu: 500m` | Maximum CPU allowed |
| `limits.memory: 256M` | `limits.memory: 256Mi` | Maximum memory allowed. If exceeded, the container is OOM-killed |

CPU unit conversion: multiply Compose decimal by 1000 to get millicores. `0.1` becomes `100m`, `0.5` becomes `500m`.

Memory unit conversion: `M` in Compose is roughly equivalent to `Mi` in Kubernetes (the difference between megabytes and mebibytes is negligible for practical purposes).

---

## Step 5: What Compose does not cover

When migrating from Compose to Kubernetes/Helm, you need to add things that Compose either does not have or makes optional:

| Concern | Compose | Kubernetes/OCP |
|---------|---------|---------------|
| TLS termination | Not handled (you add nginx/traefik as a reverse proxy) | Routes handle this automatically with `termination: edge` |
| Security context | Runs as root by default, no restrictions | OCP `restricted-v2` SCC requires `runAsNonRoot`, dropping capabilities, seccomp profile |
| RBAC/permissions | No concept of API permissions | ServiceAccounts need explicit RoleBindings to access the k8s API |
| Rolling updates | `docker-compose up -d` replaces containers (brief downtime) | Deployments do zero-downtime rolling updates by default (`maxSurge: 25%`, `maxUnavailable: 25%`) |
| Scaling | `docker-compose up --scale web=3` (limited) | `replicaCount` in values.yaml, or `oc scale` at runtime. Automatic with HPA |
| Config per environment | `.env` files or multiple compose files (`-f`) | Values files per environment (`values-dev.yaml`, `values-sit.yaml`) |
| Service discovery | DNS via Docker network (automatic) | DNS via Services (automatic) + label-based discovery (requires setup) |
| Log aggregation | `docker-compose logs` | `oc logs`, plus cluster-level log aggregation (EFK/Loki) |

---

## Step 6: A mental checklist for migration

When you have a docker-compose.yaml and need to create a Helm chart, work through this checklist for each service:

1. **Create a Deployment** for the container. Pull the `image`, `environment`, and `ports` from the Compose service. Parameterize the image repository and tag through `values.yaml`.

2. **Create a Service** for internal networking. Match the container port. Use the service name from Compose as the Kubernetes Service name so DNS resolution stays the same.

3. **Move secrets to a Secret resource.** Any password, token, or key in the `environment:` block should go into a Kubernetes Secret and be referenced via `secretKeyRef`.

4. **Add health probes.** Convert the Compose `healthcheck` (if present) into a `livenessProbe`. Add a `readinessProbe` with the same check. If there is no healthcheck, add one -- Kubernetes needs probes to manage the pod lifecycle.

5. **Add resource requests and limits.** Convert `deploy.resources` from Compose. If none are set, add them -- OpenShift clusters typically enforce ResourceQuotas.

6. **Add a Route** (if the service needs external access). Any Compose `ports:` mapping that exposes to the host becomes a Route in OpenShift.

7. **Handle storage.** Convert `volumes:` to PVCs for persistent data, or `emptyDir` for temporary data.

8. **Add security context.** Set `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, drop all capabilities, and set the seccomp profile to `RuntimeDefault`.

9. **Handle startup ordering.** Replace `depends_on` with readiness probes and retry logic. Kubernetes will restart crashed containers automatically.

10. **Add labels.** Kubernetes uses labels for everything: Service selectors, pod identity, monitoring, and service discovery.

---

## Exercise: Convert it yourself

If you have time, try this exercise. Take the `docker-compose.yaml` in this folder and convert it into a minimal Helm chart without looking at the `solutions/` folder or the Part 1 exercises.

Create a new folder called `bonus-chart/` and try to produce:

1. `Chart.yaml`
2. `templates/database-deploy.yaml`
3. `templates/database-secret.yaml`
4. `templates/database-service.yaml`
5. `templates/backend-deploy.yaml`
6. `templates/backend-service.yaml`
7. `templates/frontend-deploy.yaml`
8. `templates/frontend-service.yaml`
9. `values.yaml`

You do not need helpers, routes, or the rolebinding for this basic exercise. Focus on getting the three deployments, three services, and one secret right.

<details>
<summary>Nudge</summary>

Start with the database since it has no dependencies. Create the Secret first (for credentials), then the Deployment (which references the Secret), then the Service (which exposes the Deployment).

For each Compose `environment:` entry, decide: is this a secret (password, token)? If yes, put it in a Secret. If no (like `MONGODB_SERVER_HOST`), put it directly in the Deployment's `env:` block as a plain `value:`.

</details>

<details>
<summary>Stronger hint</summary>

The minimal Deployment structure you need:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <service-name>
spec:
  replicas: 1
  selector:
    matchLabels:
      app: <service-name>
  template:
    metadata:
      labels:
        app: <service-name>
    spec:
      containers:
        - name: <service-name>
          image: <image>
          ports:
            - containerPort: <port>
          env:
            - name: KEY
              value: "plain-text-value"
            - name: SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: <secret-name>
                  key: <key>
```

The minimal Service structure:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <service-name>
spec:
  type: ClusterIP
  selector:
    app: <service-name>
  ports:
    - port: <port>
      targetPort: <port>
```

</details>

<details>
<summary>Solution</summary>

Check the `solutions/` folder at the root of the repository for the complete working Helm chart. Compare each template file with the corresponding Compose service block and note how:

- `image:` was parameterized through `values.yaml`
- `environment:` was split into plain `env` and `secretKeyRef`
- `ports:` was split into Deployment `containerPort` and Service `port`
- `volumes:` was converted to `volumeMounts` + `volumes` in the Deployment
- Health probes were added even though not all Compose services had `healthcheck`
- Security context was added to satisfy the `restricted-v2` SCC
- Labels and selectors were added to wire Services to Pods

</details>
