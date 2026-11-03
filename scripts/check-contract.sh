#!/usr/bin/env bash
# Verifica que los manifiestos renderizados cumplen docs/contract.md (nombres, puertos, secretos, olas, recursos...).
# Independiente de lo que declare cada autor: renderiza con kustomize y comprueba sobre el resultado.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
export PATH="$HOME/.local/bin:$PATH"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
fail=0; warn=0
REQUIRE_TLS="${REQUIRE_TLS:-0}"   # 1 = exige listener https + Certificate (fase 4)
ok()   { printf 'OK     %s\n' "$*"; }
ko()   { printf 'FALLO  %s\n' "$*"; fail=1; }
tls_ko(){ if [ "$REQUIRE_TLS" = 1 ]; then ko "$*"; else aviso "pendiente (fase 4, REQUIRE_TLS=0): $*"; fi; }
aviso(){ printf 'AVISO  %s\n' "$*"; warn=$((warn+1)); }

APPS=(namespaces envoy-gateway cert-manager external-secrets openbao platform-secrets seaweedfs mimir loki tempo
      otel-collector kube-state-metrics node-exporter grafana headlamp hubble-route)
for a in "${APPS[@]}"; do
  ready=0
  for attempt in 1 2 3; do
    if kustomize build --enable-helm "apps/$a/overlays/hub" > "$OUT/$a.yaml" 2> "$OUT/$a.err"; then ready=1; break; fi
    grep -qE "(5[0-9]{2} |timeout|connection reset|EOF|TLS handshake)" "$OUT/$a.err" || break
    sleep $((attempt * 5))
  done
  [ "$ready" = 1 ] || { ko "build de apps/$a/overlays/hub"; sed 's/^/       /' "$OUT/$a.err" | head -5; }
done
J() { yq -o=json -I=0 '.' "$OUT/$1.yaml"; }   # un JSON por documento

# --- Servicios y puertos
svc() { local app=$1 ns=$2 name=$3; shift 3
  for p in "$@"; do
    if J "$app" | jq -e --arg ns "$ns" --arg n "$name" --argjson p "$p" \
        'select(.kind=="Service" and .metadata.name==$n and ((.metadata.namespace // $ns)==$ns)) | .spec.ports[]? | select(.port==$p)' >/dev/null 2>&1
    then ok "Service $ns/$name:$p  ($app)"; else ko "Service $ns/$name:$p NO esta en $app"; fi
  done; }
echo "== Servicios del contrato =="
svc seaweedfs      storage       seaweedfs-s3 8333
svc mimir          observability mimir 8080
svc loki           observability loki 3100
svc tempo          observability tempo 3200 4317 4318
svc otel-collector observability otel-gateway 4317 4318
svc grafana        observability grafana 80
svc openbao        openbao       openbao 8200
svc headlamp       headlamp      headlamp 80

echo; echo "== Buckets S3 (SeaweedFS) =="
for b in mimir-blocks mimir-ruler mimir-alertmanager loki-chunks loki-ruler tempo-traces; do
  if grep -q -- "$b" "$OUT/seaweedfs.yaml"; then ok "bucket $b"; else ko "bucket $b no aparece en el render de seaweedfs"; fi
done

echo; echo "== Secretos / External Secrets =="
es() { local ns=$1 target=$2
  if J platform-secrets | jq -e --arg ns "$ns" --arg t "$target" 'select(.kind=="ExternalSecret" and .metadata.namespace==$ns and (.spec.target.name==$t or (.spec.target.name==null and .metadata.name==$t)))' >/dev/null 2>&1
  then ok "ExternalSecret $ns/$target"; else ko "ExternalSecret $ns/$target ausente"; fi; }
es observability s3-credentials; es storage seaweedfs-s3-config; es observability grafana-admin
if J platform-secrets | jq -e 'select(.kind=="ExternalSecret") | .spec.secretStoreRef | select(.name=="openbao" and .kind=="ClusterSecretStore")' >/dev/null 2>&1; then ok "ExternalSecrets usan ClusterSecretStore/openbao"; else ko "ExternalSecrets sin ClusterSecretStore/openbao"; fi
if J external-secrets | jq -e 'select(.kind=="ClusterSecretStore" and .metadata.name=="openbao")' >/dev/null 2>&1; then ok "ClusterSecretStore openbao"; else ko "falta ClusterSecretStore openbao"; fi
if J cert-manager | jq -e 'select(.kind=="ClusterIssuer" and .metadata.name=="local-ca")' >/dev/null 2>&1; then ok "ClusterIssuer local-ca"; else ko "falta ClusterIssuer local-ca"; fi
# ningun Secret con datos en git
leak=0
for a in "${APPS[@]}"; do
  n=$(J "$a" | jq -c 'select(.kind=="Secret") | select((.data // {} | length)>0 or (.stringData // {} | length)>0) | .metadata.name' | wc -l)
  if [ "$n" -gt 0 ]; then ko "$a renderiza $n Secret(s) con datos: $(J "$a" | jq -r 'select(.kind=="Secret") | select((.data // {} | length)>0 or (.stringData // {} | length)>0) | .metadata.name' | tr '\n' ' ')"; leak=1; fi
done
[ "$leak" = 0 ] && ok "ningun Secret con datos en los renders"

echo; echo "== Gateway / TLS / rutas =="
if J envoy-gateway | jq -e 'select(.kind=="Gateway" and .metadata.name=="eg" and .metadata.namespace=="gateway-system") | .spec.listeners[] | select(.name=="https" and .port==443 and .hostname=="*.hub.localtest.me" and (.tls.certificateRefs[]?.name=="wildcard-hub-tls") and (.allowedRoutes.namespaces.from=="All"))' >/dev/null 2>&1
then ok "listener https:443 (*.hub.localtest.me, wildcard-hub-tls, rutas de todos los namespaces)"; else tls_ko "listener https incorrecto o ausente"; fi
if J envoy-gateway | jq -e 'select(.kind=="Gateway" and .metadata.name=="eg") | .spec.listeners[] | select(.name=="http" and .port==80)' >/dev/null 2>&1; then ok "listener http:80 intacto"; else ko "listener http:80 desaparecio"; fi
if J envoy-gateway | jq -e 'select(.kind=="Certificate" and .metadata.name=="wildcard-hub" and .metadata.namespace=="gateway-system" and .spec.issuerRef.name=="local-ca")' >/dev/null 2>&1; then ok "Certificate wildcard-hub (issuer local-ca)"; else tls_ko "falta Certificate wildcard-hub"; fi
route() { local host=$1 app
  for app in "${APPS[@]}" argocd; do
    [ -f "$OUT/$app.yaml" ] || { kustomize build --enable-helm "apps/$app/overlays/hub" > "$OUT/$app.yaml" 2>/dev/null || true; }
    if J "$app" 2>/dev/null | jq -e --arg h "$host" 'select(.kind=="HTTPRoute" and (.spec.hostnames[]? == $h) and (.spec.parentRefs[]? | select(.name=="eg" and .namespace=="gateway-system")))' >/dev/null 2>&1
    then ok "HTTPRoute $host  ($app)"; return; fi
  done; ko "no hay HTTPRoute para $host"; }
for h in argocd grafana headlamp openbao hubble; do route "$h.hub.localtest.me"; done

echo; echo "== Namespaces: solo los crea apps/namespaces =="
for a in "${APPS[@]}"; do
  [ "$a" = namespaces ] || [ "$a" = envoy-gateway ] && continue
  n=$(J "$a" | jq -r 'select(.kind=="Namespace") | .metadata.name' | tr '\n' ' ')
  [ -z "$n" ] && ok "$a no define Namespace" || ko "$a define Namespace: $n"
done

echo; echo "== Applications (olas, proyecto, ruta) =="
declare -A WAVE=( [namespaces]=-1 [envoy-gateway]=0 [cert-manager]=0 [external-secrets]=1 [openbao]=1 [platform-secrets]=1 [seaweedfs]=2
  [mimir]=3 [loki]=3 [tempo]=3 [otel-collector]=4 [kube-state-metrics]=4 [node-exporter]=4 [grafana]=4 [headlamp]=5 [hubble-route]=5 )
declare -A NS=( [cert-manager]=cert-manager [external-secrets]=external-secrets [openbao]=openbao [platform-secrets]=external-secrets [seaweedfs]=storage
  [mimir]=observability [loki]=observability [tempo]=observability [otel-collector]=observability [kube-state-metrics]=observability
  [node-exporter]=observability [grafana]=observability [headlamp]=headlamp [hubble-route]=kube-system )
for a in "${APPS[@]}"; do
  f="clusters/hub/applications/$a.yaml"; [ -f "$f" ] || { ko "falta $f"; continue; }
  w=$(yq '.metadata.annotations["argocd.argoproj.io/sync-wave"]' "$f"); proj=$(yq '.spec.project' "$f"); path=$(yq '.spec.source.path' "$f")
  retry=$(yq '.spec.syncPolicy.retry.limit' "$f"); dns=$(yq '.spec.destination.namespace' "$f")
  p=""; [ "$w" = "${WAVE[$a]}" ] || p="$p ola=$w(esperada ${WAVE[$a]})"
  [ "$proj" = platform ] || p="$p proyecto=$proj"
  [ "$path" = "apps/$a/overlays/hub" ] || p="$p ruta=$path"
  if [ "$a" != namespaces ] && [ "$retry" = null ]; then p="$p sinretry"; fi
  if [ -n "${NS[$a]:-}" ] && [ "$dns" != "${NS[$a]}" ]; then p="$p destino=$dns(esperado ${NS[$a]})"; fi
  [ -z "$p" ] && ok "Application $a (ola $w)" || ko "Application $a:$p"
done

echo; echo "== Recursos de memoria en cargas (requests y limits) =="
for a in "${APPS[@]}"; do
  miss=$(J "$a" | jq -r 'select(.kind|IN("Deployment","StatefulSet","DaemonSet","Job","CronJob")) | . as $o
     | [($o.spec.template.spec // $o.spec.jobTemplate.spec.template.spec) | (.containers[]?, .initContainers[]?)]
     | map(select((.resources.requests.memory // "")=="" or (.resources.limits.memory // "")=="") | "\($o.kind)/\($o.metadata.name):\(.name)") | .[]')
  if [ -z "$miss" ]; then ok "$a: todos los contenedores con requests/limits de memoria"; else aviso "$a sin requests/limits de memoria: $(echo "$miss" | tr '\n' ' ')"; fi
done

echo; echo "== Anotaciones prometheus.io/scrape en pods propios (informativo) =="
for a in cert-manager external-secrets openbao seaweedfs mimir loki tempo otel-collector kube-state-metrics node-exporter grafana; do
  n=$(J "$a" | jq -c 'select(.kind|IN("Deployment","StatefulSet","DaemonSet")) | select((.spec.template.metadata.annotations // {})["prometheus.io/scrape"]=="true") | .metadata.name' | wc -l)
  t=$(J "$a" | jq -c 'select(.kind|IN("Deployment","StatefulSet","DaemonSet")) | .metadata.name' | wc -l)
  [ "$n" -gt 0 ] && ok "$a: $n/$t cargas anotadas" || aviso "$a: ninguna de $t cargas lleva prometheus.io/scrape"
done

echo; [ "$fail" = 0 ] && echo "CONTRATO OK ($warn avisos)" || echo "CONTRATO CON FALLOS ($warn avisos)"
exit "$fail"
