#!/usr/bin/env bash
# Crea el clúster hub desde cero: kind + Cilium + Argo CD + app raiz. Despues Argo CD lo gestiona todo.
#   RECREATE=1   borra el clúster si ya existe
set -euo pipefail
CLUSTER="${CLUSTER:-hub}"
CILIUM_VERSION="${CILIUM_VERSION:-1.20.4}"
WAIT_APPS_TIMEOUT="${WAIT_APPS_TIMEOUT:-900}"
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT"
export PATH="$HOME/.local/bin:$PATH"
REG=kind-registry; REG_PORT=5001
log() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

for c in docker kind kubectl helm kustomize; do command -v "$c" >/dev/null || { echo "falta $c (scripts/install-tools.sh)"; exit 1; }; done
docker info >/dev/null 2>&1 || { echo "docker no responde"; exit 1; }

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  [ "${RECREATE:-0}" = 1 ] && kind delete cluster --name "$CLUSTER" || { echo "el clúster $CLUSTER ya existe (RECREATE=1 para recrearlo)"; exit 1; }
fi

log "1/6 kind: $CLUSTER"
kind create cluster --config "bootstrap/kind/$CLUSTER.yaml" --wait 0s
kubectl config use-context "kind-$CLUSTER" >/dev/null

log "2/6 registry local (localhost:$REG_PORT)"
docker inspect "$REG" >/dev/null 2>&1 || docker run -d --restart=always -p "127.0.0.1:$REG_PORT:5000" --network bridge --name "$REG" registry:2 >/dev/null
for node in $(kind get nodes --name "$CLUSTER"); do
  docker exec "$node" mkdir -p "/etc/containerd/certs.d/localhost:$REG_PORT"
  printf '[host."http://%s:5000"]\n' "$REG" | docker exec -i "$node" tee "/etc/containerd/certs.d/localhost:$REG_PORT/hosts.toml" >/dev/null
done
docker network connect kind "$REG" 2>/dev/null || true

log "3/6 Cilium $CILIUM_VERSION"
helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo update cilium >/dev/null
helm upgrade --install cilium cilium/cilium --version "$CILIUM_VERSION" -n kube-system \
  -f bootstrap/cilium/values.yaml --set "k8sServiceHost=${CLUSTER}-control-plane" --wait --timeout 420s
kubectl wait --for=condition=Ready nodes --all --timeout=180s

log "4/6 Argo CD (Kustomize, server-side apply)"
kustomize build bootstrap/argocd | kubectl apply --server-side --force-conflicts -f - >/dev/null
for d in argocd-server argocd-repo-server argocd-applicationset-controller argocd-redis; do
  kubectl -n argocd rollout status "deploy/$d" --timeout=300s
done
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

log "5/6 aplicacion raiz (Argo CD lee este repo, publico)"
kubectl apply -f "bootstrap/root-$CLUSTER.yaml"

log "6/6 esperando a que Argo CD sincronice todas las apps (max ${WAIT_APPS_TIMEOUT}s)"
deadline=$((SECONDS + WAIT_APPS_TIMEOUT)); last=""
while (( SECONDS < deadline )); do
  out=$(kubectl -n argocd get applications.argoproj.io --no-headers \
        -o custom-columns=APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null || true)
  [ "$out" != "$last" ] && { echo "$out"; echo "--"; last="$out"; }
  if [ -n "$out" ] && ! grep -qvE '[[:space:]]Synced[[:space:]]+Healthy$' <<<"$out"; then echo "todas las apps Synced/Healthy"; exit 0; fi
  sleep 10
done
echo "TIMEOUT esperando a las apps"; exit 1
