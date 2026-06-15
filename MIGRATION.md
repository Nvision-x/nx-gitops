# Migration: Helm push-deploy → ArgoCD

Manual uninstall of pieces dropped from `nxdeployment-<env>-env` once they're
served by ArgoCD. Run against each target cluster.

## processing-systems

```sh
helm uninstall processing-systems -n default
```
