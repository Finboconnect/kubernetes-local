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

## 3. Backstage Postgres credentials (per environment)

Required by: `apps/backstage/templates/deployment.yaml` and the bundled
Bitnami PostgreSQL subchart.

The Bitnami chart expects two keys in the secret:
- `postgres-password` — the `postgres` superuser password
- `password`          — the application user (`backstage`) password

Generate one secret per environment namespace (`backstage-dev`, `backstage-prod`):

```sh
ADMIN_PW=$(openssl rand -base64 24)
APP_PW=$(openssl rand -base64 24)

for NS in backstage-dev backstage-prod; do
  kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret generic backstage-postgres-creds \
    --namespace "$NS" \
    --from-literal=postgres-password="$ADMIN_PW" \
    --from-literal=password="$APP_PW" \
    --dry-run=client -o yaml \
  | kubeseal --format=yaml \
      --controller-name=sealed-secrets \
      --controller-namespace=kube-system \
      > "secrets/backstage-postgres-creds.${NS}.sealed.yaml"
done

unset ADMIN_PW APP_PW
```

(You'd typically generate two *different* admin/app passwords for the two
environments — modify the loop above accordingly. For learning, sharing them
is fine.)

## 4. Backstage GitHub token (per environment)

Required by: `apps/backstage/templates/deployment.yaml` (the Backstage app
itself uses this to read GitHub for catalog imports).

Create a PAT scoped to whatever repos Backstage should index:

```sh
read -rs GH_TOKEN     # paste github_pat_... or ghp_... here

for NS in backstage-dev backstage-prod; do
  kubectl create secret generic backstage-github-token \
    --namespace "$NS" \
    --from-literal=GITHUB_TOKEN="$GH_TOKEN" \
    --dry-run=client -o yaml \
  | kubeseal --format=yaml \
      --controller-name=sealed-secrets \
      --controller-namespace=kube-system \
      > "secrets/backstage-github-token.${NS}.sealed.yaml"
done

unset GH_TOKEN
```

After both loops, you'll have four new files in `secrets/`. Commit them — the
`.sealed.yaml` extension is allowed in `.gitignore` because the contents are
encrypted ciphertext.
