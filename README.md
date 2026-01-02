# 🚀 DevOps Lab: The Architect's Journey

A hands-on DevOps learning lab where **you** configure the integrations. No hand-holding—just a working cluster and challenges to solve.

## ⚠️ Resource Requirements

> **Warning**: This lab runs multiple services and can be resource-intensive!

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **RAM** | 8 GB | 16 GB |
| **CPU** | 4 cores | 8 cores |
| **Disk** | 20 GB | 40 GB |

## Prerequisites

- Docker
- k3d
- kubectl
- Helm 3

---

## 📦 Phase 1: The Base (Automated)

Run these scripts to get a working cluster with tools installed (but **not configured**):

```bash
# 1. Configure your environment
vim config.env

# 2. Create the k3d cluster with Traefik
./01-setup-cluster.sh

# 3. Install tools (ArgoCD, Prometheus, Jenkins, etc.)
./02-install-tools.sh

# 4. Deploy the demo app (manually, not via GitOps)
./03-deploy-app.sh

# 5. Add hostnames to /etc/hosts
echo "127.0.0.1 app.localhost api.localhost argocd.localhost grafana.localhost rabbitmq.localhost jenkins.localhost" | sudo tee -a /etc/hosts
```

### ✅ Verification

After Phase 1, you should have:

```bash
# Working app
curl http://app.localhost         # Frontend
curl http://api.localhost/health  # Backend API

# Tools running but unconfigured
kubectl get pods -n argocd        # ArgoCD running
kubectl get pods -n ci            # Jenkins + Registry running
kubectl get pods -n monitoring    # Prometheus + Grafana running

# But NO integrations configured yet:
kubectl get application -n argocd  # Empty - YOU will configure this
kubectl get servicemonitor -n app  # Empty - YOU will create this
```

---

## 🛠️ Your Mission (The Challenges)

*You are the Lead DevOps Engineer. The intern deployed this cluster manually. Your job is to professionalize it.*

Each quest builds on the previous one. Complete them in order.

---

### 🎯 Quest 1: The GitOps Migration

**Current State:** Apps are deployed via `kubectl apply`. Changes require manual intervention.

**Objective:** Configure ArgoCD to manage the 3-tier application using GitOps.

**Success Criteria:**
- [ ] ArgoCD Application syncs the app from Git
- [ ] You delete the backend Deployment manually → ArgoCD auto-heals it within 30s
- [ ] You can see the app status in ArgoCD UI (http://argocd.localhost)

**Hints (progressive):**
<details>
<summary>Hint 1: Where to start</summary>

Look at the `gitops-root/` folder. There's a `templates/` directory with manifests...
</details>

<details>
<summary>Hint 2: The manifest structure</summary>

You need to create an ArgoCD `Application` resource that points to your Git repo and the `gitops-root/templates/` path.
</details>

<details>
<summary>Hint 3: Key fields</summary>

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ???
  namespace: argocd
spec:
  source:
    repoURL: ???
    path: ???
  destination:
    server: https://kubernetes.default.svc
    namespace: app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```
</details>

---

### 🎯 Quest 2: The Supply Chain

**Current State:** Images are built locally and imported via `k3d image import`. No CI/CD.

**Objective:** Configure Jenkins to build Docker images and push them to the internal Registry.

**Success Criteria:**
- [ ] A Jenkins Pipeline builds `lab-backend` from `src/backend/Dockerfile`
- [ ] Image is pushed to `registry.ci.svc.cluster.local:5000/lab-backend:v1`
- [ ] You can pull the image from inside the cluster

**Hints (progressive):**
<details>
<summary>Hint 1: Access Jenkins</summary>

Jenkins is at http://jenkins.localhost. Get the password:
```bash
kubectl exec --namespace ci -it svc/jenkins -c jenkins -- \
  /bin/cat /run/secrets/additional/chart-admin-password
```
</details>

<details>
<summary>Hint 2: Pipeline setup</summary>

Create a Pipeline job → "Pipeline script from SCM" → Point to your Git repo.
You need a `Jenkinsfile` that uses Kaniko (Docker socket isn't available in k3d).
</details>

<details>
<summary>Hint 3: Kaniko executor</summary>

```groovy
agent {
    kubernetes {
        yaml '''
spec:
  containers:
  - name: kaniko
    image: gcr.io/kaniko-project/executor:debug
    ...
'''
    }
}
```
Kaniko needs `--insecure` flag for the internal registry.
</details>

---

### 🎯 Quest 3: Observability

**Current State:** Prometheus is running, but it doesn't scrape the backend metrics.

**Objective:** Create a ServiceMonitor so Prometheus discovers the backend's `/metrics` endpoint.

**Success Criteria:**
- [ ] Prometheus Targets page shows `backend` as a target
- [ ] You can query `http_requests_total` in Prometheus/Grafana
- [ ] The pre-built Grafana dashboard shows metrics

**Hints (progressive):**
<details>
<summary>Hint 1: Check the backend</summary>

The backend exposes metrics at `:8000/metrics`. Try:
```bash
kubectl port-forward svc/backend -n app 8000:80
curl http://localhost:8000/metrics
```
</details>

<details>
<summary>Hint 2: ServiceMonitor structure</summary>

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ???
  namespace: ???
  labels:
    ???  # Prometheus looks for specific labels
spec:
  selector:
    matchLabels:
      ???  # Must match Service labels
  endpoints:
  - port: ???
    path: /metrics
```
</details>

<details>
<summary>Hint 3: Label matching</summary>

Check the backend Service labels with:
```bash
kubectl get svc backend -n app --show-labels
```
Prometheus is configured to scrape ServiceMonitors with certain labels. Check the Prometheus Helm values.
</details>

---

### 🎯 Quest 4: Event-Driven Scaling

**Current State:** The worker runs with fixed replicas. Queue buildup = slow processing.

**Objective:** Configure KEDA to scale workers based on RabbitMQ queue length.

**Success Criteria:**
- [ ] Workers scale from 0 when queue has messages
- [ ] Running `./spam_jobs.sh` causes workers to scale up
- [ ] Workers scale back to 0 after queue drains

**Hints (progressive):**
<details>
<summary>Hint 1: KEDA basics</summary>

KEDA uses a `ScaledObject` to define scaling rules. You need:
- A trigger (RabbitMQ queue length)
- Min/max replicas
- Scaling metadata (queue name, threshold)
</details>

<details>
<summary>Hint 2: RabbitMQ connection</summary>

The RabbitMQ connection string is in a secret:
```bash
kubectl get secret rabbitmq-creds -n app -o yaml
```
You'll need `host` for the ScaledObject.
</details>

<details>
<summary>Hint 3: ScaledObject structure</summary>

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: ???
spec:
  scaleTargetRef:
    name: worker  # Deployment name
  minReplicaCount: 0
  maxReplicaCount: 10
  triggers:
  - type: rabbitmq
    metadata:
      queueName: work_queue
      hostFromEnv: ???
```
</details>

---

## 📁 Solutions

Stuck? Solutions are available in the `_solutions/` folder.

> ⚠️ **Try first!** The learning happens when you struggle. Only peek at solutions after genuine effort.

```
_solutions/
├── quest-1-gitops/          # ArgoCD Application
├── quest-2-cicd/            # Jenkinsfiles
├── quest-3-observability/   # ServiceMonitor
└── quest-4-keda/            # ScaledObject
```

---

## 🏆 Victory Lap

When all quests are complete, you'll have:

- ✅ **GitOps**: App changes deploy automatically via ArgoCD
- ✅ **CI/CD**: Code pushes trigger Jenkins builds → Registry → Deploy
- ✅ **Observability**: Full metrics pipeline from app → Prometheus → Grafana
- ✅ **Event-Driven Scaling**: Workers scale based on actual load

**Congratulations, DevOps Architect!** 🎉

---

## 📚 Reference

### Service URLs

| Service | URL | Notes |
|---------|-----|-------|
| Frontend | http://app.localhost | Demo app |
| Backend API | http://api.localhost | Health: `/health`, Metrics: `/metrics` |
| ArgoCD | http://argocd.localhost | See Pod for password |
| Grafana | http://grafana.localhost | admin/admin |
| Jenkins | http://jenkins.localhost | See Quest 2 for password |
| RabbitMQ | http://rabbitmq.localhost | See Secret for credentials |

### Project Structure

```
devops-labs/
├── 01-setup-cluster.sh      # Creates k3d cluster
├── 02-install-tools.sh      # Installs (unconfigured) tools
├── 03-deploy-app.sh         # Deploys app manually
├── config.env               # Configuration
├── src/                     # Application source code
├── k8s/                     # Kubernetes manifests
├── gitops-root/templates/   # GitOps manifests (for Quest 1)
├── gitops/src/              # Where your Jenkinsfiles go (Quest 2)
└── _solutions/              # 👀 Spoilers!
```

### Cleanup

```bash
k3d cluster delete devops-lab
```
