# Migration: Helm push-deploy → ArgoCD

Per target cluster: get the ArgoCD app healthy, then uninstall the push-deploy release so ArgoCD owns it. 

## 1. Upgrade Prometheus Operator CRDs

Only for clusters still on `observability-crds` (~v0.70). Brand-new clusters skip
it. development needs it.

```sh
# In-place CRD upgrade to v0.84.1 so ArgoCD can diff the new Prometheus CR fields.
kubectl apply --server-side --force-conflicts \
  -f https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.84.1/stripped-down-crds.yaml
```

## 2. Confirm ArgoCD is reconciling

```sh
# Want Synced / Healthy before removing the push-deploy release.
kubectl -n argocd get application observability-<env>
```

## 3. Uninstall the push-deploy releases

```sh
# Hands ownership to ArgoCD (recreates workloads); short monitoring/KEDA gap.
helm uninstall processing-systems -n default
helm uninstall observability      -n default
helm uninstall observability-crds -n default
```

Not destructive: the Prometheus PVC, the grafana secret, and the CRDs survive (not Helm-owned).
