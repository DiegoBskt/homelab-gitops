# Runbook: OpenBao + External Secrets

Componentes: OpenBao 2.7.2 (chart `openbao/openbao-helm` 0.30.6, standalone, almacenamiento `pebbledb` en un PVC de 1 Gi, HTTP en
`openbao.openbao.svc.cluster.local:8200`, UI en `https://openbao.hub.localtest.me`), External Secrets Operator 2.14.0 y los
`ExternalSecret` de `apps/platform-secrets`.

> Laboratorio: 1 share de unseal / umbral 1, y el *root token* se usa para configurar. Las claves se guardan en
> `~/.config/homelab/openbao-hub-init.json` (dir 700, fichero 600, **fuera de git**; `.gitignore` cubre `openbao-keys*`).
> Haz una copia en un gestor de contraseñas: **si pierdes el fichero y el PVC se reinicia, los datos de OpenBao son irrecuperables**.

Los scripts se ejecutan desde WSL con `kubectl` apuntando a `kind-hub` (variable `KUBE_CONTEXT`, por defecto `kind-hub`). Necesitan `kubectl` y `jq`.
Nunca imprimen claves, tokens ni valores; no pasan secretos por argumentos (usan stdin).

## 1. Primera puesta en marcha (gate manual)
Argo CD sincroniza la app `openbao` (Healthy aunque este sin inicializar: la readiness usa `sealedcode=204&uninitcode=204`).
Despues, una sola vez:

```bash
bootstrap/scripts/openbao-configure.sh
```

Hace, de forma idempotente: `init` (1/1) si hace falta y guarda las claves; `unseal`; habilita KV v2 en `kv`; policy `eso-read`
(lectura de `kv/data/platform/*` y `kv/metadata/platform/*`); `auth/kubernetes` con `kubernetes_host=https://kubernetes.default.svc:443`
(token y CA del propio pod); rol `eso` ligado al ServiceAccount `external-secrets/external-secrets`; y siembra
`kv/platform/s3` (`access-key`, `secret-key`) y `kv/platform/grafana` (`admin-user=admin`, `admin-password`) con valores aleatorios
**solo si no existen**. Relanzarlo es seguro (no regenera secretos existentes, no re-inicializa).

Comprobacion (el ClusterSecretStore pasa a `Valid`/`Ready` y los ExternalSecret a `SecretSynced`):

```bash
kubectl --context kind-hub get clustersecretstore openbao
kubectl --context kind-hub get externalsecret -A
```

## 2. Unseal tras reiniciar WSL / Docker / el pod
OpenBao arranca **sellado** tras cualquier reinicio del pod. El PVC conserva los datos.

```bash
bootstrap/scripts/openbao-unseal.sh
```

Si esta inicializado y sellado, usa la clave del fichero; si ya esta desellado no hace nada. Mientras este sellado, ESO no puede
leer (los Secret ya creados siguen existiendo; los ExternalSecret quedan en error hasta el unseal) y la UI muestra la pantalla de unseal.

## 3. Rotar un secreto y como lo ve ESO
Ejemplo: nueva contraseña de Grafana, sin que el valor aparezca en la linea de comandos ni en el historial. Obten el token con
`jq -r .root_token ~/.config/homelab/openbao-hub-init.json` solo dentro de una tuberia hacia el pod (no lo imprimas):

```bash
POD=$(kubectl --context kind-hub -n openbao get pod -l app.kubernetes.io/name=openbao,component=server -o jsonpath='{.items[0].metadata.name}')
# genera dentro del pod y escribe como nueva version (admin-user se conserva con "patch")
{ jq -r .root_token ~/.config/homelab/openbao-hub-init.json; } | kubectl --context kind-hub -n openbao exec -i "$POD" -c openbao -- sh -c '
  IFS= read -r BAO_TOKEN; export BAO_TOKEN BAO_ADDR=http://127.0.0.1:8200
  printf "{\"admin-password\":\"%s\"}" "$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)" | bao kv patch kv/platform/grafana -'
```

(`bao kv patch` crea una nueva version conservando `admin-user`; `bao kv rollback -version=N kv/platform/grafana` vuelve atras.)
Tambien puede hacerse desde la UI (Secrets → kv → platform → grafana → Create new version).

Como lo ve ESO: cada `ExternalSecret` tiene `refreshInterval: 15m`, asi que el Secret de Kubernetes se actualiza en <= 15 min. Para
forzarlo: `kubectl --context kind-hub -n observability annotate externalsecret grafana-admin force-sync=$(date +%s) --overwrite`.
Los pods **no se reinician solos**: Grafana lee `GF_SECURITY_ADMIN_PASSWORD` al arrancar, asi que reinicia el Deployment
(`kubectl rollout restart`). OJO: la contraseña de admin de Grafana, una vez creada la base de datos, solo cambia por su API/CLI
(`grafana cli admin reset-admin-password`), no por la variable de entorno.

Rotar `kv/platform/s3` exige cambiar a la vez SeaweedFS (`seaweedfs-s3-config` se regenera con el mismo origen) y los clientes S3
(Mimir, Loki, Tempo leen `s3-credentials` por variables de entorno → reiniciarlos). Hazlo en una ventana de mantenimiento.

## 4. Problemas habituales
| Sintoma | Causa / solucion |
|---|---|
| App `openbao` Healthy pero UI en "sealed" | Esperado tras reiniciar: `openbao-unseal.sh`. |
| ClusterSecretStore `InvalidProviderConfig` / 403 | Falta `openbao-configure.sh` o el rol `eso` no coincide con SA `external-secrets/external-secrets`. |
| `permission denied` en `auth/kubernetes/login` | El ServiceAccount de OpenBao necesita `system:auth-delegator` (el chart crea el ClusterRoleBinding). |
| Metricas `/v1/sys/metrics` con 503 | Sellado; vuelve al desellar. |
