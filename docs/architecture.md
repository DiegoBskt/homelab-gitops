# Arquitectura

- **hub** (kind: 1 control-plane + 2 workers, CNI Cilium): Argo CD, cert-manager, OpenBao, External Secrets,
  almacenamiento de objetos, Mimir, Loki, Tempo, Grafana, colectores OpenTelemetry y Headlamp.
- **spoke-1** (mas adelante): kind pequeño registrado en Argo CD; su colector envia metricas/logs/trazas al hub.
- **GitOps:** `bootstrap/` instala Argo CD una vez; la app `root` lee `clusters/hub`, que declara una `Application`
  por componente apuntando a `apps/<componente>/overlays/hub` (Kustomize).
- **Entrada:** Envoy Gateway (Gateway API) publicado en el 80/443 del host; TLS con cert-manager (CA local).
- **Secretos:** OpenBao → External Secrets (provider `vault`) → `Secret` de Kubernetes.

Detalle de interfaces en [contract.md](contract.md) y reglas de trabajo en [conventions.md](conventions.md).
