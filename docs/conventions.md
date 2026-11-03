# Convenciones

1. **Kustomize es la interfaz.** Cada componente es `apps/<nombre>/{base,overlays/<cluster>}`. Helm solo entra como
   fuente de charts mediante `helmCharts:` (Argo CD corre con `--enable-helm`).
2. **Versiones fijadas**, nunca `latest` ni rangos: chart, imagen y manifiestos remotos.
3. **Verificar antes de adoptar:** repo, version actual y estado de mantenimiento (archivado, retirado, movido).
   Ejemplos reales de este proyecto: ingress-nginx esta retirado; MinIO esta archivado; los charts de Loki se movieron a
   `grafana-community`. Cada componente anota su verificacion en `docs/versions.md`.
4. **Sin secretos en git.** `gitleaks` corre como hook de pre-commit y en CI. Secretos → OpenBao + ExternalSecret.
5. **Recursos y seguridad:** `requests`/`limits` en todos los contenedores, `securityContext` restrictivo cuando el chart lo permita.
6. **Etiquetas:** `app.kubernetes.io/part-of: homelab` en los recursos propios.
7. **Validar antes de abrir PR:** `scripts/validate.sh` (`STRICT=1` para hacer bloqueantes kube-linter y trivy).
8. **Flujo:** rama → PR → CI verde → merge a `main`. Argo CD solo sincroniza `main`.
9. **Comentarios y docs en español; identificadores y claves YAML en ingles.**

## Estado de los controles
- Bloqueantes en CI: `kustomize build`, `kubeconform`, `gitleaks` (arbol e historial).
- Informativos por ahora: `kube-linter` y `trivy` (los manifiestos upstream de Argo CD producen muchos hallazgos). Se pasan a
  bloqueantes (`STRICT=1`) cuando exista una linea base de excepciones por componente.
