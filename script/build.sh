#!/usr/bin/env bash
# Minimal wrapper to build PSMDB inside oraclelinux:9 and copy binaries to host
set -Eeuo pipefail

# --- Config (env-tweakable) ---------------------------------------------------
# Where binaries land on the HOST:
: "${PSMDB_OUT:=$PWD/psmdb-bin}"

# Docker platform override (e.g., linux/amd64 for Apple Silicon cross-build):
# usage: DOCKER_PLATFORM=linux/amd64 bash run_build_in_docker.sh
: "${DOCKER_PLATFORM:=}"

# Base image and the build script to run INSIDE the container:
: "${IMAGE:=oraclelinux:9}"
: "${BUILD_URL:=https://raw.githubusercontent.com/adamotonete/compile_psmdb_pro/refs/heads/main/script/build_psmdb.sh}"

# --- Checks -------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker is not installed or not in PATH." >&2
  echo "Install Docker Desktop (macOS) or Docker Engine, then retry." >&2
  exit 127
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon is not running or not reachable." >&2
  echo "Start Docker Desktop (macOS) or run: sudo systemctl start docker" >&2
  exit 1
fi

mkdir -p "$PSMDB_OUT"

# --- Run ----------------------------------------------------------------------
# Maps host $PSMDB_OUT -> /root/psmdb_binary/
# so your compiled 'mongod', etc., appear locally.
set -x
docker run \
  ${DOCKER_PLATFORM:+--platform "$DOCKER_PLATFORM"} \
  --rm -t \
  -v "$PSMDB_OUT:/root/psmdb_binary" \
  "$IMAGE" bash -lc "
    set -Eeuo pipefail
    (command -v microdnf >/dev/null && microdnf -y install wget ca-certificates) || dnf -y install wget ca-certificates
    update-ca-trust || true
    wget -qO /tmp/build_psmdb.sh '$BUILD_URL'
    chmod +x /tmp/build_psmdb.sh
    /tmp/build_psmdb.sh
  "
set +x

echo "✅ Done. Binaries are in: $PSMDB_OUT"