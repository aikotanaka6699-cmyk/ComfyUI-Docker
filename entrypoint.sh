#!/bin/bash
set -euo pipefail

APP_USER=${APP_USER:-appuser}
APP_GROUP=${APP_GROUP:-appuser}
PUID=${PUID:-1000}
PGID=${PGID:-1000}

BASE_DIR=/app/ComfyUI
CUSTOM_NODES_DIR="$BASE_DIR/custom_nodes"

# If running as root, map to requested UID/GID and re-exec as the app user
if [ "$(id -u)" = "0" ]; then
  if getent group "${PGID}" >/dev/null; then
    EXISTING_GRP="$(getent group "${PGID}" | cut -d: -f1)"
    usermod -g "${EXISTING_GRP}" "${APP_USER}" || true
    APP_GROUP="${EXISTING_GRP}"
  else
    groupmod -o -g "${PGID}" "${APP_GROUP}" || true
  fi
  usermod -o -u "${PUID}" "${APP_USER}" || true
  mkdir -p "/home/${APP_USER}"
  for d in "$BASE_DIR" "/home/$APP_USER"; do
    [ -e "$d" ] && chown -R "${APP_USER}:${APP_GROUP}" "$d" || true
  done
  exec runuser -u "${APP_USER}" -- "$0" "$@"
fi

# Ensure ComfyUI-Manager (bind mounts can hide baked content)
if [ ! -d "$CUSTOM_NODES_DIR/ComfyUI-Manager" ]; then
  echo "[bootstrap] Installing ComfyUI-Manager into $CUSTOM_NODES_DIR/ComfyUI-Manager"
  git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git "$CUSTOM_NODES_DIR/ComfyUI-Manager" || true
fi

# User-site PATHs for --user installs (custom nodes)
export PATH="$HOME/.local/bin:$PATH"
pyver="$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
export PYTHONPATH="$HOME/.local/lib/python${pyver}/site-packages:${PYTHONPATH:-}"

# Auto-install custom node deps
if [ "${COMFY_AUTO_INSTALL:-1}" = "1" ]; then
  echo "[deps] Scanning custom nodes for requirements..."
  while IFS= read -r -d '' req; do
    echo "[deps] pip install --user -r $req"
    pip install --no-cache-dir --user -r "$req" || true
  done < <(find "$CUSTOM_NODES_DIR" -maxdepth 3 -type f \( -iname 'requirements.txt' -o -iname 'requirements-*.txt' -o -path '*/requirements/*.txt' \) -print0)

  while IFS= read -r -d '' pjt; do
    d="$(dirname "$pjt")"
    echo "[deps] pip install --user . in $d"
    (cd "$d" && pip install --no-cache-dir --user .) || true
  done < <(find "$CUSTOM_NODES_DIR" -maxdepth 2 -type f -iname 'pyproject.toml' -print0)

  pip check || true
fi

cd "$BASE_DIR"
exec "$@"
