#!/usr/bin/env bash
# Valida el repositorio: build de cada punto de entrada Kustomize, esquemas, lint, seguridad y secretos.
#   STRICT=1  hace bloqueantes kube-linter y trivy (por defecto solo informan).
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT"
# shellcheck disable=SC1091
source tools/versions.env
export PATH="$HOME/.local/bin:$PATH"
STRICT="${STRICT:-0}"
OUT="$(mktemp -d)"; KL="$(mktemp)"; trap 'rm -rf "$OUT" "$KL"' EXIT
CRD_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
MODE=$([ "$STRICT" = 1 ] && echo bloqueante || echo informativo)
rc=0
step() { printf '\n== %s ==\n' "$1"; }

# Puntos de entrada: bootstrap/<x>, apps/<app>/overlays/<cluster>, clusters/<cluster>
mapfile -t TARGETS < <(
  { find bootstrap -mindepth 2 -maxdepth 2 -name kustomization.yaml
    find apps -path '*/overlays/*' -name kustomization.yaml -not -path 'apps/_template/*'
    find clusters -mindepth 2 -maxdepth 2 -name kustomization.yaml
  } 2>/dev/null | xargs -r -n1 dirname | sort -u)

step "1/5 kustomize build (--enable-helm): ${#TARGETS[@]} destinos"
for d in "${TARGETS[@]}"; do
  slug="${d//\//__}"
  if kustomize build --enable-helm "$d" > "$OUT/$slug.yaml" 2> "$OUT/$slug.err"; then
    printf 'OK    %-45s %s objetos\n' "$d" "$(grep -c '^kind:' "$OUT/$slug.yaml" || true)"
  else
    printf 'FALLO %s\n' "$d"; sed 's/^/      /' "$OUT/$slug.err"; rc=1; rm -f "$OUT/$slug.yaml"
  fi
done

if ls "$OUT"/*.yaml >/dev/null 2>&1; then
  step "2/5 kubeconform (K8s $K8S_VERSION + catalogo de CRDs; los CRD vendor se omiten)"
  kubeconform -strict -summary -kubernetes-version "$K8S_VERSION" -skip CustomResourceDefinition \
    -schema-location default -schema-location "$CRD_CATALOG" "$OUT"/*.yaml || rc=1

  step "3/5 kube-linter ($MODE)"
  kube-linter lint --config .kube-linter.yaml --format json "$OUT" > "$KL" 2>/dev/null || true
  n=$(jq '(.Reports // []) | length' "$KL")
  echo "$n hallazgos; top por tipo:"
  jq -r '(.Reports // []) | group_by(.Check) | map({c: .[0].Check, n: length}) | sort_by(-.n) | .[:6][] | "  \(.n)\t\(.c)"' "$KL"
  if [ "$STRICT" = 1 ] && [ "$n" -gt 0 ]; then rc=1; fi

  step "4/5 trivy config HIGH/CRITICAL ($MODE)"
  tn=$(trivy config --quiet --severity HIGH,CRITICAL --format json "$OUT" 2>/dev/null | jq '[.Results[]? | .Misconfigurations[]?] | length')
  echo "$tn hallazgos HIGH/CRITICAL"
  if [ "$STRICT" = 1 ] && [ "$tn" -gt 0 ]; then rc=1; fi
else
  echo "(sin manifiestos que validar todavia)"
fi

step "5/5 gitleaks"
gitleaks dir . --redact --no-banner || rc=1
if [ "${CI:-}" = "true" ]; then gitleaks git . --redact --no-banner || rc=1; fi

echo; [ "$rc" = 0 ] && echo "VALIDACION OK" || echo "VALIDACION CON ERRORES"
exit "$rc"
