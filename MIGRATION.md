# Migration: Helm push-deploy → ArgoCD

Per chart, per target cluster. See `nx-application-helm`'s `MIGRATION.md` for
what changed in each chart and why — this file is steps only.

## Pre-reqs (once per chart, before first cutover)

- [ ] Chart-side ArgoCD fixes landed and merged (see `nx-application-helm/MIGRATION.md`)
- [ ] ApplicationSet added under `apps/` and manually synced at least once
- [ ] Any chart-specific pre-req below is done

## Cutover steps

1. Confirm the ArgoCD Application is `Synced`/`Healthy` — it adopts the existing
   push-deploy resources in place, no uninstall needed first:
   ```sh
   kubectl -n argocd get application <chart>-<env>
   ```
2. Drop the push-deploy release with `--cascade orphan` so ArgoCD keeps the
   live resources (a plain `helm uninstall` deletes them — the objects still
   carry Helm's `meta.helm.sh/*` labels even after ArgoCD adopts them):
   ```sh
   helm uninstall <chart> -n default --cascade orphan
   ```
   Removes the release from `helm list`; leaves every live resource in place.
3. Remove `<chart>` from the env repo's `environment.yaml` `deployment.layers`
   list, so the CI reusable workflow never re-installs it via push-helm.
4. Enable `automated: {prune: true, selfHeal: true}` if not already on.

## eks-development cutover (copy-paste)

The 4 foundation charts are ArgoCD-managed and `Synced`/`Healthy`. Orphan
uninstall drops only the Helm release metadata — every live resource (pods,
StatefulSets, PVCs, Services) keeps running, ArgoCD stays in control. Safe on
the stateful `event-systems` PVCs; no data loss, no downtime.

```sh
for chart in pre-infrastructure infrastructure cnpg-operator event-systems; do
  helm uninstall "$chart" -n default --kube-context eks-development --cascade orphan
done
```

Then merge the `nxdeployment-development-env` PR that removes these from
`deployment.layers` so push-helm CI stops re-managing them.

> Do NOT use a plain `helm uninstall` (default `--cascade background`) — it
> deletes the live resources and forces a full restart of the Pulsar/NATS
> cluster.

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
