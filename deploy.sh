#!/usr/bin/env bash

set -eou pipefail

case "${1:-}" in 
  local) ctx=minikube ;;
  prod) ctx=takovibe-prod ;;
  *) echo "usage: $0 local|prod" >&2; exit 1 ;;
esac

kubectl --context "$ctx" apply -k "overlays/$1"
for f in "overlays/$1"/secrets/*.enc.yaml; do
  sops -d "$f" | kubectl --context "$ctx" apply -f -
done
