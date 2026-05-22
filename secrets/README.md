# One-time bootstrap secrets

GitOps can't store credentials in plain YAML on GitHub. These two secrets are
applied once with `kubectl apply` and live only inside the cluster.

If you ever rebuild the kind cluster, re-run these two `kubectl` blocks.

For a production setup you'd swap this manual step for sealed-secrets,
external-secrets-operator, or SOPS — all of which let you commit *encrypted*
secrets safely. Out of scope for this learning setup.

---

## 1. ARC PAT — lets the runner controller register self-hosted runners

Required by: `argocd/apps/arc-runners-kanban.yml`

Create a fine-grained PAT at
<https://github.com/settings/personal-access-tokens/new>:

- Resource owner: `Finboconnect`
- Repository access: `Only select repositories` → `kanban-app`
- Repository permissions:
  - **Administration: Read and write**  (register runners)
  - **Actions: Read**                   (see queued jobs)
  - **Metadata: Read**                  (default)

Then apply it:

```sh
kubectl create namespace arc-runners --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic kanban-runner-pat \
  --namespace arc-runners \
  --from-literal=github_token='github_pat_PASTE_HERE'
```

## 2. Git PAT — lets Argo CD Image Updater push image bumps back to the repo

Required by: write-back annotations on `kanban-dev.yml` and `kanban-prod.yml`.

Create another fine-grained PAT (or reuse the one above if its scope covers
this repo too):

- Resource owner: `Finboconnect`
- Repository access: `Only select repositories` → `kubernetes-local`
- Repository permissions:
  - **Contents: Read and write**       (push commits)
  - **Metadata: Read**                  (default)

Then apply it:

```sh
kubectl apply -n argocd -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: argocd-image-updater-git
  namespace: argocd
type: Opaque
stringData:
  username: git
  password: github_pat_PASTE_HERE
EOF
```

The image-updater annotations on the kanban Applications reference this
secret by name:

```yaml
argocd-image-updater.argoproj.io/write-back-method: git:secret:argocd/argocd-image-updater-git
```
