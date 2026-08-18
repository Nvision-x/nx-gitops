# nx-gitops

Config for the ArgoCD instance that deploys our internal environments
(`eks-development`, `eks-integration`) from the hub cluster on mimir.

This repo is config only — no charts, no CI. The reusable pieces live in
`nx-application-helm`; this repo just says which envs exist and where they go.
It also doubles as the reference layout for per-customer repos like
`nx-gitops-ssb` (see [Scaffolding a customer repo](#scaffolding-a-customer-repo)).

## The two charts this repo consumes

Both published to `ghcr.io/nvision-x` from `nx-application-helm/charts/`, both
public, so anyone can pull them without credentials.

| Chart | What it does |
|---|---|
| `argocd` | Installs ArgoCD. Thin wrapper over the upstream `argo-cd` chart, vendored so the tarball is self-contained (good for on-prem/air-gap) and the version is pinned in one place. |
| `argocd-control-plane` | Everything ArgoCD then deploys: one AppProject plus one ApplicationSet per platform layer, with the sync policies and `ignoreDifferences` workarounds baked in. Driven entirely by values. |

Rule of thumb: `argocd` is the engine, `argocd-control-plane` is the instructions.

## Layout

```
bootstrap/root-application.yaml   app-of-apps, applied by hand once
argocd/application.yaml           ArgoCD manages itself from the argocd chart
argocd/values.yaml                our ingress, domain, cert, replicas
apps/control-plane.yaml           renders argocd-control-plane with envs/values.yaml
envs/values.yaml                  our overlay: project scope + which env repos
clusters/*.yaml                   spoke registration (cross-account IAM)
tailscale/connector.yaml          hub network access
```

`argocd/` points ArgoCD at its own chart, so upgrades are a version bump here
instead of a `helm upgrade` by hand. `apps/` holds the single Application that
turns `argocd-control-plane` + our overlay into the AppProject and 8
ApplicationSets.

## One-time bootstrap

ArgoCD can't install itself, so a human does these two steps once per cluster:

```sh
helm install argocd oci://ghcr.io/nvision-x/argocd \
  --version <pin> -n argocd --create-namespace
kubectl apply -f bootstrap/root-application.yaml
```

After that it's self-running: `root` watches this repo, adopts `argocd/`,
`apps/` and `clusters/`, and ArgoCD takes over managing itself. Every later
change is a PR here — no more kubectl.

The root app picks up manifests one directory deep. ArgoCD ignores YAML that
isn't a Kubernetes object (see `argocd/values.yaml`), but `envs/` is excluded
explicitly so nobody has to think about it.

## How a deploy actually happens

1. `apps/control-plane.yaml` renders the ApplicationSets from our overlay
2. each ApplicationSet reads `environment.yaml` from `nxdeployment-<env>-env`
3. envs opt in with `deployment.method: argocd` — anything else is skipped
4. one Application per env per layer, pulling the layer chart at that env's
   `registry.defaultVersion` with values from the same env repo

So two files here become the Applications you see in the UI.

## Scaffolding a customer repo

A customer repo (`nx-gitops-ssb`) is this repo minus the hub-specific bits.
They already have `nxdeployment-ssb-env` for Helm values — this is only the
control-plane config.

**We host their ArgoCD (they're a spoke on our hub):** no new repo needed for
ArgoCD itself. Add their overlay and an Application alongside ours:

```
envs/ssb.yaml        their project scope + env repo
apps/ssb.yaml        same chart, valueFiles -> $values/envs/ssb.yaml
```

**They host their own ArgoCD:** give them a repo with two files.

```
values.yaml              the overlay below
root-application.yaml    points at their repo, not ours
```

Either way the overlay is small:

```yaml
project:
  name: nvisionx-ssb
  destinations:
    - name: eks-ssb        # in-cluster if they run their own ArgoCD
      namespace: "*"
environments:
  - name: ssb
    envRepo:
      url: https://github.com/Nvision-x/nxdeployment-ssb-env.git
      revision: main
```

Trim layers they don't run with `layers.<name>.enabled: false`. `values.schema.json`
in the chart rejects anything that isn't control-plane config, so Helm values
can't leak in here by accident.

Self-hosted customers run the same two bootstrap commands above. Nothing is
issued to them — the charts are public, and their repo can live on their own
git server, which is also what makes an air-gapped install possible.
