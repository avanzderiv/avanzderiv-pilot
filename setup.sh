#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# Avanzderiv Pilot Edition Installer
#
# Modes:
#   ./setup.sh              native Linux install
#   ./setup.sh native       native Linux install
#   ./setup.sh docker       Docker install from bundled image archive in dist/
#   ./setup.sh docker-pull  Docker install from public OCI image
#   ./setup.sh podman-pull  Podman install from public OCI image
#   ./setup.sh demo         provision the bundled demo
#
# ROOT  = runtime root inside engine/container
# BASE  = host-side working directory
# ─────────────────────────────────────────────

EDITION="2.0_PE"
ROOT="/opt/avanzderiv"
PUBLIC_IMAGE="${AVANZDERIV_IMAGE:-ghcr.io/avanzderiv/avanzderiv-pilot:2.0}"

OS=""
ARCH=""
PLATFORM=""

log() {
  printf '%s\n' "$*"
}

detect_os_arch() {
  OS_RAW="$(uname -s)"
  ARCH_RAW="$(uname -m)"

  case "$OS_RAW" in
    Linux*)  OS="linux" ;;
    Darwin*) OS="mac" ;;
    CYGWIN*|MINGW*|MSYS*) OS="windows" ;;
    *) OS="unknown" ;;
  esac

  case "$ARCH_RAW" in
    x86_64|amd64)
      ARCH="x86_64"
      OCI_ARCH="amd64"
      ;;
    aarch64|arm64)
      ARCH="arm64"
      OCI_ARCH="arm64"
      ;;
    *)
      ARCH="unknown"
      OCI_ARCH="unknown"
      ;;
  esac

  PLATFORM="${OS}-${ARCH}"
}

detect_os_arch

BIN="dist/avanzderiv-${EDITION}_${ARCH}"
IMAGE_ARCHIVE="dist/avanzderiv-${EDITION}_${ARCH}.tgz"
LOCAL_IMAGE="avanzderiv:pilot2.0-${ARCH}"

# Host working directory
if [ -n "${AVANZDERIV_BASE:-}" ]; then
  BASE="$AVANZDERIV_BASE"
elif [ "$OS" = "linux" ]; then
  BASE="$ROOT"
else
  BASE="$HOME/avanzderiv"
fi

LOCAL_BIN="$HOME/.local/bin"
TEMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TEMP_DIR"' EXIT

ensure_local_bin() {
  mkdir -p "$LOCAL_BIN"

  if ! echo "$PATH" | tr ':' '\n' | grep -qx "$LOCAL_BIN"; then
    log ""
    log "Add to shell profile:"
    log "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    log ""
  fi
}

ensure_runtime_dirs() {
  mkdir -p \
    "$BASE/data" \
    "$BASE/metadata/contracts" \
    "$BASE/state" \
    "$BASE/warehouse"
}

copy_template() {
  # Supports both the original bundled .template.tar and a public Git repo template/ directory.
  if [ -f ".template.tar" ]; then
    tar -xf .template.tar -C "$TEMP_DIR"
    TEMPLATE_ROOT="$TEMP_DIR/template"
  elif [ -d "template" ]; then
    TEMPLATE_ROOT="template"
  else
    log "ERROR: no template found. Expected .template.tar or template/ directory."
    exit 1
  fi

  if [ ! -f "$BASE/.env" ] && [ -f "$TEMPLATE_ROOT/.env.template" ]; then
    cp "$TEMPLATE_ROOT/.env.template" "$BASE/.env"
  fi

  if [ -d "$TEMPLATE_ROOT/metadata/contracts" ]; then
    cp -n "$TEMPLATE_ROOT/metadata/contracts/"* \
      "$BASE/metadata/contracts/" 2>/dev/null || true
  fi

  if [ -d "$TEMPLATE_ROOT/data" ]; then
    cp -n "$TEMPLATE_ROOT/data/"* \
      "$BASE/data/" 2>/dev/null || true
  fi
}

generate_secret() {
  if [ ! -f "$BASE/.env" ]; then
    touch "$BASE/.env"
  fi

  if ! grep -q "^AVANZDERIV_SECRET_HEX=" "$BASE/.env" \
    || grep -q "^AVANZDERIV_SECRET_HEX=$" "$BASE/.env"; then

    SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"

    if grep -q "^AVANZDERIV_SECRET_HEX=" "$BASE/.env"; then
      sed -i \
        "s/^AVANZDERIV_SECRET_HEX=.*/AVANZDERIV_SECRET_HEX=$SECRET/" \
        "$BASE/.env"
    else
      echo "AVANZDERIV_SECRET_HEX=$SECRET" >> "$BASE/.env"
    fi
  fi
}

write_container_wrapper() {
  RUNTIME="$1"
  IMAGE_REF="$2"

  cat > "$LOCAL_BIN/avanzderiv" <<EOF_WRAPPER
#!/bin/bash

$RUNTIME run --rm \\
  --env-file "$BASE/.env" \\
  -v "$BASE:$ROOT" \\
  "$IMAGE_REF" "\$@"
EOF_WRAPPER

  chmod +x "$LOCAL_BIN/avanzderiv"
}

check_container_runtime() {
  RUNTIME="$1"

  if ! command -v "$RUNTIME" >/dev/null 2>&1; then
    log "ERROR: $RUNTIME is not installed or not in PATH."
    exit 1
  fi

  if [ "$RUNTIME" = "docker" ]; then
    if ! docker info >/dev/null 2>&1; then
      log "ERROR: Docker daemon is not running."
      exit 1
    fi
  fi
}

install_container_from_archive() {
  RUNTIME="docker"

  log "Installing Avanzderiv ${EDITION} (Docker bundled image)..."
  log "  PLATFORM : $PLATFORM"
  log "  BASE     : $BASE"
  log "  ROOT     : $ROOT"
  log "  IMAGE    : $LOCAL_IMAGE"

  check_container_runtime "$RUNTIME"

  if [ ! -f "$IMAGE_ARCHIVE" ]; then
    log "ERROR: Docker image archive not found:"
    log "  $IMAGE_ARCHIVE"
    exit 1
  fi

  docker load < "$IMAGE_ARCHIVE"

  ensure_local_bin
  ensure_runtime_dirs
  copy_template
  generate_secret
  write_container_wrapper "$RUNTIME" "$LOCAL_IMAGE"

  log "Initialising engine..."
  "$LOCAL_BIN/avanzderiv" init

  log "Checking status..."
  "$LOCAL_BIN/avanzderiv" status

  log ""
  log "Docker installation complete."
  log "Run:"
  log "  avanzderiv --help"
}

install_container_from_registry() {
  RUNTIME="$1"

  log "Installing Avanzderiv ${EDITION} (${RUNTIME} public image)..."
  log "  PLATFORM : $PLATFORM"
  log "  BASE     : $BASE"
  log "  ROOT     : $ROOT"
  log "  IMAGE    : $PUBLIC_IMAGE"

  check_container_runtime "$RUNTIME"

  "$RUNTIME" pull "$PUBLIC_IMAGE"

  ensure_local_bin
  ensure_runtime_dirs
  copy_template
  generate_secret
  write_container_wrapper "$RUNTIME" "$PUBLIC_IMAGE"

  log "Initialising engine..."
  "$LOCAL_BIN/avanzderiv" init

  log "Checking status..."
  "$LOCAL_BIN/avanzderiv" status

  log ""
  log "${RUNTIME} installation complete."
  log "Run:"
  log "  avanzderiv --help"
}

install_native() {
  log "Installing Avanzderiv ${EDITION} (native Linux)..."
  log "  ROOT : $ROOT"

  if [ "$OS" != "linux" ]; then
    log "ERROR: Native install supported only on Linux."
    log "Run:"
    log "  ./setup.sh docker-pull"
    exit 1
  fi

  if [ ! -f "$BIN" ]; then
    log "ERROR: Native binary not found:"
    log "  $BIN"
    exit 1
  fi

  python3 -m venv "$ROOT/venv"

  "$ROOT/venv/bin/python" -m pip install --upgrade pip

  "$ROOT/venv/bin/python" -m pip install \
    pandas \
    duckdb \
    pyarrow

  cp "$BIN" "$ROOT/venv/bin/avanzderiv"
  chmod +x "$ROOT/venv/bin/avanzderiv"

  ensure_local_bin
  ln -sf "$ROOT/venv/bin/avanzderiv" "$LOCAL_BIN/avanzderiv"

  # In native mode BASE is the runtime root.
  BASE="$ROOT"

  ensure_runtime_dirs
  copy_template
  generate_secret

  "$ROOT/venv/bin/avanzderiv" init
  "$ROOT/venv/bin/avanzderiv" status

  log ""
  log "Native installation complete."
  log "Run:"
  log "  avanzderiv --help"
}

provision_demo() {
  log "Provisioning demo..."

  DATA_REF="$ROOT/data/sample_data.csv"

  if ! avanzderiv status >/dev/null 2>&1; then
    log "ERROR: Avanzderiv not initialised."
    exit 1
  fi

  PO_ID=$(avanzderiv register \
    --source-type csv \
    --source-ref "$DATA_REF" \
    --schema-from file \
    --print-id)

  avanzderiv classify \
    --asset_id "$PO_ID" \
    --set "rcu_id=SUBJECT.PERSON.PRIMARY"

  avanzderiv classify \
    --asset_id "$PO_ID" \
    --set "birth_year=ID.INDIRECT"

  VO_ID=$(avanzderiv derive \
    --function identity \
    --version v1 \
    --inputs "$PO_ID" \
    --desc "sample_customer" \
    --print-id)

  avanzderiv expose \
    --context public \
    --table sample_surface_v1 \
    --object_id "$VO_ID" \
    --contract public_policy_v1

  log ""
  log "Demo provisioned."
  log "Run:"
  log "  avanzderiv query --context public --table sample_surface_v1"
}

usage() {
  cat <<EOF_USAGE
Usage:
  ./setup.sh                 native Linux install
  ./setup.sh native          native Linux install
  ./setup.sh docker          Docker install from bundled image archive
  ./setup.sh docker-pull     Docker install from public OCI image
  ./setup.sh podman-pull     Podman install from public OCI image
  ./setup.sh demo            provision demo surface

Environment variables:
  AVANZDERIV_BASE=/custom/path
  AVANZDERIV_IMAGE=ghcr.io/avanzderiv/avanzderiv-pilot:2.0
EOF_USAGE
}

case "${1:-native}" in
  native)
    install_native
    ;;

  docker)
    case "$OS" in
      linux|mac|windows)
        install_container_from_archive
        ;;
      *)
        log "ERROR: unsupported platform: $PLATFORM"
        exit 1
        ;;
    esac
    ;;

  docker-pull)
    case "$OS" in
      linux|mac|windows)
        install_container_from_registry docker
        ;;
      *)
        log "ERROR: unsupported platform: $PLATFORM"
        exit 1
        ;;
    esac
    ;;

  podman-pull)
    case "$OS" in
      linux|mac)
        install_container_from_registry podman
        ;;
      *)
        log "ERROR: podman-pull unsupported platform: $PLATFORM"
        exit 1
        ;;
    esac
    ;;

  demo)
    provision_demo
    ;;

  -h|--help|help)
    usage
    ;;

  *)
    usage
    exit 1
    ;;
esac

