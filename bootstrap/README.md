# bootstrap/

Lo minimo que hace falta para arrancar un clúster. Todo lo demas lo gestiona Argo CD desde `clusters/<cluster>/`.

```bash
bootstrap/scripts/create-hub.sh          # RECREATE=1 para recrearlo
```

El script hace, en orden: kind (`bootstrap/kind/hub.yaml`) → registry local → Cilium (Helm, `bootstrap/cilium/values.yaml`)
→ Argo CD (`kustomize build bootstrap/argocd | kubectl apply --server-side`) → app raiz (`bootstrap/root-hub.yaml`) → espera a
que todas las apps queden `Synced/Healthy`.

- El repositorio es **publico**: Argo CD lo lee sin credenciales.
- La app raiz usa el proyecto `default`; el `AppProject` `platform` lo crea ella misma y lo usan las demas apps.
- Cilium se instala aqui (es el CNI: sin el no hay nodos Ready) y **no** lo gestiona Argo CD todavia. Adoptarlo exigiria
  resolver antes los certificados de Hubble (`hubble.tls.auto.method`), que con `helm template` se regeneran en cada render.
- Contraseña inicial de Argo CD (no se guarda en git):
  `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`
