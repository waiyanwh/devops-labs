# 📋 Solutions Reference

> ⚠️ **Spoiler Warning**: These files contain the solutions to the quests. Try to solve the challenges yourself first!

## Quest Solutions

| Quest | Folder | Description |
|-------|--------|-------------|
| **Quest 1** | `quest-1-gitops/` | ArgoCD Application manifest |
| **Quest 2** | `quest-2-cicd/` | Jenkins pipeline definitions |
| **Quest 3** | `quest-3-observability/` | Prometheus ServiceMonitor |
| **Quest 4** | `quest-4-keda/` | KEDA ScaledObject for RabbitMQ |

## How to Use

If you get stuck on a quest, peek at the solution files for hints. But remember:

1. **Try first** - Spend at least 15-30 minutes attempting the quest
2. **Use hints** - The README has progressive hints for each quest
3. **Understand, don't copy** - If you look at a solution, understand WHY it works
4. **Apply yourself** - Type out the solution yourself, don't just copy-paste

## Applying Solutions

```bash
# Quest 1: Apply ArgoCD Application
kubectl apply -f _solutions/quest-1-gitops/application.yaml

# Quest 3: Apply ServiceMonitor
kubectl apply -f _solutions/quest-3-observability/servicemonitor.yaml

# Quest 4: Apply KEDA ScaledObject
kubectl apply -f _solutions/quest-4-keda/rabbitmq-scaledobject.yaml
```

For Quest 2 (Jenkins), you need to configure the pipelines in the Jenkins UI using the Jenkinsfile paths.
