# Migration: Helm push-deploy → ArgoCD

Manual uninstall of pieces dropped from `nxdeployment-<env>-env` once they're
served by ArgoCD. Run against each target cluster.

## processing-systems

```sh
helm uninstall processing-systems -n default
```

## observability  (+ observability-crds)

Uninstall first, then let ArgoCD redeploy fresh (clean ownership). A short monitoring/KEDA gap is expected.

```sh
helm uninstall observability      -n default
helm uninstall observability-crds -n default
```

Not destructive: the Prometheus PVC, the grafana secret, and the CRDs are not Helm-owned, so they survive. ArgoCD recreates the workloads and upgrades the CRDs to its proper version in place.

**Never `kubectl delete crd`** — it cascade-deletes every ServiceMonitor / PrometheusRule / Prometheus / Alertmanager CR cluster-wide.
