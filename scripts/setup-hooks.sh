#!/usr/bin/env bash
# Activa los hooks de git del repo (pre-commit con gitleaks). Ejecutar una vez por clon.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
echo "core.hooksPath = $(git config core.hooksPath)"
