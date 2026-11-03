# Acceso a Headlamp

URL: `https://headlamp.hub.localtest.me` (o `http://` si aun no existe el listener 443). **Sin OIDC**: la pantalla de login pide un
**token de ServiceAccount**. Headlamp no usa su propia identidad para atender a los usuarios; los permisos son los del token pegado.
El Pod de Headlamp corre con un ServiceAccount (`headlamp`) **sin ningun binding RBAC** (solo lo usa para descubrir el API server).

## Cuentas disponibles (namespace `headlamp`)
| ServiceAccount | Permisos | Uso |
|---|---|---|
| `headlamp-viewer` | ClusterRole `view` (lectura; sin Secrets ni RBAC) | uso diario |
| `headlamp-admin` | ClusterRole `cluster-admin` | solo para cambios puntuales |

Ninguna tiene Secret de token autogenerado (`automountServiceAccountToken: false`): los tokens se piden bajo demanda y caducan.

## Crear un token de corta duracion
```bash
# Solo lectura (1 hora)
kubectl --context kind-hub -n headlamp create token headlamp-viewer --duration=1h

# Administrador (15 min; el minimo admitido es 10 min)
kubectl --context kind-hub -n headlamp create token headlamp-admin --duration=15m
```
Pegar el token en la pantalla "Authentication" de Headlamp. Al caducar hay que pedir otro (no hay renovacion). Para invalidar antes
de tiempo hay que borrar y recrear el ServiceAccount (los tokens de `create token` van ligados al UID del SA).
Requiere permisos para `create` sobre `serviceaccounts/token` (con tu usuario admin de kind los tienes).

## Riesgo del token de `headlamp-admin`
- Es **cluster-admin**: quien lo posea puede leer todos los Secrets (incluidos los de OpenBao/ESO y credenciales S3), ejecutar comandos en
  pods desde la terminal de Headlamp, modificar RBAC y borrar cualquier recurso. Argo CD revertira cambios en recursos que gestiona
  (`selfHeal`), pero no los de recursos fuera de GitOps.
- El token queda en el `localStorage`/memoria del navegador y viaja al backend de Headlamp; si el sitio se sirve por HTTP, viaja sin cifrar
  (usar HTTPS cuando el listener 443 exista; `localtest.me` solo resuelve a 127.0.0.1).
- Mitigaciones: TTL minimo, no guardarlo en ficheros ni pegarlo en chats, usar `headlamp-viewer` por defecto, cerrar sesion al terminar.
- No exponer Headlamp fuera del host sin autenticacion delante (OIDC o proxy): cualquier persona con un token valido tiene sus permisos.
