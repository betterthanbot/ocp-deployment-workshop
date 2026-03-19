# Part 1: Helm Foundations

## Your story so far

You just joined the ParksMap team as a developer. Yesterday, you went through the OpenShift basics class and deployed the ParksMap application using the web console (clickops). Today, your tech lead wants you to do the same thing, but properly -- using a Helm chart so the deployment is repeatable, version-controlled, and environment-aware.

The previous developer left behind a half-finished Helm chart. Some template files have gaps that need filling, and several files are missing entirely. Your job is to complete the chart and successfully deploy the full ParksMap stack to your dev namespace.

The ParksMap application has three components:

| Component | Name | What it does |
|-----------|------|-------------|
| Frontend | parksmap | A Spring Boot web UI that shows a map of national parks |
| Backend | nationalparks | A REST API that serves park data from MongoDB |
| Database | mongodb | Stores park location data |

The frontend discovers backends automatically by looking for Services with the label `type: parksmap-backend`. This is why RBAC is needed -- the frontend's service account must have `view` permission to list Services in the namespace.

---

## Before you begin

1. Open your DevSpaces workspace (it should already be running from the repo URL your instructor shared).
2. Open a terminal inside DevSpaces.
3. Confirm your tools are available:

```bash
helm version
oc version
oc whoami
```

4. Check which namespaces you have access to:

```bash
oc projects
```

You should see two namespaces assigned to you (for example, `user5-dev` and `user5-sit`). Write down your namespace names -- you will need them later.

5. Navigate to the exercise folder:

```bash
cd 01-helm-foundations
```

Take a few minutes to explore the files. Look at `Chart.yaml`, `values.yaml`, and the `templates/` folder. Notice that some template files have `# TODO` comments, and some files that you would expect (like `frontend-service.yaml`) do not exist yet.

---

## Exercise 1: Understand the chart structure

**Objective**: Get familiar with how a Helm chart is organized and what each file does.

**Context**: A Helm chart is a directory with a specific structure. At minimum, it needs a `Chart.yaml` (metadata) and a `templates/` directory (Kubernetes manifests with Go template syntax). The `values.yaml` file provides default configuration that templates can reference.

**Your task**:

1. Read through `Chart.yaml`. What is the chart name? What version is it?
2. Open `values.yaml` and find the frontend image repository and tag.
3. Open `templates/_helpers.tpl` and find the template named `parksmap.frontend.image`. What does it produce?
4. Run `helm template` to see the rendered output (it will have errors because of the TODOs, but that is expected):

```bash
helm template parksmap ./ 2>&1 | head -50
```

5. Run `helm lint` to see what issues the chart has:

```bash
helm lint ./
```

Note down the errors. You will fix them in the following exercises.

---

## Exercise 2: Complete the Frontend Deployment

**Objective**: Fill in the missing fields in `templates/frontend-deploy.yaml`.

**Context**: A Deployment tells Kubernetes how to run your container. It needs to know which container image to use, what ports the container listens on, and how many resources to allocate. In Helm, we pull these values from `values.yaml` rather than hardcoding them, so the same chart can be reused across environments.

**Your task**: Open `templates/frontend-deploy.yaml` and complete the four `# TODO` items:

1. Set the container image using the `parksmap.frontend.image` helper template
2. Set `imagePullPolicy` from values
3. Add the container port
4. Add resource requests and limits

After you finish, run `helm template parksmap ./ 2>&1 | grep -A 20 "kind: Deployment" | head -40` to check your work.

<details>
<summary>Nudge</summary>

Look at how `_helpers.tpl` defines image helpers. The syntax to call a named template inside another template is `{{ include "template.name" . }}`. For simple values like `imagePullPolicy`, you reference them directly with `{{ .Values.frontend.image.pullPolicy }}`.

</details>

<details>
<summary>Stronger hint</summary>

The four lines you need to add are:
- `image: {{ include "parksmap.frontend.image" . }}`
- `imagePullPolicy: {{ .Values.frontend.image.pullPolicy }}`
- A port block with `containerPort: {{ .Values.frontend.port }}`
- A resources block using `toYaml` to convert the values to YAML

For the resources block, look at how it is done in the backend deployment skeleton -- the `toYaml` line is already there as an example.

</details>

<details>
<summary>Solution</summary>

Replace the TODO section in `frontend-deploy.yaml` with:

```yaml
      containers:
        - name: parksmap
          image: {{ include "parksmap.frontend.image" . }}
          imagePullPolicy: {{ .Values.frontend.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.frontend.port }}
              protocol: TCP
          resources:
            {{- toYaml .Values.frontend.resources | nindent 12 }}
```

</details>

---

## Exercise 3: Create the Frontend Service

**Objective**: Create `templates/frontend-service.yaml` from scratch.

**Context**: A Service provides a stable network identity for a set of pods. Without a Service, other components (and Routes) have no way to reach your frontend pods. The Service uses label selectors to find which pods to send traffic to.

**Your task**: Create a new file `templates/frontend-service.yaml` that:

1. Is an `apiVersion: v1` `kind: Service`
2. Has `name: parksmap` and the correct namespace (use the namespace helper)
3. Includes the frontend labels (use the labels helper)
4. Uses `type: ClusterIP`
5. Has a selector that matches frontend pods (use the selector labels helper)
6. Exposes port 8080 (name it `8080-tcp`, use values for port and targetPort)

<details>
<summary>Nudge</summary>

Look at the backend service skeleton (`backend-service.yaml`) for the general structure. Your frontend service is simpler because there are no extra ports to iterate over.

</details>

<details>
<summary>Stronger hint</summary>

The structure is:
- metadata: name, namespace (use `include "parksmap.namespace" .`), labels (use `include "parksmap.frontend.labels" .`)
- spec: type ClusterIP, selector (use `include "parksmap.frontend.selectorLabels" .`), ports with name/port/targetPort/protocol

</details>

<details>
<summary>Solution</summary>

Create `templates/frontend-service.yaml` with this content:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: parksmap
  namespace: {{ include "parksmap.namespace" . }}
  labels:
    {{- include "parksmap.frontend.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "parksmap.frontend.selectorLabels" . | nindent 4 }}
  ports:
    - name: 8080-tcp
      port: {{ .Values.frontend.port }}
      targetPort: {{ .Values.frontend.port }}
      protocol: TCP
```

</details>

---

## Exercise 4: Create the Frontend Route

**Objective**: Create `templates/frontend-route.yaml` from scratch.

**Context**: In OpenShift, a Route exposes a Service to external traffic via a hostname. This is an OpenShift-specific resource (it does not exist in vanilla Kubernetes, which uses Ingress instead). Routes can also handle TLS termination at the edge, meaning the router handles HTTPS and forwards plain HTTP to your pods.

**Your task**: Create `templates/frontend-route.yaml` that:

1. Is conditionally created only when `frontend.route.enabled` is true (wrap the whole file in an `if` block)
2. Uses `apiVersion: route.openshift.io/v1` and `kind: Route`
3. Has `name: parksmap` in the correct namespace with frontend labels
4. Optionally sets a custom hostname from values (only if `frontend.route.host` is not empty)
5. Sets `targetPort: 8080-tcp` and routes to the `parksmap` Service with weight 100
6. Configures TLS termination and (optionally) insecureEdgeTerminationPolicy from values

<details>
<summary>Nudge</summary>

Look at the backend route skeleton (`backend-route.yaml`) for the pattern. The frontend route follows the exact same structure, just with frontend values and labels instead of backend ones.

</details>

<details>
<summary>Stronger hint</summary>

The conditional wrapping looks like:
```
{{- if .Values.frontend.route.enabled }}
... your Route YAML ...
{{- end }}
```

For the optional host field:
```
{{- if .Values.frontend.route.host }}
host: {{ .Values.frontend.route.host }}
{{- end }}
```

</details>

<details>
<summary>Solution</summary>

Create `templates/frontend-route.yaml` with this content:

```yaml
{{- if .Values.frontend.route.enabled }}
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: parksmap
  namespace: {{ include "parksmap.namespace" . }}
  labels:
    {{- include "parksmap.frontend.labels" . | nindent 4 }}
spec:
  {{- if .Values.frontend.route.host }}
  host: {{ .Values.frontend.route.host }}
  {{- end }}
  port:
    targetPort: 8080-tcp
  to:
    kind: Service
    name: parksmap
    weight: 100
  wildcardPolicy: None
  tls:
    termination: {{ .Values.frontend.route.tls.termination }}
    {{- if .Values.frontend.route.tls.insecureEdgeTerminationPolicy }}
    insecureEdgeTerminationPolicy: {{ .Values.frontend.route.tls.insecureEdgeTerminationPolicy }}
    {{- end }}
{{- end }}
```

</details>

---

## Exercise 5: Complete the Backend Deployment

**Objective**: Fill in the environment variables and health probes in `templates/backend-deploy.yaml`.

**Context**: The nationalparks backend is a Spring Boot application that connects to MongoDB. It needs several environment variables to know where the database is and how to authenticate. It also exposes a health endpoint that Kubernetes uses to determine if the pod is alive (liveness) and ready to serve traffic (readiness). Without proper probes, Kubernetes cannot detect and recover from application failures.

**Your task**: Open `templates/backend-deploy.yaml` and complete all the `# TODO` items:

1. Add the `APPNAME` env var using `.Values.backend.appName` (with a default fallback and quote function)
2. Add `MONGODB_SERVER_HOST` and `MONGODB_DATABASE` env vars from values
3. Add `MONGODB_USER` and `MONGODB_PASSWORD` env vars from the `mongodb-credentials` Secret
4. Add liveness and readiness probes using HTTP GET checks

<details>
<summary>Nudge</summary>

For env vars that come from values, the pattern is:
```yaml
- name: VAR_NAME
  value: {{ .Values.some.path | quote }}
```

For env vars that come from a Secret:
```yaml
- name: VAR_NAME
  valueFrom:
    secretKeyRef:
      name: secret-name
      key: key-name
```

For health probes, look up the Kubernetes documentation for `httpGet` liveness probes.

</details>

<details>
<summary>Stronger hint</summary>

The `APPNAME` line should use the `default` function:
```yaml
value: {{ .Values.backend.appName | default "National Parks" | quote }}
```

The health probe structure is:
```yaml
livenessProbe:
  httpGet:
    path: <health path from values>
    port: <port from values>
    scheme: HTTP
  periodSeconds: 10
  failureThreshold: 3
  timeoutSeconds: 1
```

The readiness probe has the identical structure.

</details>

<details>
<summary>Solution</summary>

Replace the TODO sections in `backend-deploy.yaml`:

**Environment variables:**
```yaml
          env:
            - name: APPNAME
              value: {{ .Values.backend.appName | default "National Parks" | quote }}
            - name: MONGODB_SERVER_HOST
              value: {{ .Values.database.host | quote }}
            - name: MONGODB_DATABASE
              value: {{ .Values.database.dbName | quote }}
            - name: MONGODB_USER
              valueFrom:
                secretKeyRef:
                  name: mongodb-credentials
                  key: app-usr
            - name: MONGODB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mongodb-credentials
                  key: app-pwd
```

**Health probes:**
```yaml
          livenessProbe:
            httpGet:
              path: {{ .Values.backend.healthPath }}
              port: {{ .Values.backend.port }}
              scheme: HTTP
            periodSeconds: 10
            failureThreshold: 3
            timeoutSeconds: 1
          readinessProbe:
            httpGet:
              path: {{ .Values.backend.healthPath }}
              port: {{ .Values.backend.port }}
              scheme: HTTP
            periodSeconds: 10
            failureThreshold: 3
            timeoutSeconds: 1
```

</details>

---

## Exercise 6: Complete the Backend Service and Route

**Objective**: Fill in the blanks in `templates/backend-service.yaml` and `templates/backend-route.yaml`.

**Context**: The backend service is special -- it needs a `type: parksmap-backend` label so the frontend can discover it automatically. The Route exposes the backend API externally (useful for the data load endpoint and for debugging).

**Your task**:

**In `backend-service.yaml`**:
1. Add the `type: parksmap-backend` label
2. Fill in the selector using the backend selector labels helper
3. Add the primary port (8080-tcp) and the extra ports loop

**In `backend-route.yaml`**:
1. Set the TLS termination from values
2. Conditionally set the insecureEdgeTerminationPolicy

<details>
<summary>Nudge</summary>

For the service: the `type: parksmap-backend` label goes under the labels section in metadata, after the helper labels. For the extra ports, look at how the backend deployment template iterates over `extraPorts` with `range`.

For the route: the TLS fields are straightforward value references.

</details>

<details>
<summary>Stronger hint</summary>

**backend-service.yaml selector:**
```yaml
  selector:
    {{- include "parksmap.backend.selectorLabels" . | nindent 4 }}
```

**backend-service.yaml ports:**
```yaml
  ports:
    - name: 8080-tcp
      port: {{ .Values.backend.port }}
      targetPort: {{ .Values.backend.port }}
      protocol: TCP
    {{- range .Values.backend.extraPorts }}
    - name: {{ printf "%d-tcp" (.containerPort | int) }}
      port: {{ .containerPort }}
      targetPort: {{ .containerPort }}
      protocol: TCP
    {{- end }}
```

</details>

<details>
<summary>Solution</summary>

**backend-service.yaml:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nationalparks
  namespace: {{ include "parksmap.namespace" . }}
  labels:
    {{- include "parksmap.backend.labels" . | nindent 4 }}
    type: parksmap-backend
spec:
  type: ClusterIP
  selector:
    {{- include "parksmap.backend.selectorLabels" . | nindent 4 }}
  ports:
    - name: 8080-tcp
      port: {{ .Values.backend.port }}
      targetPort: {{ .Values.backend.port }}
      protocol: TCP
    {{- range .Values.backend.extraPorts }}
    - name: {{ printf "%d-tcp" (.containerPort | int) }}
      port: {{ .containerPort }}
      targetPort: {{ .containerPort }}
      protocol: TCP
    {{- end }}
```

**backend-route.yaml:**
```yaml
{{- if .Values.backend.route.enabled }}
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: nationalparks
  namespace: {{ include "parksmap.namespace" . }}
  labels:
    {{- include "parksmap.backend.labels" . | nindent 4 }}
    type: parksmap-backend
spec:
  {{- if .Values.backend.route.host }}
  host: {{ .Values.backend.route.host }}
  {{- end }}
  port:
    targetPort: 8080-tcp
  to:
    kind: Service
    name: nationalparks
    weight: 100
  wildcardPolicy: None
  tls:
    termination: {{ .Values.backend.route.tls.termination }}
    {{- if .Values.backend.route.tls.insecureEdgeTerminationPolicy }}
    insecureEdgeTerminationPolicy: {{ .Values.backend.route.tls.insecureEdgeTerminationPolicy }}
    {{- end }}
{{- end }}
```

</details>

---

## Exercise 7: Create the Database Secret

**Objective**: Create `templates/database-secret.yaml` from scratch.

**Context**: Kubernetes Secrets store sensitive data like passwords, tokens, and keys. Instead of hardcoding credentials in your Deployment, you store them in a Secret and reference them via environment variables. This keeps credentials out of your container image and makes it possible to change them without rebuilding.

In this chart, we use `stringData` (plain text that Kubernetes automatically base64-encodes) instead of `data` (which requires you to base64-encode values yourself). This is simpler for a workshop setting, though in production you would typically use an external secret manager.

**Your task**: Create `templates/database-secret.yaml` that:

1. Is an `apiVersion: v1` `kind: Secret`
2. Has `name: mongodb-credentials` in the correct namespace with database labels
3. Uses `type: Opaque`
4. Contains four entries under `stringData`:
   - `admin-usr` from `.Values.database.credentials.adminUser`
   - `admin-pwd` from `.Values.database.credentials.adminPassword`
   - `app-usr` from `.Values.database.credentials.appUser`
   - `app-pwd` from `.Values.database.credentials.appPassword`
5. Wraps each value with the `quote` function

<details>
<summary>Nudge</summary>

A Secret looks similar to a ConfigMap but uses either `data` (base64) or `stringData` (plain text). The structure is:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ...
  namespace: ...
type: Opaque
stringData:
  key-name: "value"
```

</details>

<details>
<summary>Stronger hint</summary>

The stringData entries follow this pattern:
```yaml
stringData:
  admin-usr: {{ .Values.database.credentials.adminUser | quote }}
```

</details>

<details>
<summary>Solution</summary>

Create `templates/database-secret.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-credentials
  namespace: {{ include "parksmap.namespace" . }}
  labels:
    {{- include "parksmap.database.labels" . | nindent 4 }}
type: Opaque
stringData:
  admin-usr: {{ .Values.database.credentials.adminUser | quote }}
  admin-pwd: {{ .Values.database.credentials.adminPassword | quote }}
  app-usr: {{ .Values.database.credentials.appUser | quote }}
  app-pwd: {{ .Values.database.credentials.appPassword | quote }}
```

</details>

---

## Exercise 8: Complete the Database Deployment

**Objective**: Fill in the environment variables, volume mounts, and volume definitions in `templates/database-deploy.yaml`.

**Context**: MongoDB needs two things: credentials (passed as environment variables from the Secret you just created) and storage (directories for data and configuration). For this workshop, we use `emptyDir` volumes -- which means data is lost when the pod restarts. In a real deployment, you would use a PersistentVolumeClaim (PVC) for the data directory. The template already has a conditional block for this, and you will implement both paths.

**Your task**: Complete the `# TODO` items in `database-deploy.yaml`:

1. Add `MONGO_INITDB_ROOT_USERNAME` and `MONGO_INITDB_ROOT_PASSWORD` env vars from the Secret
2. Add volume mounts for `/data/configdb` and `/data/db`
3. Add the volumes section with conditional persistence logic

<details>
<summary>Nudge</summary>

The env var pattern for reading from a Secret is the same one you used in the backend deployment (Exercise 5). The secret name is `mongodb-credentials` and the keys are `admin-usr` and `admin-pwd`.

For volume mounts, the pattern is:
```yaml
volumeMounts:
  - name: volume-name
    mountPath: /some/path
```

For the volumes section, you need an if/else block based on `.Values.database.persistence.enabled`.

</details>

<details>
<summary>Stronger hint</summary>

Volume mounts:
```yaml
volumeMounts:
  - name: mongodb-configdb
    mountPath: /data/configdb
  - name: mongodb-data
    mountPath: /data/db
```

The volumes conditional block:
```yaml
volumes:
  {{- if .Values.database.persistence.enabled }}
  - name: mongodb-configdb
    emptyDir: {}
  - name: mongodb-data
    persistentVolumeClaim:
      claimName: mongodb-data
  {{- else }}
  - name: mongodb-configdb
    emptyDir: {}
  - name: mongodb-data
    emptyDir: {}
  {{- end }}
```

</details>

<details>
<summary>Solution</summary>

Replace the TODO sections in `database-deploy.yaml`:

**Environment variables:**
```yaml
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

**Volume mounts:**
```yaml
          volumeMounts:
            - name: mongodb-configdb
              mountPath: /data/configdb
            - name: mongodb-data
              mountPath: /data/db
```

**Volumes:**
```yaml
      volumes:
        {{- if .Values.database.persistence.enabled }}
        - name: mongodb-configdb
          emptyDir: {}
        - name: mongodb-data
          persistentVolumeClaim:
            claimName: mongodb-data
        {{- else }}
        - name: mongodb-configdb
          emptyDir: {}
        - name: mongodb-data
          emptyDir: {}
        {{- end }}
```

</details>

---

## Exercise 9: Create the Database Service

**Objective**: Create `templates/database-service.yaml` from scratch.

**Context**: The backend application connects to MongoDB using the hostname `mongodb` (configured via the `MONGODB_SERVER_HOST` env var). For this to work, there must be a Service named `mongodb` in the same namespace. Kubernetes DNS resolves the service name to the ClusterIP, which routes traffic to the MongoDB pod.

**Your task**: Create a Service for MongoDB that:

1. Is named `mongodb` with the correct namespace and database labels
2. Uses `type: ClusterIP`
3. Selects pods using the database selector labels helper
4. Exposes port 27017 (name it `mongodb`)

<details>
<summary>Nudge</summary>

This is very similar to the frontend service you created in Exercise 3. The main differences are the name, labels, selector, and port number.

</details>

<details>
<summary>Stronger hint</summary>

Use `include "parksmap.database.labels"` for labels and `include "parksmap.database.selectorLabels"` for the selector. The port comes from `.Values.database.port`.

</details>

<details>
<summary>Solution</summary>

Create `templates/database-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mongodb
  namespace: {{ include "parksmap.namespace" . }}
  labels:
    {{- include "parksmap.database.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "parksmap.database.selectorLabels" . | nindent 4 }}
  ports:
    - name: mongodb
      port: {{ .Values.database.port }}
      targetPort: {{ .Values.database.port }}
      protocol: TCP
```

</details>

---

## Exercise 10: Create the RoleBinding

**Objective**: Create `templates/rolebinding.yaml` from scratch.

**Context**: The parksmap frontend needs to call the Kubernetes API to list Services in the namespace. It looks for Services labelled `type: parksmap-backend` and adds them as map data sources. By default, a pod's service account has no permissions to do this. We need to grant it the `view` ClusterRole via a RoleBinding.

Without this RoleBinding, the frontend will start up but the map will be empty because it cannot discover the backend service.

**Your task**: Create a RoleBinding that:

1. Is conditionally created only when `rolebinding.enabled` is true
2. Grants the `view` ClusterRole to the `default` ServiceAccount
3. Is named `view` in the correct namespace with common labels

<details>
<summary>Nudge</summary>

A RoleBinding has three parts: metadata, a `roleRef` (which ClusterRole to grant), and `subjects` (who gets the permission). The `roleRef` always uses `apiGroup: rbac.authorization.k8s.io` and `kind: ClusterRole`.

</details>

<details>
<summary>Stronger hint</summary>

The subjects section binds the `default` ServiceAccount in the current namespace:
```yaml
subjects:
  - kind: ServiceAccount
    name: default
    namespace: {{ include "parksmap.namespace" . }}
```

</details>

<details>
<summary>Solution</summary>

Create `templates/rolebinding.yaml`:

```yaml
{{- if .Values.rolebinding.enabled }}
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: view
  namespace: {{ include "parksmap.namespace" . }}
  labels:
    {{- include "parksmap.labels" . | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
  - kind: ServiceAccount
    name: default
    namespace: {{ include "parksmap.namespace" . }}
{{- end }}
```

</details>

---

## Checkpoint: Validate your chart

Before deploying, make sure your chart is valid:

```bash
helm lint ./
```

You should see: `1 chart(s) linted, 0 chart(s) failed`

Now render the templates to inspect the output:

```bash
helm template parksmap ./ -f values-dev.yaml
```

Review the output. Every resource should have valid YAML with no TODO comments remaining. If you see errors, go back and fix the relevant exercise.

---

## Exercise 11: Deploy to your Dev namespace

**Objective**: Deploy the completed chart to your dev namespace and validate that all components are running.

**Context**: This is the moment of truth. You will use `helm install` to deploy the chart, using `values-dev.yaml` for dev-specific configuration. Notice that `values-dev.yaml` sets `namespace: userx-dev`. This is a placeholder -- you need to override it with your actual namespace.

**Your task**:

1. Install the chart to your dev namespace. Replace `<your-dev-namespace>` with your actual namespace name (e.g., `user5-dev`):

```bash
helm install parksmap ./ \
  --namespace <your-dev-namespace> \
  -f values-dev.yaml \
  --set namespace=<your-dev-namespace>
```

2. Check that all pods are running:

```bash
oc get pods -n <your-dev-namespace>
```

You should see three pods (parksmap, nationalparks, mongodb) all in `Running` state. Wait a minute or two if they are still starting.

3. Check the Routes:

```bash
oc get routes -n <your-dev-namespace>
```

4. Open the frontend Route URL in your browser. You should see a map, but it will be empty.

5. Load the park data by visiting the backend Route URL with `/ws/data/load` appended. You can find the backend route URL from the output of `oc get routes`:

```bash
# Get the backend route URL
oc get route nationalparks -n <your-dev-namespace> -o jsonpath='{.spec.host}'
```

Visit: `https://<backend-route-host>/ws/data/load`

You should see: `Items inserted in database: 2893`

6. Go back to the frontend map. Refresh the page. You should now see national parks plotted on the map. Notice the legend -- it should say "National Parks (DEV)".

<details>
<summary>Troubleshooting: Pods not starting</summary>

Check pod status for details:
```bash
oc describe pod <pod-name> -n <your-dev-namespace>
```

Common issues:
- **ImagePullBackOff**: The image tag or repository is wrong. Check your values.
- **CrashLoopBackOff**: The container starts but crashes. Check logs with `oc logs <pod-name>`.
- **Pending**: No resources available or the namespace does not exist. Check your namespace name.

</details>

<details>
<summary>Troubleshooting: Map is empty after loading data</summary>

Check that the RoleBinding exists:
```bash
oc get rolebinding view -n <your-dev-namespace>
```

Check that the backend service has the discovery label:
```bash
oc get svc nationalparks -n <your-dev-namespace> --show-labels
```

Look for `type=parksmap-backend` in the labels. If it is missing, check your `backend-service.yaml`.

</details>

---

## Exercise 12: Deploy to your SIT namespace

**Objective**: Deploy the same chart with different configuration to your SIT namespace and observe the differences.

**Context**: In a real development workflow, developers push to dev first for rapid testing. Once they are confident that things work, they promote to SIT (System Integration Testing) which uses a more stable, production-like configuration. The same Helm chart is used for both, but the values files define the differences: SIT uses pinned image tags instead of `latest`, runs more replicas for resilience, and enforces stricter resource limits.

**Your task**:

1. Deploy to your SIT namespace using `values-sit.yaml`:

```bash
helm install parksmap ./ \
  --namespace <your-sit-namespace> \
  -f values-sit.yaml \
  --set namespace=<your-sit-namespace>
```

2. Compare the pods in dev and sit:

```bash
echo "=== DEV ==="
oc get pods -n <your-dev-namespace>
echo ""
echo "=== SIT ==="
oc get pods -n <your-sit-namespace>
```

Notice that SIT has **2 replicas** of the frontend and backend, while dev has 1.

3. Load data into the SIT backend (same process as dev):

```bash
oc get route nationalparks -n <your-sit-namespace> -o jsonpath='{.spec.host}'
```

Visit `https://<sit-backend-route>/ws/data/load` in your browser.

4. Open the SIT frontend route in your browser and compare it to the DEV frontend. Notice the legend says "National Parks (SIT)" instead of "National Parks (DEV)".

5. Compare the two deployments side by side to see all the differences:

```bash
echo "=== DEV frontend replicas ==="
oc get deploy parksmap -n <your-dev-namespace> -o jsonpath='{.spec.replicas}'
echo ""
echo "=== SIT frontend replicas ==="
oc get deploy parksmap -n <your-sit-namespace> -o jsonpath='{.spec.replicas}'
echo ""
echo "=== DEV backend image ==="
oc get deploy nationalparks -n <your-dev-namespace> -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""
echo "=== SIT backend image ==="
oc get deploy nationalparks -n <your-sit-namespace> -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**Key takeaway**: The same chart, different values, different behavior. This is the power of Helm -- one chart, many environments.

---

## What you have learned

By completing this section, you now know how to:

- Read and understand a Helm chart structure (Chart.yaml, values.yaml, templates/)
- Use Helm template functions (`include`, `toYaml`, `nindent`, `default`, `quote`, `printf`)
- Create Kubernetes Deployments, Services, Routes, Secrets, and RoleBindings as Helm templates
- Use values files to parameterize your deployment
- Deploy to multiple environments using different values files
- Use `helm install`, `helm template`, and `helm lint`
- Validate your deployment with `oc get pods`, `oc get routes`, and `oc describe`

In the next section, you will learn what can go wrong in a production deployment and how to debug common issues.
