# DevOps Lab - GitOps Root

This folder contains the Kubernetes manifests for the DevOps Lab 3-tier application.

## Structure

```
gitops-root/
├── templates/           # Kubernetes manifests
│   ├── namespace.yaml
│   ├── postgres.yaml
│   ├── backend.yaml
│   ├── frontend.yaml
│   ├── ingress.yaml
│   ├── servicemonitor.yaml
│   └── grafana-dashboard.yaml
├── application.yaml     # ArgoCD Application manifest
└── README.md
```

## Usage

1. Initialize this folder as a Git repository
2. Push to GitHub
3. Update the `repoURL` in `application.yaml`
4. Apply the ArgoCD application:
   ```bash
   kubectl apply -f application.yaml
   ```

## Pre-requisites

Before deploying via ArgoCD, ensure the Docker images are imported into k3d:

```bash
docker build -t lab-backend:v1 ./src/backend/
docker build -t lab-frontend:v1 ./src/frontend/
k3d image import lab-backend:v1 lab-frontend:v1 -c devops-lab
```
