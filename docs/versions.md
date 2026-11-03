# Versiones y verificacion de componentes

Fecha de verificacion: 2026-11-03. **Verificado por:** `orq` = el orquestador contra un despliegue o la API de GitHub; `agente` = el subagente que escribio el
componente (busqueda web, `helm show`, notas de version y, cuando se indica, ejecucion del binario en Docker). Nada de esto se ha desplegado aun en el clúster.

| Componente | Fuente (chart / manifiesto) | Version | Verificado por | Estado de mantenimiento |
|---|---|---|---|---|
| Argo CD | `argoproj/argo-cd` install.yaml | v3.5.7 | orq | activo |
| Cilium | chart `cilium/cilium` (helm.cilium.io) | 1.20.4 | orq | activo |
| Envoy Gateway | chart OCI `oci://registry-1.docker.io/envoyproxy/gateway-helm` | v1.9.3 | orq | activo |
| cert-manager | `https://charts.jetstack.io` chart `cert-manager` | v1.21.3 | agente | activo, CNCF graduado, Apache-2.0 |
| External Secrets Operator | `https://charts.external-secrets.io` chart `external-secrets` | 2.14.0 | agente | activo, CNCF, Apache-2.0 (API `external-secrets.io/v1` servida) |
| OpenBao | `https://openbao.github.io/openbao-helm` chart `openbao` (imagen `quay.io/openbao/openbao`) | chart 0.30.6 / app 2.7.2 | agente | activo, fork de Vault en la Linux Foundation, MPL-2.0 (repo de GitHub sin consultar) |
| SeaweedFS | `https://seaweedfs.github.io/seaweedfs/helm` chart `seaweedfs` | 4.52.0 | orq + agente | activo (push 2026-11-03), Apache-2.0; spike S3 real (ver contrato, seccion 6) |
| Mimir | `https://grafana.github.io/helm-charts` chart `mimir-distributed` | 6.2.2 / Mimir 3.2.3 | agente | activo; sigue en el repo `grafana` (no en `grafana-community`); subchart MinIO desactivado |
| Loki | `oci://ghcr.io/grafana-community/helm-charts/loki` | 20.3.0 / Loki 3.7.9 | agente | activo; chart movido a grafana-community; `-verify-config` OK en Docker |
| Tempo | `oci://ghcr.io/grafana-community/helm-charts/tempo` | 3.2.1 / Tempo 3.1.1 | agente | activo; el chart `tempo` antiguo de `grafana/helm-charts` esta marcado deprecated; `-config.verify` OK en Docker |
| OpenTelemetry Collector | `https://open-telemetry.github.io/opentelemetry-helm-charts` chart `opentelemetry-collector` | 0.178.2 / contrib 0.163.2 | agente | activo; hay contrib v0.164.1 mas nueva (no adoptada); `validate` OK en Docker |
| kube-state-metrics | `https://prometheus-community.github.io/helm-charts` | chart 8.8.0 / v2.20.0 | agente | activo |
| node-exporter | `https://prometheus-community.github.io/helm-charts` chart `prometheus-node-exporter` | 4.60.1 / v1.12.1 | agente | activo |
| Grafana | `https://grafana-community.github.io/helm-charts` chart `grafana` | 14.3.1 / Grafana 13.3.0 | agente | activo; el repo `grafana.github.io/helm-charts` esta deprecated; arranque en Docker con la provision renderizada OK |
| Headlamp | `https://kubernetes-sigs.github.io/headlamp/` chart `headlamp` | 0.46.0 | agente | activo (kubernetes-sigs, no archivado) |
| Dashboards (dotdc/Cilium/Envoy/Argo CD) | ver `apps/grafana/README.md` | v3.0.8 / 1.20.4 / 1.9.3 / 3.5.7 | agente | Apache-2.0 segun la API de GitHub |

## Decisiones tomadas por los autores
- **Mimir** usa arquitectura clasica (ingest storage y Kafka desactivados por consumo de RAM) con 1 replica y `replication_factor=1`.
- **Loki**: el modo del chart se llama ahora `Monolithic` (antes `SingleBinary`).
- **Colectores**: dos releases del chart simple (gateway + agente) en vez de `opentelemetry-kube-stack`: sin Operator, sin CRDs ni webhooks propios. Estimacion sin medir.
- **Grafana** sin persistencia (la contraseña de admin sigue al Secret `grafana-admin`).
- **Headlamp**: el Pod no tiene permisos propios; el acceso es con tokens de corta duracion de `headlamp-viewer` o `headlamp-admin` (ver runbook).
