#!/usr/bin/env bash
# Hace unseal de OpenBao (hub) con la clave guardada en ~/.config/homelab/openbao-hub-init.json.
# Usalo tras reiniciar WSL / Docker / el pod: OpenBao arranca sellado (1 share, laboratorio).
#   bootstrap/scripts/openbao-unseal.sh
# Variables opcionales: KUBE_CONTEXT, BAO_NAMESPACE, BAO_POD, BAO_INIT_FILE. Solo imprime estados, nunca la clave.
# Requiere: kubectl, jq.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=openbao-lib.sh
source "$DIR/openbao-lib.sh"
need kubectl; need jq

find_pod
state="$(bao_state)"
log "estado inicial: $state"
case "$state" in
  initialized=false*) die "OpenBao no esta inicializado: ejecuta bootstrap/scripts/openbao-configure.sh" ;;
  *sealed=false)      log "ya esta desellado: nada que hacer"; exit 0 ;;
esac
do_unseal
state="$(bao_state)"
log "estado final: $state"
case "$state" in *sealed=false) log "OK" ;; *) die "sigue sellado" ;; esac
