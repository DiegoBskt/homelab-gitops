#!/usr/bin/env bash
# Funciones comunes de openbao-configure.sh y openbao-unseal.sh (se cargan con `source`).
#
# Reglas de seguridad:
#  - Nunca se imprimen tokens, claves de unseal ni valores secretos (solo rutas y estados).
#  - Ningun secreto viaja en la linea de comandos (ni del host ni del pod): el token raiz y los valores
#    se pasan por stdin. Dentro del pod, `sh -c` lee la 1.ª linea de stdin hacia la variable BAO_TOKEN.
#  - El fichero de claves vive en ~/.config/homelab (700), con permisos 600, fuera de git.
# Variables de entorno opcionales: KUBE_CONTEXT (def. kind-hub), BAO_NAMESPACE (def. openbao),
# BAO_POD (def. se detecta por etiqueta), BAO_INIT_FILE.

: "${KUBE_CONTEXT:=kind-hub}"
: "${BAO_NAMESPACE:=openbao}"
: "${BAO_INIT_FILE:=$HOME/.config/homelab/openbao-hub-init.json}"
BAO_CONTAINER=openbao

set -euo pipefail
set +x   # por si el llamador activo xtrace: evita volcar valores en el log

log() { printf '[openbao] %s\n' "$*" >&2; }
die() { printf '[openbao] ERROR: %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "falta la herramienta '$1'"; }

kc() { kubectl --context "$KUBE_CONTEXT" -n "$BAO_NAMESPACE" "$@"; }

# Localiza el pod del servidor (StatefulSet 'openbao' -> openbao-0) y espera a que este Running
# (no hace falta Ready: sin inicializar/sellado la readiness ya devuelve 204, pero Running basta).
find_pod() {
  if [ -z "${BAO_POD:-}" ]; then
    BAO_POD="$(kc get pod -l app.kubernetes.io/name=openbao,component=server \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    [ -n "$BAO_POD" ] || die "no hay pod de OpenBao en el namespace '$BAO_NAMESPACE' (¿Application openbao sincronizada?)"
  fi
  log "pod: $BAO_POD"
  kc wait --for=jsonpath='{.status.phase}'=Running "pod/$BAO_POD" --timeout=180s >/dev/null \
    || die "el pod $BAO_POD no llega a Running"
  # Espera a que el proceso responda por HTTP (el contenedor puede estar arrancando).
  local i
  for i in $(seq 1 30); do
    if bao_plain status -format=json </dev/null >/dev/null 2>&1 || [ "$?" = 2 ]; then return 0; fi
    sleep 2
  done
  die "OpenBao no responde en el pod $BAO_POD"
}

# bao sin token. Argumentos = argumentos de `bao`. stdin del llamador pasa tal cual (p. ej. clave de unseal).
bao_plain() {
  kc exec -i "$BAO_POD" -c "$BAO_CONTAINER" -- \
    sh -c 'export BAO_ADDR=http://127.0.0.1:8200; exec bao "$@"' sh "$@"
}

# bao con token raiz. El token viaja por stdin (1.ª linea) y no aparece en ningun argv.
# El resto de stdin del llamador (payload) llega a `bao`. Requiere ROOT_TOKEN en el entorno del script.
bao_tok() {
  { printf '%s\n' "$ROOT_TOKEN"; cat; } | kc exec -i "$BAO_POD" -c "$BAO_CONTAINER" -- \
    sh -c 'export BAO_ADDR=http://127.0.0.1:8200; IFS= read -r BAO_TOKEN; export BAO_TOKEN; exec bao "$@"' sh "$@"
}

# Igual que bao_tok pero ejecuta un script sh dentro del pod (para generar aleatorios sin sacarlos del pod).
# Uso: bao_tok_sh '<script>'  (el script no debe contener secretos; BAO_TOKEN ya esta exportado).
bao_tok_sh() {
  { printf '%s\n' "$ROOT_TOKEN"; cat; } | kc exec -i "$BAO_POD" -c "$BAO_CONTAINER" -- \
    sh -c 'export BAO_ADDR=http://127.0.0.1:8200; IFS= read -r BAO_TOKEN; export BAO_TOKEN; eval "$1"' sh "$1"
}

# Estado: imprime "initialized=<bool> sealed=<bool>". `bao status` sale con 2 si esta sellado.
bao_state() {
  local out rc=0
  out="$(bao_plain status -format=json 2>/dev/null </dev/null)" || rc=$?
  [ "$rc" -le 2 ] || die "bao status fallo (codigo $rc)"
  printf 'initialized=%s sealed=%s' \
    "$(jq -r '.initialized' <<<"$out")" "$(jq -r '.sealed' <<<"$out")"
}

# Hace unseal con la clave del fichero. `bao operator unseal` no admite stdin sin TTY, asi que se usa la API
# (`bao write sys/unseal -`) con el JSON {"key": ...} por stdin: la clave no aparece en ningun argv. No imprime nada.
do_unseal() {
  [ -f "$BAO_INIT_FILE" ] || die "no existe $BAO_INIT_FILE (¿se inicializo OpenBao desde otro equipo?)"
  jq -ce '{key: .unseal_keys_b64[0]}' "$BAO_INIT_FILE" 2>/dev/null \
    | bao_plain write -format=json sys/unseal - >/dev/null \
    || die "unseal fallido (¿clave incorrecta en $BAO_INIT_FILE?)"
}

load_root_token() {
  [ -f "$BAO_INIT_FILE" ] || die "no existe $BAO_INIT_FILE"
  ROOT_TOKEN="$(jq -er '.root_token' "$BAO_INIT_FILE")" || die "$BAO_INIT_FILE sin root_token"
}
