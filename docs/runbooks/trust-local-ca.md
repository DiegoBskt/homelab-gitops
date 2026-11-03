# Runbook: confiar en la CA local (`local-ca`)

cert-manager emite los certificados del Gateway (`*.hub.localtest.me`) con una CA propia (`ClusterIssuer local-ca`, raiz
`homelab-local-ca`, valida 10 años, ECDSA P-256). Los navegadores avisaran de certificado no confiable hasta que importes **solo el
certificado publico** de esa CA. El Secret `cert-manager/local-ca-root` contiene `tls.crt`, `ca.crt` (publicos) y `tls.key` (**privada: no la exportes**).

## 1. Extraer la CA publica (WSL)
```bash
kubectl --context kind-hub -n cert-manager get secret local-ca-root -o jsonpath='{.data.ca\.crt}' | base64 -d > hub-local-ca.crt
openssl x509 -in hub-local-ca.crt -noout -subject -issuer -dates -fingerprint -sha256   # revisa que sea 'homelab-local-ca'
mkdir -p /mnt/c/Users/$USER/Downloads 2>/dev/null; cp hub-local-ca.crt "/mnt/c/Users/<tu-usuario-windows>/Downloads/hub-local-ca.crt"
```
Comprueba que la huella SHA-256 coincide con la que ves en el Secret desde otro comando antes de importar.

## 2. Windows (almacen del usuario; Chrome, Edge y Brave lo usan)
PowerShell **sin** privilegios de administrador:
```powershell
Import-Certificate -FilePath "$env:USERPROFILE\Downloads\hub-local-ca.crt" -CertStoreLocation Cert:\CurrentUser\Root
# o, con certutil (muestra un dialogo de confirmacion):
certutil -user -addstore Root "$env:USERPROFILE\Downloads\hub-local-ca.crt"
```
Verificar: `certutil -user -store Root homelab-local-ca`. Para todo el equipo (admin): `certutil -addstore -f Root <fichero>`.
Retirar: `certutil -user -delstore Root homelab-local-ca`.

## 3. Firefox
Usa su propio almacen: Ajustes → Privacidad y seguridad → Certificados → *Ver certificados* → *Autoridades* → *Importar…* → marca
"Confiar en esta CA para identificar sitios web". Alternativa: `about:config` → `security.enterprise_roots.enabled = true` para que use el almacen de Windows.

## 4. WSL / Linux (curl, git, etc. dentro de WSL)
```bash
sudo cp hub-local-ca.crt /usr/local/share/ca-certificates/hub-local-ca.crt && sudo update-ca-certificates
curl -sI https://argocd.hub.localtest.me | head -1
```
(Los contenedores/pods **no** heredan esta confianza; dentro del clúster se usa HTTP al Service.)

## 5. Prueba
`https://openbao.hub.localtest.me` debe mostrar candado sin aviso. Si sigue el aviso: comprueba `kubectl -n gateway-system get certificate wildcard-hub`
(`READY=True`) y que reiniciaste el navegador.

## Riesgo de confiar en una CA local
- Quien tenga la **clave privada** de la CA (`tls.key` del Secret `local-ca-root`, accesible a cualquiera con `get secret` en `cert-manager`,
  incluido Argo CD y los admins del clúster, y presente en el etcd del nodo kind) puede emitir certificados validos para **cualquier dominio**
  (banco, correo...) que tu navegador aceptara sin aviso, permitiendo interceptar tu trafico si ademas se situa en la red.
- La CA no esta limitada por *name constraints*: tu equipo la acepta para todo, no solo para `*.hub.localtest.me`.
- Mitigaciones: importa solo en un perfil de navegador de pruebas o en una maquina de laboratorio; no copies `tls.key` ni la subas a git; restringe
  quien puede leer Secrets de `cert-manager`; retira la CA (`-delstore`) al destruir el clúster (recrearlo genera una CA **nueva** y la antigua queda huerfana);
  cuando exista `letsencrypt-dns` para un dominio real, deja de usar la CA local.
