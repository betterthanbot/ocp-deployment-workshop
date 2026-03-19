# Part 2: Production Readiness

## Your story continues

Your tech lead is impressed. You completed the Helm chart and deployed ParksMap to dev. But before the team can ship this to SIT and eventually production, there are several problems that need fixing. A senior engineer reviewed the chart overnight and flagged eight issues ranging from security violations to misconfigurations.

In this section, you will work through a chart that is already complete but deliberately broken. Each exercise presents a real failure you would encounter in an OpenShift environment. Your job is to diagnose the problem, understand why it happens, and fix it.

This is how real production debugging works. You will not always know the answer right away. Before reaching for the hints, try the following approach:

1. **Read the error message carefully.** Kubernetes error messages are verbose, but they contain the answer.
2. **Use debugging commands.** `oc describe pod`, `oc logs`, `oc get events`, `oc get endpoints` are your best friends.
3. **Search online.** If you see an error message you do not recognize, paste it into a search engine. This is what every engineer does.

The hints are there if you get stuck, but try to solve each one on your own first.

---

## Before you begin

1. If you still have the Part 1 releases installed, uninstall them first to start clean:

```bash
helm uninstall parksmap --namespace <your-dev-namespace> 2>/dev/null
helm uninstall parksmap --namespace <your-sit-namespace> 2>/dev/null
```

2. Navigate to the exercise folder:

```bash
cd ../02-production-readiness
```

3. Take a look at the templates and values files. They look complete, but several bugs are hiding in them.

---

## Exercise 1: The namespace that does not exist

**The scenario**: You try to deploy the chart to your dev namespace and it seems to work, but nothing shows up.

Try deploying:

```bash
helm install parksmap ./ \
  --namespace <your-dev-namespace> \
  -f values-dev.yaml
```

Now check what happened:

```bash
oc get pods -n <your-dev-namespace>
```

Nothing? But Helm said the install succeeded. Where did your resources go?

**Your task**: Figure out why the resources are not appearing in your namespace and fix the problem.

<details>
<summary>Debugging steps to try first</summary>

Run `helm template` and look at the namespace field on the rendered resources:

```bash
helm template parksmap ./ -f values-dev.yaml | grep "namespace:"
```

What namespace do you see? Is it the same as the one you passed to `--namespace`?

Now check `values-dev.yaml` and look for a `namespace` key. What value does it have?

</details>

<details>
<summary>Nudge</summary>

The chart has a `namespace` field in `values-dev.yaml` that overrides the `--namespace` flag. Look at the `_helpers.tpl` file to see how the namespace is resolved -- the values file takes precedence over the release namespace. 

Note that `values.yaml` (the base defaults) *also* has `namespace: "userx-dev"`. However, when you run `helm install -f values-dev.yaml`, any settings in `values-dev.yaml` merge with and override the base `values.yaml`. You only need to fix the value in `values-dev.yaml`.

</details>

<details>
<summary>Stronger hint</summary>

Open `values-dev.yaml` and change the `namespace` value from `userx-dev` to your actual namespace (e.g., `user5-dev`).

Alternatively, you can override it at install time:

```bash
helm install parksmap ./ \
  --namespace <your-dev-namespace> \
  -f values-dev.yaml \
  --set namespace=<your-dev-namespace>
```

</details>

<details>
<summary>Solution</summary>

The problem is that `values-dev.yaml` contains `namespace: "userx-dev"`. The `_helpers.tpl` template resolves the namespace like this:

```
{{- .Values.namespace | default .Release.Namespace }}
```

Since `.Values.namespace` is set to `userx-dev`, it takes precedence over the `--namespace` flag. Helm itself installs successfully into your namespace, but all the rendered resources target `userx-dev` -- a namespace that either does not exist or that you do not have access to.

**Fix**: Either edit `values-dev.yaml` to set your actual namespace, or override at install time with `--set namespace=<your-dev-namespace>`.

**Lesson**: Always be careful with hardcoded namespace values in Helm charts. In a CI/CD pipeline, the namespace should come from the pipeline variables, not from a checked-in values file.

After fixing, uninstall and reinstall:

```bash
helm uninstall parksmap --namespace <your-dev-namespace> 2>/dev/null
helm install parksmap ./ \
  --namespace <your-dev-namespace> \
  -f values-dev.yaml \
  --set namespace=<your-dev-namespace>
```

</details>

---

## Exercise 2: SecurityContext and the restricted-v2 SCC

**The scenario**: After fixing the namespace, you check the pods and see they are stuck. They are not starting.

```bash
oc get pods -n <your-dev-namespace>
```

You will likely see pods that cannot be scheduled or are failing with a security-related error.

**Your task**: Find and fix the security context issue in the deployments.

<details>
<summary>Debugging steps to try first</summary>

Check the pod events:

```bash
oc get events -n <your-dev-namespace> --sort-by='.lastTimestamp' | tail -20
```

Describe one of the failing pods:

```bash
oc describe pod -l app=parksmap -n <your-dev-namespace>
```

Look for messages containing "forbidden" or "security" or "SCC".

Also check what SCC is enforced in the namespace:

```bash
oc get pod -l app=parksmap -n <your-dev-namespace> -o yaml | grep -i "scc"
```

</details>

<details>
<summary>Nudge</summary>

OpenShift uses Security Context Constraints (SCCs) to control what a container is allowed to do. The default SCC for most namespaces is `restricted-v2`, which requires that containers:

- Must NOT run as root (`runAsUser: 0` is not allowed)
- Must set `runAsNonRoot: true`
- Must set `allowPrivilegeEscalation: false`
- Must drop all capabilities
- Must use the `RuntimeDefault` seccomp profile

Look at the deployment templates. Do any of them set `runAsUser: 0`?

</details>

<details>
<summary>Stronger hint</summary>

Three deployment templates have `securityContext: runAsUser: 0` set on the container:
- `templates/frontend-deploy.yaml`
- `templates/backend-deploy.yaml`
- `templates/database-deploy.yaml`

You need to either remove the `securityContext` block entirely (letting OCP assign a UID) or replace it with one that satisfies `restricted-v2`.

</details>

<details>
<summary>Solution</summary>

In all three deployment files (`frontend-deploy.yaml`, `backend-deploy.yaml`, `database-deploy.yaml`), find this block inside the container spec:

```yaml
          securityContext:
            runAsUser: 0
```

Replace it with a `restricted-v2` compliant security context:

```yaml
          securityContext:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault
            capabilities:
              drop:
                - ALL
```

Alternatively, you can simply remove the `securityContext` block entirely, and OpenShift will apply the `restricted-v2` defaults automatically. However, it is a best practice to be explicit about your security posture.

After fixing all three files, upgrade the release:

```bash
helm upgrade parksmap ./ \
  --namespace <your-dev-namespace> \
  -f values-dev.yaml \
  --set namespace=<your-dev-namespace>
```

**Lesson**: On OpenShift, the `restricted-v2` SCC is enforced by default. Never set `runAsUser: 0` unless the namespace has been granted a more permissive SCC (which is rare and requires cluster-admin approval). Always test your charts against the default SCC before assuming they will work.

</details>

---

## Exercise 3: Missing resource limits

**The scenario**: Your pods are running now, but the platform team sends you a message: "All containers must have resource limits set. We enforce ResourceQuotas on every namespace."

Check your current resource configuration:

```bash
oc get deploy parksmap -n <your-dev-namespace> -o jsonpath='{.spec.template.spec.containers[0].resources}' | python3 -m json.tool
```

**Your task**: Add resource limits to all containers that are missing them.

<details>
<summary>Debugging steps to try first</summary>

Check which containers have limits and which do not:

```bash
for deploy in parksmap nationalparks mongodb; do
  echo "=== $deploy ==="
  oc get deploy $deploy -n <your-dev-namespace> -o jsonpath='{.spec.template.spec.containers[0].resources}'
  echo ""
done
```

If `limits` is empty (`{}`), the container has no upper bound on CPU and memory usage. This means one misbehaving pod could consume all the node's resources.

</details>

<details>
<summary>Nudge</summary>

Open `values-dev.yaml` and look at the `resources` section for each component. The `limits` field is set to `{}` (empty) for some components. You need to set appropriate CPU and memory limits.

A good rule of thumb: set limits to 2-4x the requests for dev environments. This gives the application room to burst without being too greedy.

</details>

<details>
<summary>Stronger hint</summary>

In `values-dev.yaml`, update the resource sections. For example:

```yaml
frontend:
  resources:
    requests:
      cpu: 10m
      memory: 800Mi
    limits:
      cpu: 200m
      memory: 1Gi
```

Do the same for the backend and database components.

</details>

<details>
<summary>Solution</summary>

Edit `values-dev.yaml` and set resource limits for all three components:

```yaml
frontend:
  resources:
    requests:
      cpu: 10m
      memory: 800Mi
    limits:
      cpu: 200m
      memory: 1Gi

backend:
  resources:
    requests:
      cpu: 10m
      memory: 80Mi
    limits:
      cpu: 100m
      memory: 500Mi

database:
  resources:
    requests:
      cpu: 20m
      memory: 60Mi
    limits:
      cpu: 200m
      memory: 256Mi
```

Then upgrade:

```bash
helm upgrade parksmap ./ \
  --namespace <your-dev-namespace> \
  -f values-dev.yaml \
  --set namespace=<your-dev-namespace>
```

**Lesson**: Always set resource limits. Without them, a container can consume unlimited resources, which affects other tenants on the same cluster. Many production clusters enforce `ResourceQuota` or `LimitRange` objects that reject pods without limits.

</details>

---

## Exercise 4: Broken health probes

**The scenario**: The nationalparks backend pods keep restarting. Check the restart count:

```bash
oc get pods -l app=nationalparks -n <your-dev-namespace>
```

If you see the RESTARTS column increasing, the liveness probe is killing the container because it is failing.

**Your task**: Find and fix the health probe configuration in the backend deployment.

<details>
<summary>Debugging steps to try first</summary>

Describe the pod and look at the events:

```bash
oc describe pod -l app=nationalparks -n <your-dev-namespace>
```

Look for messages like "Liveness probe failed" or "Readiness probe failed". What HTTP response code is returned? What URL is the probe hitting?

You can also check the pod logs to confirm the application is actually starting:

```bash
oc logs -l app=nationalparks -n <your-dev-namespace>
```

</details>

<details>
<summary>Nudge</summary>

The health probe is configured to check a URL path on a specific port. Compare the path and port in the deployment template (`templates/backend-deploy.yaml`) with what the application actually exposes.

Look at `values.yaml` to see what `healthPath` and `port` should be. Then look at the deployment template to see what is actually configured.

</details>

<details>
<summary>Stronger hint</summary>

In `templates/backend-deploy.yaml`, the probes are hardcoded with the wrong path and port:

```yaml
          livenessProbe:
            httpGet:
              path: /healthz         # Should be /ws/healthz/
              port: 9090             # Should be {{ .Values.backend.port }}
```

The correct path is in `values.yaml` under `backend.healthPath` (`/ws/healthz/`), and the correct port is `backend.port` (8080).

</details>

<details>
<summary>Solution</summary>

In `templates/backend-deploy.yaml`, replace both the liveness and readiness probe blocks:

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

Then upgrade:

```bash
helm upgrade parksmap ./ \
  --namespace <your-dev-namespace> \
  -f values-dev.yaml \
  --set namespace=<your-dev-namespace>
```

**Lesson**: Always use values references for probe paths and ports instead of hardcoding them. When probes are wrong, the container starts fine but Kubernetes kills it because it thinks it is unhealthy. The key debugging step is `oc describe pod` -- the events section tells you exactly which probe failed and what response it got.

</details>

---

## Exercise 5: Image pull failure

**The scenario**: The nationalparks backend pod is stuck in `ErrImagePull` or `ImagePullBackOff`.

```bash
oc get pods -l app=nationalparks -n <your-dev-namespace>
```

**Your task**: Find and fix the image configuration.

<details>
<summary>Debugging steps to try first</summary>

Describe the pod and focus on the Events section:

```bash
oc describe pod -l app=nationalparks -n <your-dev-namespace>
```

Look for the "Failed to pull image" message. What image and tag is it trying to pull?

</details>

<details>
<summary>Nudge</summary>

The image tag in the values file is not a real tag. What tag does `values-dev.yaml` specify for the backend image? Does that tag actually exist in the image repository?

</details>

<details>
<summary>Stronger hint</summary>

In `values-dev.yaml`, the backend image tag is set to:

```yaml
backend:
  image:
    tag: nonexistent-tag
```

This tag does not exist in `quay.io/openshift-roadshow/nationalparks`. Change it to a valid tag like `latest`.

</details>

<details>
<summary>Solution</summary>

Edit `values-dev.yaml` and change the backend image tag:

```yaml
backend:
  image:
    tag: latest
    pullPolicy: Always
```

Then upgrade:

```bash
helm upgrade parksmap ./ \
  --namespace <your-dev-namespace> \
  -f values-dev.yaml \
  --set namespace=<your-dev-namespace>
```

**Lesson**: Using `latest` in dev is acceptable for rapid iteration, but never use `latest` in SIT or production. Pin your images to a specific version (e.g., `1.3.0`) so that deployments are reproducible. A common gotcha is when someone pushes a new `latest` image that breaks things, and you cannot roll back because you do not know which version was running before.

</details>

---

## Exercise 6: Label and selector mismatch

**The scenario**: The nationalparks pod is running, but when you `curl` the service, you get no response. The route returns a 503 error.

```bash
oc get endpoints nationalparks -n <your-dev-namespace>
```

If the ENDPOINTS column is empty or shows `<none>`, the Service cannot find any matching pods.

**Your task**: Find and fix the selector mismatch in the backend service.

<details>
<summary>Debugging steps to try first</summary>

Compare the Service selector with the pod labels:

```bash
echo "=== Service selector ==="
oc get svc nationalparks -n <your-dev-namespace> -o jsonpath='{.spec.selector}'

echo ""
echo "=== Pod labels ==="
oc get pods -l app=nationalparks -n <your-dev-namespace> -o jsonpath='{.metadata.labels}'
```

Do the selector labels match the pod labels?

</details>

<details>
<summary>Nudge</summary>

The Service `selector` must exactly match labels that are on the pods. If even one label does not match, the Service will have no endpoints and traffic will not reach the pods.

Look at `templates/backend-service.yaml` and compare its `selector` with the labels set on the backend pods (these come from the `parksmap.backend.selectorLabels` template in `_helpers.tpl`).

</details>

<details>
<summary>Stronger hint</summary>

In `templates/backend-service.yaml`, the selector is hardcoded with a wrong value:

```yaml
  selector:
    app: nationalparks
    deployment: wrong-name    # Should be: nationalparks
```

The pod labels (set by the deployment template via `parksmap.backend.selectorLabels`) use `deployment: nationalparks`.

</details>

<details>
<summary>Solution</summary>

In `templates/backend-service.yaml`, replace the hardcoded selector with the helper template:

```yaml
  selector:
    {{- include "parksmap.backend.selectorLabels" . | nindent 4 }}
```

Or if you prefer to keep it explicit, fix the hardcoded value:

```yaml
  selector:
    app: nationalparks
    deployment: nationalparks
```

Then upgrade:

```bash
helm upgrade parksmap ./ \
  --namespace <your-dev-namespace> \
  -f values-dev.yaml \
  --set namespace=<your-dev-namespace>
```

Verify endpoints are now populated:

```bash
oc get endpoints nationalparks -n <your-dev-namespace>
```

**Lesson**: Label/selector mismatches are one of the most common Kubernetes debugging scenarios. When a Service has no endpoints, the first thing to check is whether the selector matches the pod labels. Use `oc get endpoints` as your go-to debugging command for service connectivity issues.

</details>

---

## Exercise 7: Secret key mismatch

**The scenario**: The nationalparks backend pod starts but crashes shortly after with an error about being unable to connect to MongoDB.

```bash
oc logs -l app=nationalparks -n <your-dev-namespace> --tail=20
```

**Your task**: Find and fix the secret key reference in the backend deployment.

<details>
<summary>Debugging steps to try first</summary>

Describe the pod and look for warnings about missing secret keys:

```bash
oc describe pod -l app=nationalparks -n <your-dev-namespace>
```

Look for events like "Error: secret key not found" or the environment variable injection failing.

Also check what keys exist in the secret:

```bash
oc get secret mongodb-credentials -n <your-dev-namespace> -o jsonpath='{.data}' | python3 -m json.tool
```

Compare the key names in the secret with the key names referenced in the deployment.

</details>

<details>
<summary>Nudge</summary>

The backend deployment references secret keys by name when injecting `MONGODB_USER` and `MONGODB_PASSWORD` as environment variables. But the key names in the `secretKeyRef` do not match the key names that were defined in the `database-secret.yaml` template.

</details>

<details>
<summary>Stronger hint</summary>

In `templates/backend-deploy.yaml`, the secret references use:

```yaml
            - name: MONGODB_USER
              valueFrom:
                secretKeyRef:
                  name: mongodb-credentials
                  key: app-user     # Wrong! Should be: app-usr

            - name: MONGODB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mongodb-credentials
                  key: app-pass     # Wrong! Should be: app-pwd
```

The actual keys in the secret (defined in `database-secret.yaml`) are `app-usr` and `app-pwd`.

</details>

<details>
<summary>Solution</summary>

In `templates/backend-deploy.yaml`, fix the secret key references:

```yaml
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

Then upgrade:

```bash
helm upgrade parksmap ./ \
  --namespace <your-dev-namespace> \
  -f values-dev.yaml \
  --set namespace=<your-dev-namespace>
```

**Lesson**: Secret key mismatches cause pods to crash or fail to start. Kubernetes will report the error in the pod events, but you need to cross-reference the key names between the Secret resource and the Deployment that references it. A good practice is to define secret key names as values so they are consistent across templates.

</details>

---

## Exercise 8: Missing backend discovery label

**The scenario**: Everything seems to be running. The backend responds when you hit its route directly. But the frontend map is empty -- it cannot find the backend.

Visit the frontend route and confirm the map shows no parks data, even after loading data via the backend route.

**Your task**: Find and fix the missing label that the frontend uses to discover the backend service.

<details>
<summary>Debugging steps to try first</summary>

Check the frontend logs for clues:

```bash
oc logs -l app=parksmap -n <your-dev-namespace> --tail=20
```

Check what labels are on the backend service:

```bash
oc get svc nationalparks -n <your-dev-namespace> --show-labels
```

What labels does the frontend look for? You can find this in the `_helpers.tpl` or the original README.

</details>

<details>
<summary>Nudge</summary>

The parksmap frontend discovers backends by looking for Services with a specific label. This label was on the backend service in the Part 1 exercises. Is it present in the Part 2 version?

</details>

<details>
<summary>Stronger hint</summary>

The frontend looks for Services with the label `type: parksmap-backend`. Check `templates/backend-service.yaml` -- this label is missing from the metadata labels section.

</details>

<details>
<summary>Solution</summary>

In `templates/backend-service.yaml`, add the discovery label after the backend labels include:

```yaml
metadata:
  name: nationalparks
  namespace: {{ include "parksmap.namespace" . }}
  labels:
    {{- include "parksmap.backend.labels" . | nindent 4 }}
    type: parksmap-backend
```

Then upgrade:

```bash
helm upgrade parksmap ./ \
  --namespace <your-dev-namespace> \
  -f values-dev.yaml \
  --set namespace=<your-dev-namespace>
```

Refresh the frontend page. If you already loaded data in a previous exercise, the parks should now appear. If not, load data first:

```bash
oc get route nationalparks -n <your-dev-namespace> -o jsonpath='{.spec.host}'
```

Visit `https://<backend-route>/ws/data/load`, then refresh the frontend.

**Lesson**: Service discovery via labels is a common pattern in Kubernetes. If your application uses label-based discovery, those labels are just as important as the service ports and selectors. Missing a discovery label will not cause any errors or crashes -- the application will simply not find the backend, which makes it harder to debug than a pod crash.

</details>

---

## Final validation

If you have fixed all eight issues, your ParksMap application should be fully working. Verify:

1. All pods are running without restarts:

```bash
oc get pods -n <your-dev-namespace>
```

2. All services have endpoints:

```bash
oc get endpoints -n <your-dev-namespace>
```

3. The frontend map shows national parks data.

4. Deploy to SIT as well (remember to fix the namespace in `values-sit.yaml` too):

```bash
helm install parksmap ./ \
  --namespace <your-sit-namespace> \
  -f values-sit.yaml \
  --set namespace=<your-sit-namespace>
```

Load data for SIT and compare the two environments.

---

## What you have learned

By completing this section, you can now:

- Debug namespace mismatches caused by hardcoded values
- Understand and satisfy the OCP `restricted-v2` SCC requirements
- Set proper resource requests and limits
- Diagnose and fix health probe failures
- Troubleshoot image pull errors
- Debug Service selector and endpoint issues
- Identify missing labels that break service discovery
- Fix Secret key reference mismatches

These are the most common deployment failures you will encounter when working with Kubernetes and OpenShift. The debugging approach you practiced here -- `oc describe`, `oc logs`, `oc get events`, `oc get endpoints` -- works for almost any issue.
