# apps/

Un directorio por componente, con la estructura Kustomize estandar:

```
apps/<componente>/
  base/kustomization.yaml        # recursos remotos con version fijada y/o helmCharts
  base/values.yaml               # values del chart (si aplica)
  overlays/<cluster>/            # ajustes por clúster (hub, spoke-1...)
```

Para que Argo CD lo despliegue, se anade una `Application` en `clusters/<cluster>/applications/`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <componente>
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3"      # ver docs/contract.md
spec:
  project: platform
  source:
    repoURL: https://github.com/DiegoBskt/homelab-gitops.git
    targetRevision: main
    path: apps/<componente>/overlays/hub
  destination: {server: https://kubernetes.default.svc, namespace: <ns>}
  syncPolicy:
    automated: {prune: true, selfHeal: true}
    syncOptions: [CreateNamespace=true, ServerSideApply=true]
```

`apps/_template` es un ejemplo copiable y no se valida en CI.
