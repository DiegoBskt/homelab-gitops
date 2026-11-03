# Contrato de interfaces

Fuente de verdad para quien escriba manifiestos de un componente. Los nombres, puertos y rutas de
esta pagina son **fijos**: si algo no encaja, se reporta; no se cambia por cuenta propia.

## 1. Clústeres y etiquetas
| Clúster | Contexto kubectl | Estado |
|---|---|---|
| `hub` | `kind-hub` | Fase 2 |
| `spoke-1` | `kind-spoke-1` | Mas adelante |

Toda señal (metricas, logs, trazas) lleva la etiqueta/atributo **`cluster=<nombre>`** (`k8s.cluster.name`
en OTel). Mimir y Loki funcionan en **un solo tenant** (`multitenancy_enabled: false`, `auth_enabled: false`).

## 2. Namespaces
| Namespace | Contenido |
|---|---|
| `argocd` | Argo CD |
| `cert-manager` | cert-manager |
| `openbao` | OpenBao |
| `external-secrets` | External Secrets Operator |
| `storage` | Almacenamiento de objetos S3 (SeaweedFS, a validar) |
| `observability` | Mimir, Loki, Tempo, Grafana, colectores OpenTelemetry, kube-state-metrics, node-exporter |
| `headlamp` | Headlamp |
| `gateway-system` | `Gateway` `eg` (Envoy Gateway ya vive en `envoy-gateway-system`) |

## 3. Servicios (nombre y puerto exactos; usar `fullnameOverride` o un `Service` adicional)
| Servicio | Puertos / rutas |
|---|---|
| `seaweedfs-s3.storage.svc.cluster.local` | `8333` HTTP, path-style, region `us-east-1` |
| `mimir.observability.svc.cluster.local` | `8080`: push `/api/v1/push`, OTLP `/otlp`, consulta `/prometheus` |
| `loki.observability.svc.cluster.local` | `3100`: push `/loki/api/v1/push`, OTLP `/otlp` |
| `tempo.observability.svc.cluster.local` | `3200` consulta HTTP, `4317` OTLP gRPC, `4318` OTLP HTTP |
| `otel-gateway.observability.svc.cluster.local` | `4317` gRPC, `4318` HTTP (punto de entrada OTLP de las apps) |
| `grafana.observability.svc.cluster.local` | `80` |
| `openbao.openbao.svc.cluster.local` | `8200` (HTTP dentro del clúster en esta primera version) |
| `argocd-server.argocd.svc.cluster.local` | `80` (modo `server.insecure`) |
| `headlamp.headlamp.svc.cluster.local` | `80` |

**Buckets S3:** `mimir-blocks`, `mimir-ruler`, `mimir-alertmanager`, `loki-chunks`, `loki-ruler`, `tempo-traces`.

## 4. Secretos
- Backend: OpenBao, motor KV v2 montado en `kv`. Autenticacion de ESO por **Kubernetes auth** (`auth/kubernetes`).
- `ClusterSecretStore` llamado **`openbao`**.
- **Ningun valor secreto en git, jamas.** Los charts consumen `Secret` ya existentes (`existingSecret`) creados por `ExternalSecret`.

| Ruta en OpenBao | Secret de Kubernetes (namespace) | Claves |
|---|---|---|
| `kv/platform/s3` | `s3-credentials` (`storage`, `observability`) | `access-key`, `secret-key` |
| `kv/platform/grafana` | `grafana-admin` (`observability`) | `admin-user`, `admin-password` |

## 5. TLS y entrada HTTP(S)
- `ClusterIssuer` **`local-ca`** (CA propia; mas adelante `letsencrypt-dns` si hay dominio).
- `Gateway` **`eg`** en `gateway-system`: listeners `http` (80) y `https` (443), certificado comodin `*.hub.localtest.me`
  en el Secret `wildcard-hub-tls` (mismo namespace que el Gateway).
- Cada app publica un `HTTPRoute` en su namespace con `parentRefs: [{name: eg, namespace: gateway-system}]`.
  El `Gateway` admite rutas de todos los namespaces.
- Hostnames: `argocd`, `grafana`, `headlamp`, `openbao`, `hubble` + `.hub.localtest.me`.
- **Dentro del clúster se usa siempre el DNS del Service**, nunca `localtest.me` (resuelve a 127.0.0.1).

## 6. Telemetria
- Colectores OpenTelemetry (agente por nodo para logs; gateway para OTLP y metricas), ambos en `observability`.
- Metricas → Mimir (`prometheusremotewrite` a `http://mimir.observability.svc:8080/api/v1/push`, u OTLP).
- Logs → Loki (OTLP o push API). Trazas → Tempo (`tempo:4317`).
- Fuentes minimas: kubelet/cAdvisor, kube-state-metrics, node-exporter, Cilium/Hubble (`:9962`, `:9965`), Envoy Gateway, y los propios componentes.
- Grafana: datasources Mimir, Loki y Tempo aprovisionados, con correlacion traza↔log↔metrica.

## 7. Olas de sincronizacion (`argocd.argoproj.io/sync-wave`)
| Ola | Componentes |
|---|---|
| 0 | cert-manager, CRDs de ESO, Envoy Gateway (ya instalado), `Gateway` |
| 1 | OpenBao (unseal manual), ESO + `ClusterSecretStore`, `ClusterIssuer` |
| 2 | Almacenamiento de objetos S3 |
| 3 | Mimir, Loki, Tempo |
| 4 | Colectores OTel, kube-state-metrics, node-exporter, Grafana |
| 5 | Headlamp, dashboards y alertas |

## 8. Presupuesto de recursos (orientativo, **sin medir**)
Objetivo: suma de `requests` del hub ≤ 8 GiB de RAM. Todo contenedor lleva `requests` y `limits`.
