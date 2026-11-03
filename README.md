# homelab-gitops

GitOps de un laboratorio local de Kubernetes: **kind + Cilium + Envoy Gateway + Argo CD**, con observabilidad
(**Mimir, Loki, Tempo, Grafana, OpenTelemetry**), **cert-manager**, **OpenBao + External Secrets** y **Headlamp**.
Todo en **Kustomize** (Helm solo como fuente de charts).

> Estado: fase 1 (esqueleto, CI y contrato). Los secretos nunca se guardan en este repositorio.

```
bootstrap/   lo minimo que se aplica a mano (Argo CD + app raiz)
clusters/    que despliega Argo CD en cada clúster (hub, spoke-1...)
apps/        un directorio por componente (base + overlays)
appsets/     ApplicationSets multi-clúster
docs/        arquitectura, contrato de interfaces, convenciones, versiones
scripts/     install-tools, validate, setup-hooks
tools/       versiones fijadas de las herramientas
```

## Empezar
```bash
scripts/install-tools.sh   # kustomize, kubeconform, kube-linter, trivy, gitleaks, helm (versiones fijadas)
scripts/setup-hooks.sh     # pre-commit con gitleaks
scripts/validate.sh        # lo mismo que ejecuta CI
```
