# nx-gitops

ArgoCD configuration for the NvisionX EKS clusters. This repo is the source of
truth that ArgoCD continuously reconciles against the cluster.

## Layout

| Path | Contents |
|---|---|
| `bootstrap/` | Manifests applied **once, manually**, to start the ArgoCD self-management loop. |
| `argocd/` | ArgoCD's own `Application` (self-managing the argo-cd Helm chart) and its `values.yaml`. |
| `projects/` | `AppProject` CRs defining allowed sources, destinations, and RBAC scopes. |
| `clusters/` | ArgoCD cluster registration `Secret`s (one per managed cluster). |
| `apps/` | `ApplicationSet`s that generate the workload `Application`s. |

## Bootstrap (one-time, per cluster)

ArgoCD is installed onto a cluster by `nx-development-tf` (or the equivalent env
repo) via the `nx-argocd-tf` Terraform module. At that point the chart is
running but ArgoCD is not yet aware of this Git repo.

The handoff is a **single, manual** `kubectl apply` that creates the `root`
Application. From there ArgoCD discovers everything else by recursive directory
sync.

```bash
AWS_PROFILE=nvisionx-development \
  kubectl -n argocd apply -f bootstrap/root-application.yaml
```

After it lands, expect to see `argocd`, `nvisionx-development` (AppProject),
the cluster `Secret`, and the `applications` ApplicationSet appear within
~30 seconds:

```bash
AWS_PROFILE=nvisionx-development \
  kubectl -n argocd get applications,applicationsets,appprojects
```

The bootstrap is intentionally not committed as an `Application` managed by
ArgoCD itself — it would be circular. Updating `bootstrap/root-application.yaml`
later requires re-running the same `kubectl apply` to push the new spec into
the in-cluster CR.

## Repo access (Git credentials)

ArgoCD's `repo-server` clones this repo every reconcile to render manifests.
Today the repo is **public**, so no credentials are needed — anonymous
`git clone` works and ArgoCD requires no `repo-creds` Secret.

If this repo is moved back to private, ArgoCD will need read credentials. Two
supported options:

- **GitHub App** (recommended) — install a GitHub App with `Contents: Read` on
  this repo (or org-wide on `Nvision-x/*`), then create an ArgoCD
  `repo-creds`-labeled `Secret` in the `argocd` namespace with the App ID,
  installation ID, and private key. Credentials auto-rotate, no person
  dependency.
- **Personal Access Token** — a PAT with `repo` scope (classic) or
  `Contents: Read` (fine-grained), stored as a `repo-creds`-labeled `Secret`
  with `username: x-access-token` and `password: <PAT>`. Simpler but ties the
  cluster's read access to one user's token lifecycle.

Note: the existing `default/github-cr-secret` in the cluster is a
`dockerconfigjson` Secret with `read:packages` scope only — it's for image
pulls from GHCR and **cannot** authorize `git clone`. A separate Secret is
required if going private.

## Accessing the ArgoCD UI

The `argocd-server` Service is exposed to the tailnet via the Tailscale
Kubernetes operator (`loadBalancerClass: tailscale` set in `argocd/values.yaml`).
Once ArgoCD has self-applied those values, the UI is reachable from any
tailnet member at:

```
http://argocd.<your-tailnet>.ts.net
```

It is plain HTTP because `server.insecure: true` is set — Tailscale provides
the encrypted transport (WireGuard); no certificates needed.

### Get the admin password

ArgoCD generates a random admin password on first install and stores it in the
`argocd-initial-admin-secret` Secret. Retrieve it with:

```bash
AWS_PROFILE=nvisionx-development \
  kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo
```

Username: `admin`. Share with the team via your usual secret-sharing channel.

The Secret is deleted by ArgoCD the first time the admin password is changed
through the UI/CLI. If you want a stable team password that survives reinstall,
pin a bcrypt hash in `argocd/values.yaml` under
`configs.secret.argocdServerAdminPassword` instead — but until then, the
auto-generated value is what's in use.

### CLI access

Because `server.insecure: true` is set, the `argocd` CLI must connect with
`--plaintext`:

```bash
argocd login argocd.<your-tailnet>.ts.net --plaintext --username admin
```
