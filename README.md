# DevOps Lab - Local Kubernetes Learning Environment

A complete local DevOps lab featuring k3d, ArgoCD, Prometheus, Grafana, and a 3-tier demo application with full observability.

## Quick Start

1. **Configure your environment:**
   ```bash
   # Edit config.env with your settings (GitHub URL, passwords, etc.)
   vim config.env
   ```

2. **Create the cluster:**
   ```bash
   ./01-setup-cluster.sh
   ```

3. **Install GitOps & Monitoring tools:**
   ```bash
   ./02-install-tools.sh
   ```

4. **Deploy the demo application:**
   
   **Option A: Manual Deployment (Script)**
   Good for local development loop.
   ```bash
   ./03-deploy-app.sh
   ```

   **Option B: GitOps Deployment (ArgoCD)**
   Good for testing the full CD pipeline.
   1. Ensure code is pushed to your Git repo.
   2. Edit `config.env` and set `GIT_REPO_URL` to your repo.
   3. Apply the Application manifest:
      ```bash
      # First, build and import images (if not done)
      ./03-deploy-app.sh --build-only  # You might need to edit script to support this or just let it run
      
      # Apply ArgoCD Application
      kubectl apply -f gitops-root/application.yaml
      ```
   4. Sync via ArgoCD UI at http://argocd.localhost

5. **Add hostnames to /etc/hosts:**
   ```bash
   echo "127.0.0.1 app.localhost api.localhost argocd.localhost grafana.localhost" | sudo tee -a /etc/hosts
   ```

## Configuration

All configurable values are in `config.env`. Key settings:

| Variable | Description | Default |
|----------|-------------|---------|
| `CLUSTER_NAME` | k3d cluster name | `devops-lab` |
| `SERVER_COUNT` | Master nodes | `1` |
| `AGENT_COUNT` | Worker nodes | `3` |
| `GIT_REPO_URL` | Your GitHub repo for GitOps | `https://github.com/YOUR_USERNAME/devops-labs.git` |
| `DB_PASSWORD` | PostgreSQL password | `apppassword` |
| `GRAFANA_ADMIN_PASSWORD` | Grafana password | `admin` |

## Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Frontend | http://app.localhost | - |
| Backend API | http://api.localhost | - |
| ArgoCD | http://argocd.localhost | `admin` / (auto-generated) |
| Grafana | http://grafana.localhost | `admin` / `admin` |

## Project Structure

```
devops-labs/
├── config.env              # ⚙️  Configuration file (edit this!)
├── 01-setup-cluster.sh     # Creates k3d cluster (supports K8s 1.35+)
├── 02-install-tools.sh     # Installs ArgoCD + Prometheus (patched for Traefik v2)
├── 03-deploy-app.sh        # Builds and deploys the app
├── 04-chaos-test.sh        # 🐒 Chaos Monkey resilience tests
├── 05-k8s-compat-test.sh   # 🔄 K8s version compatibility matrix
├── src/
│   ├── backend/            # FastAPI with Prometheus metrics
│   └── frontend/           # Nginx + HTML/JS
├── k8s/app/                # Kubernetes manifests
└── gitops-root/            # ArgoCD GitOps structure
    ├── application.yaml    # ArgoCD Application
    └── templates/          # K8s manifests for syncing
```

## Prerequisites

- Docker
- k3d
- kubectl
- Helm 3

## Cleanup

## Testing

This project includes scripts for resilience and compatibility testing:

### Chaos Monkey
Run reliability tests (Pod deletion, DB outage, etc.):
```bash
./04-chaos-test.sh
```

### K8s Compatibility
Test the stack against different Kubernetes versions (v1.22 - v1.35):
```bash
# Test specific version
./05-k8s-compat-test.sh 1.35

# Test all supported versions
./05-k8s-compat-test.sh all
```
> **Note:** K8s 1.35+ requires `k3d` v5.7.4+. The setup script tries to detect/download it automatically.

## Cleanup

```bash
k3d cluster delete devops-lab
```
