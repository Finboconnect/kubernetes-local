#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./deploy.sh <env> [action]
#
# env     - one of the files in environments/ (dev, prod, ...), excluding
#           values.yml and platform.yml which are layered automatically.
# action  - install (default) | template | apply | uninstall | diff

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV="${1:-}"
ACTION="${2:-install}"

list_envs() {
  for f in environments/*.yml; do
    name="$(basename "$f" .yml)"
    case "$name" in
      values|platform) ;;
      *) echo "  - $name" ;;
    esac
  done
}

if [[ -z "$ENV" || "$ENV" == "-h" || "$ENV" == "--help" ]]; then
  cat <<EOF
Usage: $0 <env> [install|template|apply|uninstall|diff]

Available environments:
$(list_envs)

Examples:
  $0 dev                # helm upgrade --install into the dev namespace
  $0 prod template      # render manifests to stdout
  $0 dev apply          # helm template | kubectl apply -f -
  $0 dev uninstall      # helm uninstall the release
EOF
  exit 1
fi

ENV_FILE="environments/${ENV}.yml"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: environment file '$ENV_FILE' not found." >&2
  echo "Available environments:" >&2
  list_envs >&2
  exit 1
fi

# Pull the namespace out of the env file (simple, no yq dependency).
NAMESPACE="$(awk '/^namespace:/ {print $2; exit}' "$ENV_FILE")"
if [[ -z "$NAMESPACE" ]]; then
  echo "Error: 'namespace:' not set in $ENV_FILE." >&2
  exit 1
fi

RELEASE="kanban-${ENV}"

VALUES=(
  -f environments/values.yml
  -f environments/platform.yml
  -f "$ENV_FILE"
)

echo ">> env=${ENV}  release=${RELEASE}  namespace=${NAMESPACE}  action=${ACTION}"

case "$ACTION" in
  install|upgrade)
    helm upgrade --install "$RELEASE" . \
      --namespace "$NAMESPACE" \
      --create-namespace \
      "${VALUES[@]}"
    ;;
  template|render)
    helm template "$RELEASE" . \
      --namespace "$NAMESPACE" \
      "${VALUES[@]}"
    ;;
  apply)
    helm template "$RELEASE" . \
      --namespace "$NAMESPACE" \
      "${VALUES[@]}" \
      | kubectl apply -f -
    ;;
  diff)
    helm diff upgrade "$RELEASE" . \
      --namespace "$NAMESPACE" \
      "${VALUES[@]}"
    ;;
  uninstall|delete)
    helm uninstall "$RELEASE" --namespace "$NAMESPACE"
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    exit 1
    ;;
esac
