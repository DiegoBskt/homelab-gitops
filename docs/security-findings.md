# Hallazgos de trivy (config) aceptados — hub

`trivy config --severity HIGH,CRITICAL` sobre los manifiestos renderizados de `apps/*/overlays/hub`: **33 hallazgos**, todos
inherentes al tipo de componente. Se revisan al actualizar versiones; no bloquean CI (job informativo).

| ID | Sev. | N | Componentes | Por que se acepta |
|---|---|---|---|---|
| KSV-0041 Manage secrets | CRITICAL | 13 | argocd, cert-manager, envoy-gateway, external-secrets, kube-state-metrics | Controladores que deben leer/escribir Secrets (certificados, sync de secretos, TLS). |
| KSV-0114 Manage webhookconfigurations | CRITICAL | 3 | cert-manager, envoy-gateway, external-secrets | Inyeccion de `caBundle` en sus propios webhooks. |
| KSV-0046 / KSV-0044 Wildcard | CRITICAL | 3 | argocd | Argo CD gestiona cualquier recurso del cluster (rol del controlador). |
| KSV-0056 Manage networking | HIGH | 3 | cert-manager, envoy-gateway | Solver de HTTP-01 / Gateway API. |
| KSV-0118 Default security context | HIGH | 8 | argocd, external-secrets | **Mejorable**: fijar `securityContext` explicito en sus values. Pendiente. |
| KSV-0009 / 0010 / 0121 hostNetwork, hostPID, hostPath | HIGH | 3 | node-exporter | Necesario para metricas del nodo. |
