# Bonus: Docker Compose to Helm Migration

This section is optional and should be attempted only if you finish Parts 1 and 2 with time remaining.

## Context

Many teams run their applications on VMs using Docker Compose. When migrating to OpenShift, one common question is: "How do I convert my docker-compose.yaml into a Helm chart?"

There is no one-click converter that does this perfectly, but there is a clear mental model for mapping Compose concepts to Kubernetes resources. In this section, you will look at a Docker Compose file for the same ParksMap stack and see how each section translates to the Helm chart you just built.

---

## The docker-compose.yaml

Open `docker-compose.yaml` in this folder. This is what the ParksMap stack looks like when running on a VM with Docker Compose.

Take a few minutes to read through it. Notice the three services, how they are connected, and how environment variables are passed.

---

## Mapping table

Here is how each Docker Compose concept maps to Kubernetes/Helm:

| Docker Compose | Kubernetes/Helm | Notes |
|---------------|----------------|-------|
| `services:` | One Deployment + one Service per service | Each Compose service becomes a Deployment (for the pods) and a Service (for networking) |
| `image:` | `image:` in the Deployment container spec | Identical concept |
| `ports: "8080:8080"` | Service with `port: 8080` + Route (for external access) | Compose port mapping becomes a Service. For external access, add a Route (OCP) or Ingress (k8s) |
| `environment:` | `env:` in the Deployment container spec | Direct mapping, but secrets should use `valueFrom.secretKeyRef` instead of plain text |
| `volumes:` | `volumeMounts:` + `volumes:` in Deployment, plus a PVC | Compose named volumes become PVCs. Bind mounts do not translate directly |
| `depends_on:` | No direct equivalent | Kubernetes does not have startup ordering. Use readiness probes and init containers instead |
| `networks:` | Not needed | In Kubernetes, all pods in a namespace can reach each other via Service DNS names |
| `restart: always` | Built into Deployments | Kubernetes automatically restarts crashed containers |
| Container name | `metadata.name` on the Service | Other containers connect using the Service name (DNS resolution) |

---

## Walkthrough: Translating each service

### MongoDB (database)

**Compose**:
```yaml
  mongodb:
    image: quay.io/centos7/mongodb-60-centos7:6.0.4
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: secret
    volumes:
      - mongo-data:/data/db
      - mongo-config:/data/configdb
    ports:
      - "27017:27017"
```

**Helm equivalent**: You built this in Part 1 across three files:

- `database-deploy.yaml` (Deployment with the image, env vars from Secret, volume mounts)
- `database-secret.yaml` (Secret for the credentials, instead of plain text env vars)
- `database-service.yaml` (Service for internal DNS resolution, replaces the Docker network)

Key differences from Compose:
- Credentials moved from plain text `environment:` to a Kubernetes Secret
- `volumes:` becomes `emptyDir` or PVC volume definitions within the Deployment
- `ports:` on the Compose service only exposes within the Docker network; in k8s, the Service does this

### nationalparks (backend)

**Compose**:
```yaml
  nationalparks:
    image: quay.io/openshift-roadshow/nationalparks:latest
    environment:
      MONGODB_SERVER_HOST: mongodb
      MONGODB_DATABASE: parksapp
      MONGODB_USER: parksapp
      MONGODB_PASSWORD: keepsafe
    depends_on:
      - mongodb
    ports:
      - "8080:8080"
```

**Helm equivalent**: `backend-deploy.yaml`, `backend-service.yaml`, `backend-route.yaml`

Key differences:
- `depends_on: mongodb` has no k8s equivalent. If MongoDB is not ready when the backend starts, the backend will crash and Kubernetes will restart it (and it will eventually connect)
- `MONGODB_SERVER_HOST: mongodb` works the same way -- the Service name `mongodb` resolves via DNS
- `ports: "8080:8080"` becomes a Service (for internal traffic) and a Route (for external access)

### parksmap (frontend)

**Compose**:
```yaml
  parksmap:
    image: quay.io/openshift-roadshow/parksmap:latest
    depends_on:
      - nationalparks
    ports:
      - "8080:8080"
```

**Helm equivalent**: `frontend-deploy.yaml`, `frontend-service.yaml`, `frontend-route.yaml`

Key differences:
- The frontend does not connect to the backend directly via hostname. Instead, it uses the Kubernetes API to discover services with the `type: parksmap-backend` label. This is why the RoleBinding is needed.
- In Compose, `depends_on` ensures the backend starts first. In k8s, the frontend will start and just show an empty map until the backend is ready and labelled.

---

## Things that Compose does not handle

When migrating from Compose to Helm/Kubernetes, these are things you need to add that Compose does not require:

1. **Health probes** (liveness and readiness): Compose has `healthcheck:` but it is optional and rarely used. In Kubernetes, probes are critical for reliable deployments.

2. **Resource limits**: Compose has `deploy.resources` but many teams skip it. In OpenShift, `ResourceQuota` often makes this mandatory.

3. **Security context**: Compose runs everything as root by default. OpenShift's `restricted-v2` SCC will block this.

4. **Labels and selectors**: Compose uses service names for networking. Kubernetes relies on labels to connect Services to Pods. Getting labels wrong means traffic does not flow.

5. **TLS/Route**: Compose does not handle TLS. In OpenShift, Routes provide edge TLS termination out of the box.

6. **RBAC**: Compose has no concept of permissions. In Kubernetes, service accounts need explicit permissions to call the API.

---

## Exercise: Try it yourself

If you want to practice, try writing a Helm chart from scratch for a different docker-compose.yaml. Take any Compose file you use at work and try mapping it using the table above. Start with the Deployments and Services, then add Routes, Secrets, and probes.

Common pitfalls when migrating:
- Forgetting that Compose service names become Kubernetes Service names (not pod names)
- Hardcoding passwords in env vars instead of using Secrets
- Missing health probes (your app will work but will not recover from failures)
- Missing resource limits (the platform team will reject your deployment)
- Trying to run as root (OCP will block it)
