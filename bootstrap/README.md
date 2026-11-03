# bootstrap/

Lo minimo que se aplica a mano, una sola vez, sobre un clúster nuevo. Todo lo demas lo gestiona Argo CD.

```bash
# 1. Argo CD (Server-Side Apply: los CRDs superan el limite de anotaciones)
kustomize build bootstrap/argocd | kubectl apply --server-side --force-conflicts -f -
# 2. Aplicacion raiz: a partir de aqui Argo CD lee clusters/hub de este repo
kubectl apply -f bootstrap/root-hub.yaml
```

El repositorio es privado: Argo CD necesita credenciales de solo lectura (deploy key), que se crean
en el bootstrap y **nunca** se guardan en git.
