#!/usr/bin/env bash
# Inicializa (si hace falta), desella y configura OpenBao del hub. Idempotente: se puede relanzar.
#   bootstrap/scripts/openbao-configure.sh
#
# Pasos (todo con `kubectl exec` sobre el pod del StatefulSet 'openbao'):
#  1. init con 1 share / umbral 1 (laboratorio) si no esta inicializado. La salida JSON (claves + root token)
#     va directa al fichero ~/.config/homelab/openbao-hub-init.json (dir 700, fichero 600, fuera de git).
#     Nunca se imprime. Si el fichero ya existe y OpenBao NO esta inicializado, aborta (no lo sobrescribe).
#  2. unseal si esta sellado.
#  3. motor KV v2 en 'kv'.
#  4. policy 'eso-read': lectura de kv/data/platform/* (+ lectura/listado de kv/metadata/platform/*).
#  5. auth kubernetes: kubernetes_host=https://kubernetes.default.svc:443; usa el token y la CA del propio pod
#     (el chart crea el ClusterRoleBinding system:auth-delegator para su ServiceAccount).
#  6. rol 'eso' ligado al ServiceAccount external-secrets/external-secrets con la policy 'eso-read'.
#  7. siembra kv/platform/s3 (access-key, secret-key) y kv/platform/grafana (admin-user=admin, admin-password)
#     SOLO si no existen; los aleatorios se generan dentro del pod y nunca salen de el. `-cas=0` hace la
#     creacion atomica (falla si alguien la creo en medio).
# Solo imprime rutas y estados. Requiere: kubectl, jq. Variables: KUBE_CONTEXT, BAO_NAMESPACE, BAO_POD, BAO_INIT_FILE.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=openbao-lib.sh
source "$DIR/openbao-lib.sh"
need kubectl; need jq

find_pod
state="$(bao_state)"
log "estado inicial: $state"

# 1. init
case "$state" in
  initialized=false*)
    if [ -e "$BAO_INIT_FILE" ]; then
      die "OpenBao no esta inicializado pero ya existe $BAO_INIT_FILE (de otra instalacion). Muevelo a mano y relanza."
    fi
    ( umask 077; mkdir -p "$(dirname "$BAO_INIT_FILE")"; chmod 700 "$(dirname "$BAO_INIT_FILE")" )
    tmp="$(umask 077; mktemp "$BAO_INIT_FILE.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    log "inicializando (1 share, umbral 1)"
    bao_plain operator init -key-shares=1 -key-threshold=1 -format=json </dev/null >"$tmp" 2>/dev/null \
      || die "operator init fallo"
    jq -e '.root_token and (.unseal_keys_b64|length==1)' "$tmp" >/dev/null || die "salida de init inesperada"
    chmod 600 "$tmp"; mv -f "$tmp" "$BAO_INIT_FILE"; trap - EXIT
    log "claves guardadas en $BAO_INIT_FILE (600); haz copia segura de ese fichero"
    state="$(bao_state)"
    ;;
esac

# 2. unseal
case "$state" in
  *sealed=true) log "desellando"; do_unseal ;;
esac
case "$(bao_state)" in *sealed=false) ;; *) die "OpenBao sigue sellado" ;; esac
chmod 600 "$BAO_INIT_FILE" 2>/dev/null || true
load_root_token

# 3. KV v2 en 'kv'
if bao_tok secrets list -format=json </dev/null | jq -e 'has("kv/")' >/dev/null; then
  log "kv/ ya habilitado"
else
  log "habilitando kv/ (v2)"
  bao_tok secrets enable -path=kv -version=2 kv </dev/null >/dev/null
fi

# 4. policy de solo lectura
log "policy eso-read (kv/data/platform/*, kv/metadata/platform/*)"
bao_tok policy write eso-read - >/dev/null <<'EOF'
path "kv/data/platform/*" {
  capabilities = ["read"]
}
path "kv/metadata/platform/*" {
  capabilities = ["read", "list"]
}
EOF

# 5. auth kubernetes
if bao_tok auth list -format=json </dev/null | jq -e 'has("kubernetes/")' >/dev/null; then
  log "auth/kubernetes ya habilitado"
else
  log "habilitando auth/kubernetes"
  bao_tok auth enable kubernetes </dev/null >/dev/null
fi
log "auth/kubernetes/config (host https://kubernetes.default.svc:443, token y CA del pod)"
bao_tok write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc:443 </dev/null >/dev/null

# 6. rol eso
log "auth/kubernetes/role/eso -> external-secrets/external-secrets (policy eso-read)"
bao_tok write auth/kubernetes/role/eso \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  token_policies=eso-read token_ttl=1h </dev/null >/dev/null

# 7. siembra (solo si no existe). Los valores aleatorios se generan y consumen dentro del pod.
seed() { # $1 = ruta bajo kv/ ; $2 = script sh (dentro del pod) que escribe el JSON por stdout
  local path="$1" rc=0
  bao_tok kv metadata get "kv/$path" </dev/null >/dev/null 2>&1 || rc=$?
  if [ "$rc" = 0 ]; then log "kv/$path ya existe: no se toca"; return 0; fi
  [ "$rc" = 2 ] || die "no se pudo consultar kv/$path (codigo $rc)"
  log "sembrando kv/$path (valores aleatorios, no se muestran)"
  bao_tok_sh "$2 | bao kv put -cas=0 kv/$path - >/dev/null" </dev/null
}
rnd='tr -dc A-Za-z0-9 </dev/urandom | head -c'
seed platform/s3 "printf '{\"access-key\":\"%s\",\"secret-key\":\"%s\"}' \"\$(tr -dc A-Z0-9 </dev/urandom | head -c 20)\" \"\$($rnd 40)\""
seed platform/grafana "printf '{\"admin-user\":\"admin\",\"admin-password\":\"%s\"}' \"\$($rnd 32)\""

log "listo. Rutas: kv/platform/s3, kv/platform/grafana. Siguiente: comprobar que el ClusterSecretStore 'openbao' esta Ready."
