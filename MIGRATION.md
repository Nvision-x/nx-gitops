# Playbook: Helm push-deploy → ArgoCD

Per environment. Chart-side changes are already merged; see `nx-application-helm/MIGRATION.md` for what changed and why. This file is the run-order.

Set the namespace once (kubectl must already point at the target cluster):

```sh
NS=<namespace>   # this env's namespace from its environment.yaml
```

## Prerequisites

- Env repo `nxdeployment-<env>-env` exists with `environment.yaml`.
- The env's cluster is reachable and registered in the central ArgoCD (mimir).
- Chart-side ArgoCD fixes are merged (they are, globally).

## Step 1 — Enable the env in the appsets

In each `apps/*-appset.yaml`, uncomment (or add) this env's entry under `generators`. Commit and push to the branch the root app tracks (`development`). The central ArgoCD then generates the Applications.

Layers and sync-waves (created in this order automatically):

```
pre-infrastructure  -10
infrastructure       -5
observability        -4
cnpg-operator        -3
databases             0
event-systems         1
processing-systems    2
applications          3
```

## Step 2 — Chart-specific pre-reqs (before cutover)

Only `observability`, and only on clusters still running the old `observability-crds` (~v0.70). Brand-new clusters skip this:

```sh
kubectl apply --server-side --force-conflicts \
  -f https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.84.1/stripped-down-crds.yaml
```

No pre-reqs for the other layers.

## Step 3 — Wait for all Applications Synced/Healthy

ArgoCD adopts the existing push-deploy resources in place — no uninstall first.

```sh
kubectl -n argocd get applications | grep <env>
```

All 8 must read `Synced` / `Healthy` before Step 4. If one is stuck `OutOfSync`, force a fresh compare:

```sh
kubectl -n argocd annotate application <chart>-<env> \
  argocd.argoproj.io/refresh=hard --overwrite
```

## Step 4 — Hand off Helm → ArgoCD

Delete only the Helm release-storage Secret for each chart. This makes Helm forget the release WITHOUT touching any resource — ArgoCD keeps managing them. No deletion, no restart, no downtime:

```sh
for chart in pre-infrastructure infrastructure observability cnpg-operator \
             databases event-systems processing-systems applications; do
  kubectl -n "$NS" delete secret -l "owner=helm,name=$chart" --ignore-not-found
done
```

Confirm Helm no longer tracks anything:

```sh
helm -n "$NS" list -a
```

## Step 5 — Stop push-helm CI

Open a PR on `nxdeployment-<env>-env` that empties the layer list, so the reusable workflow stops re-installing:

```yaml
deployment:
  layers: []
```

## Step 6 — Verify

```sh
kubectl -n argocd get applications | grep <env>
kubectl -n "$NS" get pods | grep -vE "Running|Completed"
helm -n "$NS" list -a
```

Expect: all apps Synced/Healthy, no bad pods, no Helm releases.

## NEVER: helm uninstall

`helm uninstall` (even `--cascade orphan`) DELETES the release's objects (ServiceAccounts, ClusterRoles, Deployments). ArgoCD self-heals them, but recreated ServiceAccounts get new UIDs — API-watching operators keep presenting stale tokens and crashloop `401 Unauthorized`. Use Step 4 instead.

## Recovery: operators crashlooping (401 Unauthorized)

If SAs were deleted/recreated (e.g. an accidental uninstall), recreate the pods so they pick up fresh tokens:

```sh
kubectl -n "$NS" rollout restart deployment cert-manager-cainjector keda-operator
```

`cert-manager-cainjector` re-injects the webhook CA bundle, unblocking an `infrastructure` sync failing with `x509: certificate signed by unknown authority`. That fix is cluster-side, so kick a fresh compare:

```sh
kubectl -n argocd annotate application infrastructure-<env> \
  argocd.argoproj.io/refresh=hard --overwrite
```

## Notes per chart

- **databases** — external DB host/user/password come from a PostSync Job (`external-db-config-sync`); `databases-appset.yaml` carries the matching `ignoreDifferences` so selfHeal doesn't revert them.
- **applications** — `applications-appset.yaml` ignores Deployment `/spec/replicas` so ArgoCD selfHeal doesn't fight KEDA scale-to-zero.
- **event-systems** — repo-server must reach `pulsar.apache.org` and `nats-io.github.io` at render time (deps are not vendored).
