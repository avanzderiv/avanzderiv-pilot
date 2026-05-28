#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# Avanzderiv Pilot Edition Installer
#
# ROOT  = runtime root inside engine/container
# BASE  = host-side working directory
# ─────────────────────────────────────────────

EDITION="2.0_PE"
ROOT="/opt/avanzderiv"

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
      ;;
    aarch64|arm64)
      ARCH="arm64"
      ;;
    *)
      ARCH="unknown"
      ;;
  esac

  PLATFORM="${OS}-${ARCH}"
}

detect_os_arch

BIN="dist/avanzderiv-${EDITION}_${ARCH}"
IMAGE="dist/avanzderiv-${EDITION}_${ARCH}.tgz"

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

  if ! echo "$PATH" | grep -q "$LOCAL_BIN"; then
    echo ""
    echo "Add to shell profile:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
  fi
}

install_docker() {

  echo "Installing Avanzderiv ${EDITION} (Docker)..."
  echo "  PLATFORM : $PLATFORM"
  echo "  BASE     : $BASE"
  echo "  ROOT     : $ROOT"

  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running."
    exit 1
  fi

  if [ ! -f "$IMAGE" ]; then
    echo "ERROR: Docker image archive not found:"
    echo "  $IMAGE"
    exit 1
  fi

  if [ ! -f ".template.tar" ]; then
    echo "ERROR: .template.tar not found."
    exit 1
  fi

  docker load < "$IMAGE"

  mkdir -p \
    "$BASE/data" \
    "$BASE/metadata/contracts" \
    "$BASE/state" \
    "$BASE/warehouse"

  tar -xf .template.tar -C "$TEMP_DIR"

  if [ ! -f "$BASE/.env" ] && [ -f "$TEMP_DIR/template/.env.template" ]; then
    cp "$TEMP_DIR/template/.env.template" "$BASE/.env"
  fi

  if [ -d "$TEMP_DIR/template/metadata/contracts" ]; then
    cp -n "$TEMP_DIR/template/metadata/contracts/"* \
      "$BASE/metadata/contracts/" 2>/dev/null || true
  fi

  if [ -d "$TEMP_DIR/template/data" ]; then
    cp -n "$TEMP_DIR/template/data/"* \
      "$BASE/data/" 2>/dev/null || true
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

  ensure_local_bin

  cat > "$LOCAL_BIN/avanzderiv" <<EOF
#!/bin/bash

docker run --rm \\
  --env-file "$BASE/.env" \\
  -v "$BASE:$ROOT" \\
  avanzderiv:pilot2.0-${ARCH} "\$@"
EOF

  chmod +x "$LOCAL_BIN/avanzderiv"

  echo "Initialising engine..."
  "$LOCAL_BIN/avanzderiv" init

  echo "Checking status..."
  "$LOCAL_BIN/avanzderiv" status

  echo ""
  echo "Docker installation complete."
  echo "Run:"
  echo "  avanzderiv --help"
}

install_native() {

  echo "Installing Avanzderiv ${EDITION} (native Linux)..."
  echo "  ROOT : $ROOT"

  if [ "$OS" != "linux" ]; then
    echo "ERROR: Native install supported only on Linux."
    exit 1
  fi

  if [ ! -f "$BIN" ]; then
    echo "ERROR: Native binary not found:"
    echo "  $BIN"
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

  ln -sf \
    "$ROOT/venv/bin/avanzderiv" \
    "$LOCAL_BIN/avanzderiv"

  mkdir -p \
    "$ROOT/data" \
    "$ROOT/state" \
    "$ROOT/warehouse" \
    "$ROOT/metadata/contracts"

  tar -xf .template.tar -C "$TEMP_DIR"

  if [ ! -f "$ROOT/.env" ] \
    && [ -f "$TEMP_DIR/template/.env.template" ]; then

    cp "$TEMP_DIR/template/.env.template" "$ROOT/.env"
  fi

  if [ -d "$TEMP_DIR/template/metadata/contracts" ]; then
    cp -n "$TEMP_DIR/template/metadata/contracts/"* \
      "$ROOT/metadata/contracts/" 2>/dev/null || true
  fi

  if [ -d "$TEMP_DIR/template/data" ]; then
    cp -n "$TEMP_DIR/template/data/"* \
      "$ROOT/data/" 2>/dev/null || true
  fi

  if ! grep -q "^AVANZDERIV_SECRET_HEX=" "$ROOT/.env" \
    || grep -q "^AVANZDERIV_SECRET_HEX=$" "$ROOT/.env"; then

    SECRET="$("$ROOT/venv/bin/python" \
      -c 'import secrets; print(secrets.token_hex(32))')"

    if grep -q "^AVANZDERIV_SECRET_HEX=" "$ROOT/.env"; then
      sed -i \
        "s/^AVANZDERIV_SECRET_HEX=.*/AVANZDERIV_SECRET_HEX=$SECRET/" \
        "$ROOT/.env"
    else
      echo "AVANZDERIV_SECRET_HEX=$SECRET" >> "$ROOT/.env"
    fi
  fi

  "$ROOT/venv/bin/avanzderiv" init
  "$ROOT/venv/bin/avanzderiv" status

  echo ""
  echo "Native installation complete."
  echo "Run:"
  echo "  avanzderiv --help"
}

provision_demo() {

  echo "Provisioning demo..."

  DATA_REF="$ROOT/data/sample_data.csv"

  if ! avanzderiv status >/dev/null 2>&1; then
    echo "ERROR: Avanzderiv not initialised."
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

  echo ""
  echo "Demo provisioned."
  echo "Run:"
  echo "  avanzderiv query --context public --table sample_surface_v1"
}

case "${1:-native}" in

  native)
    case "$OS" in
      linux)
        install_native
        ;;
      *)
        echo "ERROR: Native install supported only on Linux."
        echo "Run:"
        echo "  ./setup.sh docker"
        exit 1
        ;;
    esac
    ;;

  docker)
    case "$OS" in
      linux|mac|windows)
        install_docker
        ;;
      *)
        echo "ERROR: unsupported platform: $PLATFORM"
        exit 1
        ;;
    esac
    ;;

  demo)
    provision_demo
    ;;

  *)
    echo "Usage:"
    echo "  ./setup.sh"
    echo "  ./setup.sh docker"
    echo "  ./setup.sh demo"
    exit 1
    ;;
esac
