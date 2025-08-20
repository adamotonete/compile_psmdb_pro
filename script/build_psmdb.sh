#!/usr/bin/env bash
# Build PSMDB 8.0.12-4 with FIPS/FCBIS/OIDC on Oracle Linux 9 (Docker/VM)
# Usage:
#   chmod +x build_psmdb.sh
#   ./build_psmdb.sh
#
# Optional environment overrides:
#   AWS_SDK_VER=1.9.379 PSMDB_BRANCH=origin/release-8.0.12-4 BUILD_JOBS=8 ./build_psmdb.sh
#   LOG_FILE=/path/to/custom.log LINKER_EXTRA="--linker=gold" ./build_psmdb.sh
#
# The script writes a log with timestamps to $HOME/psmdb_build_YYYYmmdd_HHMMSS.log by default.

set -Eeuo pipefail

# ---------- Run metadata & logging ----------
RUN_TS="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="${LOG_FILE:-$HOME/psmdb_build_${RUN_TS}.log}"

# Redirect all stdout/stderr to the log (and still show on console)
exec > >(tee -a "$LOG_FILE") 2>&1

now() { date '+%Y-%m-%d %H:%M:%S %z'; }
log() { echo -e "\n[$(now)] $*"; }

trap 'echo "[ERROR] [$(now)] Line ${LINENO}: command \"${BASH_COMMAND}\" failed." >&2' ERR

log "RUN START (log: $LOG_FILE)"
uname -a || true
log "Shell: $SHELL | User: $(id -un) (uid $(id -u))"
log "Working dir: $(pwd)"

# ---------- Config (change as needed) ----------
AWS_SDK_VER="${AWS_SDK_VER:-1.9.379}"
PSMDB_BRANCH="${PSMDB_BRANCH:-origin/release-8.0.12-4}"
PSMDB_VERSION_JSON="${PSMDB_VERSION_JSON:-8.0.12-4}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc --all)}"
AWS_LIBS="${AWS_LIBS:-/tmp/lib/aws}"
VENV_DIR="${VENV_DIR:-$HOME/p311}"
AWS_SRC="${AWS_SRC:-$HOME/aws-sdk-cpp}"
PSMDB_SRC="${PSMDB_SRC:-$HOME/percona-server-mongodb}"
LINKER_EXTRA="${LINKER_EXTRA:-}"   # set to "--linker=gold" if lld error appears

log "Config:"
echo "  AWS_SDK_VER       = $AWS_SDK_VER"
echo "  PSMDB_BRANCH      = $PSMDB_BRANCH"
echo "  PSMDB_VERSION_JSON= $PSMDB_VERSION_JSON"
echo "  BUILD_JOBS        = $BUILD_JOBS"
echo "  AWS_LIBS          = $AWS_LIBS"
echo "  VENV_DIR          = $VENV_DIR"
echo "  AWS_SRC           = $AWS_SRC"
echo "  PSMDB_SRC         = $PSMDB_SRC"
echo "  LINKER_EXTRA      = $LINKER_EXTRA"

# Use sudo only when not root
if [[ $(id -u) -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

check_disk() {
  log "STEP: Check free disk space"
  local avail_gb
  avail_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
  echo "  Free space on /: ${avail_gb}G"
  if [[ -n "$avail_gb" && "$avail_gb" -lt 150 ]]; then
    echo "  [WARN] Low free space (<150G). Build may fail."
  fi
}

ensure_pkg() {
  log "STEP: Refresh package metadata"
  $SUDO dnf makecache -y

  log "STEP: Install required packages"
  $SUDO dnf install -y  lld   gcc-toolset-12     cmake     curl     binutils-devel     openssl-devel     openldap-devel     krb5-devel     libcurl-devel     cyrus-sasl-devel     bzip2-devel     zlib-devel     lz4-devel     xz-devel     e2fsprogs-devel     python3.11     python3.11-devel     python3.11-pip     python3.11-setuptools     python3.11-wheel     git     gcc     gcc-c++

  log "STEP: Sanity checks (python/gcc)"
  python3.11 --version
  /opt/rh/gcc-toolset-12/root/usr/bin/gcc --version
}

activate_gcc() {
  log "STEP: Activate GCC 12 toolset"
  if [[ -f /opt/rh/gcc-toolset-12/enable ]]; then
    # shellcheck disable=SC1091
    source /opt/rh/gcc-toolset-12/enable
  else
    echo "[ERROR] gcc-toolset-12 enable script not found." >&2
    exit 1
  fi
}

create_venv() {
  log "STEP: Create Python 3.11 virtual environment"
  mkdir -p "$VENV_DIR"
  python3.11 -m venv "$VENV_DIR" --prompt mongodb
  # shellcheck disable=SC1090
  source "$VENV_DIR/bin/activate"

  log "STEP: Upgrade pip/setuptools/wheel"
  pip install --upgrade pip setuptools wheel

  log "STEP: Install Python helpers (Poetry + plugins + cxxfilt)"
  pip install build pyproject_hooks importlib-metadata
  pip install "poetry==2.0.0" "poetry-plugin-export>=1.8"
  pip install cxxfilt
}

build_aws_sdk() {
  log "STEP: Get AWS SDK for C++ (version ${AWS_SDK_VER})"
  mkdir -p "$AWS_LIBS"
  if [[ -d "$AWS_SRC/.git" ]]; then
    git -C "$AWS_SRC" fetch --all --tags
  else
    git clone --recurse-submodules https://github.com/aws/aws-sdk-cpp.git "$AWS_SRC"
  fi
  git -C "$AWS_SRC" checkout "$AWS_SDK_VER"

  log "STEP: Configure AWS SDK (static, S3 + transfer)"
  mkdir -p "$AWS_SRC/build"
  cd "$AWS_SRC/build"
  cmake ..     -DCMAKE_BUILD_TYPE=Release     '-DBUILD_ONLY=s3;transfer'     -DBUILD_SHARED_LIBS=OFF     -DMINIMIZE_SIZE=ON     -DCMAKE_INSTALL_PREFIX="${AWS_LIBS}"

  log "STEP: Build & install AWS SDK"
  make -j"$BUILD_JOBS" install
}

get_psmdb() {
  log "STEP: Get PSMDB source (${PSMDB_BRANCH})"
  if [[ -d "$PSMDB_SRC/.git" ]]; then
    git -C "$PSMDB_SRC" fetch --all
  else
    git clone https://github.com/percona/percona-server-mongodb.git "$PSMDB_SRC"
  fi
  cd "$PSMDB_SRC"
  git checkout "$PSMDB_BRANCH"

  log "STEP: Write version.json with quoted fields"
  # Robust JSON creation (ensures quotes): {"version": "8.0.12-4"}
  printf '{"version": "%s"}
' "$PSMDB_VERSION_JSON" > version.json
  echo "  version.json => $(cat version.json)"
}

install_poetry_deps() {
  log "STEP: Install PSMDB Python dependencies with Poetry"
  source "$VENV_DIR/bin/activate"
  cd "$PSMDB_SRC"
  # workarounds as poetry is failing to compile
  pip install setuptools==58.1.0       
  pip install --use-pep517 requests-oauth==0.4.1 regex==2021.11.10 cheetah3==3.2.6.post1 pykmip==0.10.0  sentinels==1.0.0 zope.interface==5.0.0  
  # workarounds
  poetry install --no-root --sync
}

build_psmdb() {
  log "STEP: Build PSMDB with SCons"
  source "$VENV_DIR/bin/activate"
  cd "$PSMDB_SRC"
  buildscripts/scons.py     --disable-warnings-as-errors     --release     --ssl     --opt=on     -j"$BUILD_JOBS"     --use-sasl-client     --wiredtiger     --audit     --inmemory     --hotbackup     --full-featured     CPPPATH="${AWS_LIBS}/include"     LIBPATH="${AWS_LIBS}/lib ${AWS_LIBS}/lib64"     CXX="/opt/rh/gcc-toolset-12/root/usr/bin/c++"     CC="/opt/rh/gcc-toolset-12/root/usr/bin/gcc"     ${LINKER_EXTRA}     install-mongod

  log "STEP: Build finished. Binaries:"
  echo "  $PSMDB_SRC/build/install/bin"

  log "STEP: Strip Binaries / Creating .dbg files"
  
  cd "$PSMDB_SRC/build/install/bin/"

  for f in mongod; do
    [ -f "$f" ] || continue
    objcopy --only-keep-debug "$f" "$f.debug"
    strip --strip-unneeded "$f"
    objcopy --add-gnu-debuglink="$f.debug" "$f"
  done

  mv "$PSMDB_SRC/build/install/bin/mongod" "$HOME/psmdb_binary/mongod"
  log "Checking version"
  "$HOME/psmdb_binary/mongod" --version || true
}

main() {
  log "STEP: Start build"
  check_disk
  ensure_pkg
  activate_gcc
  create_venv
  build_aws_sdk
  get_psmdb
  install_poetry_deps
  build_psmdb
  log "RUN END"
}

main "$@"
