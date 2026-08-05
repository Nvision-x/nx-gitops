# Bootstrap (fresh cluster, one-time)

```sh
helm registry login ghcr.io
helm install argocd oci://ghcr.io/nvision-x/argocd --version <pin> -n argocd --create-namespace
kubectl apply -f bootstrap/root-application.yaml
```

`<pin>` = the `targetRevision` in `argocd/application.yaml`. After the root app syncs,
ArgoCD self-manages from this repo (full values in `argocd/values.yaml`).
