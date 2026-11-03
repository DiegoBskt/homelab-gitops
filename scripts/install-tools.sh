#!/usr/bin/env bash
# Instala en ~/.local/bin las herramientas de validacion con la version fijada en tools/versions.env.
# FORCE=1 reinstala aunque ya existan (lo usa CI).
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source "$ROOT/tools/versions.env"
BIN="${HOME}/.local/bin"; mkdir -p "$BIN"; export PATH="$BIN:$PATH"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
need() { [ "${FORCE:-0}" = 1 ] || ! command -v "$1" >/dev/null; }
gh_dl() { curl -fsSL "$1" | tar xz -C "$T"; }

need kustomize   && { gh_dl "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"; install "$T/kustomize" "$BIN/"; }
need kubeconform && { gh_dl "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz"; install "$T/kubeconform" "$BIN/"; }
need kube-linter && { gh_dl "https://github.com/stackrox/kube-linter/releases/download/${KUBE_LINTER_VERSION}/kube-linter-linux.tar.gz"; install "$T/kube-linter" "$BIN/"; }
need trivy       && { gh_dl "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/trivy_${TRIVY_VERSION#v}_Linux-64bit.tar.gz"; install "$T/trivy" "$BIN/"; }
need gitleaks    && { gh_dl "https://github.com/gitleaks/gitleaks/releases/download/${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION#v}_linux_x64.tar.gz"; install "$T/gitleaks" "$BIN/"; }
need helm        && { gh_dl "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"; install "$T/linux-amd64/helm" "$BIN/"; }

[ -n "${GITHUB_PATH:-}" ] && echo "$BIN" >> "$GITHUB_PATH"
for t in kustomize kubeconform kube-linter trivy gitleaks helm; do printf '%-12s %s\n' "$t" "$(command -v "$t")"; done
