# Migration: Helm push-deploy → ArgoCD

Per chart, per target cluster. See `nx-application-helm`'s `MIGRATION.md` for
what changed in each chart and why — this file is steps only.

## Pre-reqs (once per chart, before first cutover)

- [ ] Chart-side ArgoCD fixes landed and merged (see `nx-application-helm/MIGRATION.md`)
- [ ] ApplicationSet added under `apps/` and manually synced at least once
- [ ] Any chart-specific pre-req below is done

## Cutover steps

1. Confirm the ArgoCD Application is `Synced`/`Healthy`:
   ```sh
   kubectl -n argocd get application <chart>-<env>
   ```
2. Uninstall the push-deploy release so ArgoCD owns it:
   ```sh
   helm uninstall <chart> -n default
   ```
   Not destructive: PVCs, Secrets, and CRDs survive (not Helm-owned).
3. Remove `<chart>` from the env repo's `environment.yaml` `deployment.layers`
   list, so the CI reusable workflow never re-installs it via push-helm.
4. Enable `automated: {prune: true, selfHeal: true}` if not already on.

## Chart-specific pre-reqs

- **observability** (only clusters still on `observability-crds` ~v0.70;
  brand-new clusters skip this):
  ```sh
  kubectl apply --server-side --force-conflicts \
    -f https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.84.1/stripped-down-crds.yaml
  ```
- **infrastructure / pre-infrastructure / cnpg-operator / event-systems**: none.
- **databases**: do not cut over yet — see the external-values gap in
  `nx-application-helm/MIGRATION.md`.
- **applications**: known gap (knowledge-hub-be-go) documented in
  `nx-application-helm/MIGRATION.md` — cutover is still fine, that one feature
  just won't self-configure until fixed.
