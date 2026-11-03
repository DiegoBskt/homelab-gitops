# Grafana

Chart `grafana` **14.3.1** (Grafana 13.3.0) del repo **`https://grafana-community.github.io/helm-charts`**.
El repo clasico `https://grafana.github.io/helm-charts` esta marcado `deprecated: true` (ultima version 10.5.15, Grafana 12.3.1);
el chart se mantiene ahora en `grafana-community` (repo activo, Apache-2.0). Se usa el repo http (no hay OCI publicado).

- 1 replica, **sin persistencia** (emptyDir): datasources, dashboards y admin son codigo/Secret. Con un PVC la contraseña
  admin guardada en la BD dejaria de seguir al Secret `grafana-admin`.
- Admin desde el Secret `grafana-admin` (`admin-user`/`admin-password`, lo crea ESO en `apps/platform-secrets`). Ningun valor en git.
- Service `grafana:80` → pod `:3000`; `HTTPRoute` del propio chart: `grafana.hub.localtest.me` → `grafana:80`
  (`parentRefs: eg/gateway-system`, sin `sectionName`). `root_url=https://grafana.hub.localtest.me`.
- Pod anotado `prometheus.io/scrape|port=3000|path=/metrics`. Requests de memoria: **256 MiB** (limite 512 MiB).
- Verificacion offline: se arranco `grafana/grafana:13.3.0-distroless` en Docker con los ficheros renderizados
  (`grafana.ini`, datasources, providers y dashboards): los 3 datasources y los 13 dashboards se provisionan sin errores.

## Datasources (UIDs fijos: `mimir`, `loki`, `tempo`)
| Nombre | Tipo | URL | Correlaciones |
|---|---|---|---|
| Mimir (por defecto) | `prometheus` (`prometheusType: Mimir`) | `http://mimir.observability.svc.cluster.local:8080/prometheus` | `exemplarTraceIdDestinations` → Tempo (`trace_id`) |
| Loki | `loki` | `http://loki.observability.svc.cluster.local:3100` | `derivedFields` (`matcherType: label`, `trace_?id`) → Tempo |
| Tempo | `tempo` | `http://tempo.observability.svc.cluster.local:3200` | `tracesToLogsV2` → Loki (`k8s.pod.name`→`k8s_pod_name`, `k8s.namespace.name`→`k8s_namespace_name`), `tracesToMetrics` y `serviceMap` → Mimir, `nodeGraph` |

Claves comprobadas contra la documentacion de Grafana v13.3 (`docs/sources/datasources/{tempo,loki,prometheus}`); en el
provisioning `$` se escapa como `$$`. Notas:
- Los tags de `tracesToLogsV2` no se remapean solos (solo los por defecto): se da `key` (atributo del span) y `value` (label de Loki).
- `filterByTraceID: false`: los logs de contenedor (`filelog`) no llevan `trace_id`; activarlo si las apps lo emiten.
- `tracesToMetrics`/`serviceMap` esperan las metricas del metrics-generator de Tempo (`traces_spanmetrics_*`, `traces_service_graph_*`);
  si C no activa el generator, esos enlaces quedaran vacios (no rompen nada).
- `matcherType: label` (derived field sobre structured metadata) esta documentado en la UI ("Type: Label") y se acepta en el
  provisioning de Grafana 13.3 (comprobado al arrancar y leer la API); el ejemplo de la doc de provisioning solo muestra la variante regex.

## Dashboards como codigo
Tres `ConfigMap` generados por Kustomize (`configMapGenerator`, **sin sufijo hash**, JSON minificado, < 300 KiB cada uno) y montados
como ficheros con providers `file` (sin sidecar: ahorra un contenedor y RBAC; Grafana relee cada 30 s). Carpetas: *Kubernetes*, *Plataforma*, *Explorar*.
Todos usan una variable `datasource` (tipo prometheus) cuyo valor por defecto es `mimir`.

| Fichero | Carpeta | Origen (version fijada) | Licencia |
|---|---|---|---|
| `kubernetes/k8s-views-{global,namespaces,nodes,pods}.json` | Kubernetes | https://github.com/dotdc/grafana-dashboards-kubernetes `dashboards/` @ `v3.0.8` (commit `e4faf59e`) | Apache-2.0 |
| `platform/cilium-agent.json` (Cilium Metrics), `cilium-operator.json`, `hubble.json` | Plataforma | https://github.com/cilium/cilium `install/kubernetes/cilium/files/{cilium-agent,cilium-operator,hubble}/dashboards/` @ `v1.20.4` (commit `beb276d2`) | Apache-2.0 |
| `platform/envoy-gateway-global.json`, `envoy-proxy-global.json`, `envoy-clusters.json` | Plataforma | https://github.com/envoyproxy/gateway `charts/gateway-addons-helm/dashboards/` @ `v1.9.3` (commit `ec0171b2`) | Apache-2.0 |
| `platform/argocd.json` | Plataforma | https://github.com/argoproj/argo-cd `examples/dashboard.json` @ `v3.5.7` (commit `6d732962`) | Apache-2.0 |
| `explore/logs-explorer.json`, `traces-explorer.json` | Explorar | Propios de este repositorio (Loki: volumen + logs con filtros cluster/namespace/pod/regex/nivel; Tempo: busqueda TraceQL + traza por ID) | licencia del repositorio |

"Nodes (node-exporter)" lo cubre `k8s-views-nodes` (usa `node_*` de node-exporter); no se incluye *Node Exporter Full* (id 1860)
para no añadir otra fuente con licencia distinta.

### Adaptaciones respecto al original (todas mecanicas)
- JSON minificado; se eliminan `__inputs`, `__requires`, `__elements`; `id: null`; etiqueta `homelab`.
- Variables de tipo `datasource` (prometheus): `current` = Mimir (`uid: mimir`).
- Envoy: el uid fijo `PBFA97CFB590B2093` se sustituye por `${datasource}`.
- Argo CD: los matchers `job="argocd-*-metrics"` se cambian por `job=~"argocd-.*"` (el job real depende del scrape de D; contrato: `argocd-*`).
- Variable **`cluster`**: la traen y la filtran los 4 dashboards de Kubernetes (`label_values(kube_node_info,cluster)` → `hub`).
  Cilium, Hubble, Envoy y Argo CD **no** filtran por `cluster` (no la tienen): mostraran todas las series de todos los clusters cuando exista `spoke-1`.
- Para actualizar: descargar de la misma ruta con la nueva etiqueta/commit, repetir las adaptaciones, actualizar esta tabla.

## Cache del chart
`kustomize build --enable-helm` descarga el chart en `base/charts/` (mismo patron que `apps/envoy-gateway`). Del chart de Headlamp se ha
borrado `tests/` porque sus fixtures (`kind: Secret` de ejemplo) disparan `gitleaks`. Argo CD descarga el chart por su cuenta; el directorio
`charts/` no es necesario en git (se puede añadir `apps/*/base/charts/` a `.gitignore`).
