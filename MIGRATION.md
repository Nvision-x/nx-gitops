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
2. Make Helm forget the release WITHOUT touching any resource — delete only the
   release storage Secret. ArgoCD already manages the resources, so this is a
   clean hand-off: nothing deleted, no restart needed:
   ```sh
   kubectl delete secret -n <ns> -l owner=helm,name=<chart>
   ```
   Do NOT use `helm uninstall --cascade orphan`: despite the name it DELETES the
   release's objects (ServiceAccounts, ClusterRoles, Deployments…) and only
   orphans their pods. ArgoCD self-heals them back, but recreated ServiceAccounts
   get new UIDs — API-watching operators keep presenting stale tokens and
   crashloop with `401 Unauthorized` until their pods are recreated (see Recovery).
3. Remove `<chart>` from the env repo's `environment.yaml` `deployment.layers`
   list, so the CI reusable workflow never re-installs it via push-helm.
4. Enable `automated: {prune: true, selfHeal: true}` if not already on.

## Foundation charts cutover (copy-paste)

Once the ArgoCD Applications are `Synced`/`Healthy`, make Helm forget the
foundation releases without touching any resource (ArgoCD keeps managing them —
no deletion, no restart, no downtime):

```sh
CTX=<cluster-context>   # kube-context for this env's cluster
NS=<namespace>          # this env's namespace from environment.yaml

for chart in pre-infrastructure infrastructure cnpg-operator event-systems; do
  kubectl --context "$CTX" -n "$NS" delete secret -l "owner=helm,name=$chart"
done
```

Then merge the `nxdeployment-<env>-env` PR that removes these from
`deployment.layers` so push-helm CI stops re-managing them.

### Recovery: operators crashlooping after cutover (401 Unauthorized)

If a release was instead removed with `helm uninstall --cascade orphan` (or the
ServiceAccounts were otherwise deleted and recreated), API-watching operators
keep presenting stale tokens and crashloop with `401 Unauthorized`. Recreate the
pods so they pick up fresh tokens:

```sh
kubectl --context "$CTX" -n "$NS" rollout restart deployment \
  cert-manager-cainjector keda-operator
```

`cert-manager-cainjector` then re-injects the cert-manager webhook CA bundle,
which unblocks an `infrastructure` sync failing with
`webhook.cert-manager.io … x509: certificate signed by unknown authority`.

The webhook fix is cluster-side, so ArgoCD won't know to retry on its own —
kick a fresh compare, and if the prior auto-sync already exhausted its retries,
trigger an explicit sync:

```sh
kubectl --context "$CTX" -n argocd annotate application infrastructure-<env> \
  argocd.argoproj.io/refresh=hard --overwrite
# if still not syncing (retries exhausted): ArgoCD UI → Sync, or
# argocd app sync infrastructure-<env>
```

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
