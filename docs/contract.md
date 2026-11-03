# Contrato de interfaces (v2, fase 3)

Fuente de verdad para quien escriba manifiestos de un componente. Los nombres, puertos, rutas y propietarios de
esta pagina son **fijos**. Si algo no encaja, se reporta en el informe final; no se cambia por cuenta propia.

## 0. Reglas de trabajo (aplican a todos los componentes)
1. **Solo se escribe en los ficheros propios** (seccion 3). No se editan ficheros de otro componente ni `docs/versions.md`,
   `clusters/hub/applications/kustomization.yaml` ni `docs/contract.md`: de la integracion se encarga el orquestador.
2. **No se muta el clúster**: nada de `kubectl apply/delete/create/patch`, `helm install/upgrade`. La validacion es offline
   (`scripts/validate.sh <destino>`). `kubectl get/describe/logs` de solo lectura esta permitido.
3. **Sin git**: no se ejecuta ningun comando de git que cambie estado (commit, checkout, push...).
4. **Sin secretos en ficheros**: ningun valor secreto (ni de ejemplo reutilizable). Los charts consumen `Secret` ya existentes.
5. **Versiones fijadas** (chart, imagen, manifiestos remotos). Nunca `latest`.
6. **Verificar antes de adoptar**: repositorio y chart vigentes, version actual y **estado de mantenimiento** (archivado,
   retirado, movido). Ejemplos reales: ingress-nginx esta retirado; MinIO archivado; los charts de Loki pasaron a
   `grafana-community`. Si un chart o proyecto esta archivado o deprecado, se busca el sustituto y se reporta.
7. Todo contenedor lleva `requests` y `limits` de memoria (y `requests` de CPU). `securityContext` restrictivo si el chart lo permite.
8. Kustomize es la interfaz: `apps/<app>/{base,overlays/hub}`. Helm solo mediante `helmCharts:` (OCI o repo http).
   La `Application` va en `clusters/hub/applications/<app>.yaml` (plantilla en la seccion 12).
9. Los **Namespace los crea `apps/namespaces`**: no se definen manifiestos `Namespace`.
10. Comentarios y documentacion en español; identificadores y claves YAML en ingles.

## 1. Entorno
- kind `hub`: 1 control-plane + 2 workers, Kubernetes v1.37, **Cilium 1.20.4** (sin kube-proxy), StorageClass por defecto `standard` (local-path).
- Argo CD v3.5.7 con `--enable-helm` y diff del lado servidor; las apps usan `ServerSideApply=true`.
- Envoy Gateway v1.9.3 (Gateway API v1). CRDs de Gateway API y de Envoy ya instalados. Gateway `eg` en `gateway-system`.
- **Aun no existen** los CRDs de cert-manager, External Secrets ni ningun otro de esta fase.
- Acceso desde el host: `*.hub.localtest.me` → 127.0.0.1 → Gateway (80/443).

## 2. Clústeres y etiquetas
| Clúster | Contexto kubectl | Estado |
|---|---|---|
| `hub` | `kind-hub` | activo |
| `spoke-1` | `kind-spoke-1` | mas adelante |

Toda señal lleva la etiqueta/atributo **`cluster=<nombre>`** (ademas de `k8s.cluster.name`). Mimir y Loki: **un solo tenant**
(`multitenancy_enabled: false` / `auth_enabled: false`). En Loki los puntos de los atributos OTLP pasan a `_` (p. ej. `k8s_namespace_name`).

## 3. Propiedad de ficheros
| ID | Componentes | Rutas que puede escribir |
|---|---|---|
| **A** | cert-manager, OpenBao, External Secrets, `platform-secrets`, TLS del Gateway | `apps/{cert-manager,openbao,external-secrets,platform-secrets}/**`, `clusters/hub/applications/{cert-manager,openbao,external-secrets,platform-secrets}.yaml`, `bootstrap/scripts/openbao-*.sh`, `docs/runbooks/{openbao,trust-local-ca}.md`, y **solo** en `apps/envoy-gateway/base/` añadir el listener `https` y el `Certificate` comodin |
| **B** | Almacenamiento S3 (SeaweedFS) y Mimir | `apps/{seaweedfs,mimir}/**`, `clusters/hub/applications/{seaweedfs,mimir}.yaml` |
| **C** | Loki y Tempo | `apps/{loki,tempo}/**`, `clusters/hub/applications/{loki,tempo}.yaml` |
| **D** | Colectores OpenTelemetry, kube-state-metrics, node-exporter | `apps/{otel-collector,kube-state-metrics,node-exporter}/**`, `clusters/hub/applications/{otel-collector,kube-state-metrics,node-exporter}.yaml` |
| **E** | Grafana, Headlamp, ruta de Hubble UI | `apps/{grafana,headlamp,hubble-route}/**`, `clusters/hub/applications/{grafana,headlamp,hubble-route}.yaml` |

## 4. Namespaces (los crea `apps/namespaces`)
`cert-manager`, `openbao`, `external-secrets`, `storage`, `observability`, `headlamp`. Ya existen: `argocd`, `envoy-gateway-system`,
`gateway-system`, `kube-system`.

## 5. Servicios (nombre y puerto exactos; usar `fullnameOverride` o un `Service` adicional)
| Servicio | Puertos / rutas |
|---|---|
| `seaweedfs-s3.storage.svc.cluster.local` | `8333` HTTP, **path-style**, region `us-east-1` |
| `mimir.observability.svc.cluster.local` | `8080`: push `/api/v1/push`, OTLP `/otlp`, consulta `/prometheus` |
| `loki.observability.svc.cluster.local` | `3100`: push `/loki/api/v1/push`, OTLP `/otlp`, consulta `/loki` |
| `tempo.observability.svc.cluster.local` | `3200` consulta HTTP, `4317` OTLP gRPC, `4318` OTLP HTTP |
| `otel-gateway.observability.svc.cluster.local` | `4317` gRPC, `4318` HTTP (entrada OTLP de las apps) |
| `grafana.observability.svc.cluster.local` | `80` |
| `openbao.openbao.svc.cluster.local` | `8200` (HTTP dentro del clúster en esta version) |
| `argocd-server.argocd.svc.cluster.local` | `80` (modo `server.insecure`) |
| `headlamp.headlamp.svc.cluster.local` | `80` |
| `hubble-ui.kube-system.svc.cluster.local` | `80` (ya existe, lo crea Cilium) |

**Buckets S3:** `mimir-blocks`, `mimir-ruler`, `mimir-alertmanager`, `loki-chunks`, `loki-ruler`, `tempo-traces`.

## 6. Almacenamiento S3 (SeaweedFS) — resultados del spike
Chart `seaweedfs/seaweedfs` 4.52.0 (`https://seaweedfs.github.io/seaweedfs/helm`; proyecto activo, Apache-2.0). Verificado contra un
despliegue real: buckets via `createBuckets`, multipart (40 MiB, md5 identico), `ListObjectsV2` con prefijo y delimitador,
GET por rango, HEAD, copy, multi-delete, lifecycle, y rechazo con 403 sin credenciales / `SignatureDoesNotMatch` con credenciales erroneas.
- Usar **`allInOne.enabled: true`** y **desactivar `master.enabled`, `volume.enabled`, `filer.enabled`** (si no, el chart despliega
  tambien pods separados duplicados). `allInOne.affinity: ""` (una sola replica). Datos en PVC (`allInOne.data.type: persistentVolumeClaim`, 10Gi).
- Autenticacion: `allInOne.s3.enableAuth: true` y `allInOne.s3.existingConfigSecret: seaweedfs-s3-config` (clave `seaweedfs_s3_config`).
- El Service del chart se llama `<release>-seaweedfs-all-in-one`: hay que exponerlo ademas como **`seaweedfs-s3`** (puerto 8333).
- Peculiaridad: `ListObjectsV2` **no devuelve `KeyCount`**. Los clientes (minio-go, aws-sdk) lo toleran en las pruebas hechas con la CLI de AWS, pero no se ha
  probado con Mimir/Loki/Tempo: se comprobara en la integracion.
- Clientes S3: `endpoint seaweedfs-s3.storage.svc.cluster.local:8333`, `insecure/HTTP`, `region us-east-1`, **path-style forzado**,
  credenciales por variables de entorno (`-config.expand-env=true` en Mimir/Loki/Tempo) desde el Secret `s3-credentials`.

## 7. Secretos (OpenBao + External Secrets)
- OpenBao: motor **KV v2** montado en `kv`; autenticacion de ESO por **Kubernetes auth** (`auth/kubernetes`, rol `eso`, policy de solo lectura sobre `kv/data/platform/*`).
- `ClusterSecretStore` **`openbao`** (provider `vault`, `server: http://openbao.openbao.svc.cluster.local:8200`, `path: kv`, `version: v2`,
  auth kubernetes con `serviceAccountRef` = `external-secrets/external-secrets`). apiVersion `external-secrets.io/v1`.
- **Todos los `ExternalSecret` viven en `apps/platform-secrets` (A).** El resto de componentes solo referencian Secrets ya existentes (`existingSecret`).

| Origen en OpenBao | Secret de Kubernetes (namespaces) | Claves |
|---|---|---|
| `kv/platform/s3` (`access-key`, `secret-key`) | `s3-credentials` (`observability`) | `access-key`, `secret-key`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
| `kv/platform/s3` | `seaweedfs-s3-config` (`storage`) | `seaweedfs_s3_config`: JSON `{"identities":[{"name":"platform","credentials":[{"accessKey":…,"secretKey":…}],"actions":["Admin","Read","Write","List","Tagging"]}]}` construido con `target.template` |
| `kv/platform/grafana` (`admin-user`, `admin-password`) | `grafana-admin` (`observability`) | `admin-user`, `admin-password` |

- **Siembra y arranque de OpenBao (A escribe los scripts; los ejecuta el orquestador):**
  `bootstrap/scripts/openbao-configure.sh` (idempotente) hace: `init` (1 share / umbral 1, laboratorio) si no esta inicializado, guarda las claves en
  `~/.config/homelab/openbao-hub-init.json` con permisos 600 (**fuera de git, nunca se imprimen**), `unseal`, habilita `kv` v2, crea la policy y el rol `eso`,
  configura `auth/kubernetes`, y siembra `kv/platform/s3` y `kv/platform/grafana` con valores **aleatorios** solo si no existen. Solo imprime rutas, nunca valores.
  `bootstrap/scripts/openbao-unseal.sh` hace unseal con ese fichero (tras reiniciar WSL). Se ejecutan con `kubectl exec` sobre el pod de OpenBao.

## 8. TLS y entrada HTTP(S)
- `ClusterIssuer` **`local-ca`**: cadena `selfsigned` → Certificate raiz (`isCA`) → ClusterIssuer tipo CA. (Mas adelante `letsencrypt-dns`.)
- `Gateway` **`eg`** (`gateway-system`): listeners `http` (80, existente) y **`https` (443)** con `hostname: "*.hub.localtest.me"` y
  `certificateRefs: wildcard-hub-tls`. `Certificate` `wildcard-hub` en `gateway-system` (`*.hub.localtest.me`, `hub.localtest.me`, issuer `local-ca`). El proxy ya publica el 443 del host.
- Cada app publica un `HTTPRoute` en su namespace con `parentRefs: [{name: eg, namespace: gateway-system}]` (sin `sectionName`: atacha a http y https).
- Hostnames: `argocd`, `grafana`, `headlamp`, `openbao`, `hubble` + `.hub.localtest.me`.
- **Dentro del clúster se usa siempre el DNS del Service**, nunca `localtest.me` (resuelve a 127.0.0.1).

## 9. Telemetria
- **Colectores OpenTelemetry (D)**: agente por nodo (logs con `filelog`, metricas de kubelet/cAdvisor, node) y gateway (`otel-gateway`: OTLP de las apps, scraping
  Prometheus, enrutado). Todo en `observability`.
- Atributos de recurso: `cluster=hub`, `k8s.cluster.name=hub`, `k8s.namespace.name`, `k8s.pod.name`, `k8s.container.name`, `service.name`, `k8s.node.name`.
- Metricas → Mimir: `prometheusremotewrite` a `http://mimir.observability.svc.cluster.local:8080/api/v1/push` con `external_labels: {cluster: hub}` (o OTLP a `/otlp`).
  **Los nombres de metrica y los valores del label `job` deben ser los de Prometheus clasico** para que sirvan los dashboards estandar:

| `job` | Fuente |
|---|---|
| `kubelet`, `cadvisor` | kubelet `:10250` (`/metrics`, `/metrics/cadvisor`) |
| `kube-state-metrics`, `node-exporter` | los dos componentes de D |
| `cilium-agent` (`:9962`), `cilium-operator` (`:9963`), `hubble` (`:9965`) | Cilium (ns `kube-system`) |
| `envoy-gateway` (controller), `envoy-proxy` | Envoy Gateway |
| `argocd-*` | Argo CD (`argocd-metrics`, `argocd-server-metrics`, `argocd-repo-server`...) |
| resto | cualquier pod con anotaciones `prometheus.io/scrape: "true"`, `prometheus.io/port`, `prometheus.io/path` |

- **Regla para A, B, C, E:** sus pods exponen metricas y llevan esas anotaciones `prometheus.io/*` (via `podAnnotations` del chart). No hay CRDs de Prometheus Operator
  (no se usan `ServiceMonitor`).
- Logs → Loki por OTLP (`http://loki.observability.svc.cluster.local:3100/otlp`). Loki indexa como labels: `cluster`, `k8s.namespace.name`, `k8s.pod.name`,
  `k8s.container.name`, `service.name`, `k8s.node.name` (C lo configura en `otlp_config`).
- Trazas → Tempo (`tempo.observability.svc.cluster.local:4317`).
- **Grafana (E):** datasources Mimir (`/prometheus`), Loki y Tempo aprovisionados, con correlacion traza↔logs (por `k8s.pod.name`/`k8s.namespace.name`),
  traza↔metricas y logs→traza. Dashboards como codigo (ConfigMaps o provisioning desde el repo), con licencia compatible anotada.

## 10. Olas de sincronizacion (`argocd.argoproj.io/sync-wave` en la Application)
| Ola | Componentes |
|---|---|
| -1 | `namespaces` |
| 0 | cert-manager, CRDs de ESO, Envoy Gateway (existente) |
| 1 | OpenBao (**gate manual**: init/unseal/configuracion), ESO + `ClusterSecretStore`, `ClusterIssuer`/CA, `platform-secrets` |
| 2 | SeaweedFS |
| 3 | Mimir, Loki, Tempo |
| 4 | otel-collector, kube-state-metrics, node-exporter, Grafana |
| 5 | Headlamp, hubble-route, dashboards y alertas |

Las waves entre Applications **no** bloquean a las hijas: cada Application lleva `retry` y `SkipDryRunOnMissingResource=true`, y los recursos que dependen de CRDs
de la misma app llevan `sync-wave` mayor (CRDs y chart en 0, CRs en 1+).

## 11. Presupuesto de recursos (orientativo, **sin medir**; requests de memoria)
A: cert-manager + ESO + OpenBao ≤ 700 MiB · B: SeaweedFS ≤ 600 MiB, Mimir ≤ 2,5 GiB · C: Loki ≤ 1 GiB, Tempo ≤ 800 MiB · D: colectores + KSM + node-exporter ≤ 1,2 GiB ·
E: Grafana ≤ 500 MiB, Headlamp ≤ 200 MiB. Todo en modo minimo de laboratorio (1 replica, sin zonas, sin caches memcached, PVC pequeños en `standard`).

## 12. Plantilla de `Application`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app>
  namespace: argocd
  annotations: {argocd.argoproj.io/sync-wave: "<ola>"}
spec:
  project: platform
  source:
    repoURL: https://github.com/DiegoBskt/homelab-gitops.git
    targetRevision: main
    path: apps/<app>/overlays/hub
  destination: {server: https://kubernetes.default.svc, namespace: <ns>}
  syncPolicy:
    automated: {prune: true, selfHeal: true}
    syncOptions: [ServerSideApply=true, SkipDryRunOnMissingResource=true]
    retry: {limit: 5, backoff: {duration: 10s, factor: 2, maxDuration: 3m}}
```
No usar `group: ""` en `ignoreDifferences` (Argo CD lo descarta y la app padre queda `OutOfSync`).

## 13. Informe final obligatorio
Lista de ficheros creados; para cada componente una fila `componente | fuente (chart/manifiesto) | version | fecha de verificacion | estado de mantenimiento | evidencia`;
resultado de `scripts/validate.sh <destinos>`; **desviaciones del contrato** y por que; `requests` de memoria totales; pasos manuales necesarios; dudas abiertas.
