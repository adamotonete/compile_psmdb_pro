# Compile PSMDB 8.0.12-4 in Docker (Oracle Linux 9)

This repository provides a **brew-style one-liner** to build **Percona Server for MongoDB (PSMDB)** inside an `oraclelinux:9` container and place the resulting binaries on your host.

- Inside the container, the build script compiles PSMDB under the source tree and then **moves the final `mongod` binary to**:  
  `~/psmdb_binary/mongod`
- That directory is **bind-mounted** to a host folder so the compiled `mongod` appears locally.

## Important Note

This script was tested and proven to work with the **8.0.12-4** branch. There is **no guarantee** it will work for any other version. Feel free to change or adapt this script as needed for your environment.

## Quick start

Using **curl** (recommended):

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/adamotonete/compile_psmdb_pro/refs/heads/main/script/build.sh)"

Using **wget**:

wget -qO- https://raw.githubusercontent.com/adamotonete/compile_psmdb_pro/refs/heads/main/script/build.sh | bash

By default, binaries land in `./psmdb-bin` relative to your current directory.

### Apple Silicon (M1/M2/M3) building **x86_64** binaries

If you need **amd64** binaries from an Apple Silicon host, set `DOCKER_PLATFORM=linux/amd64`:

DOCKER_PLATFORM=linux/amd64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/adamotonete/compile_psmdb_pro/refs/heads/main/script/build.sh)"

(If you’re fine with native ARM64 binaries, just omit `DOCKER_PLATFORM`.)

## Where do the binaries go?

- **Container build tree (intermediate)**: `$PSMDB_SRC/build/install/bin/`  
- **Container final output (what gets bind-mounted)**: `~/psmdb_binary/` (i.e., `/root/psmdb_binary/`)  
- **Host path**: `${PSMDB_OUT}` (defaults to `./psmdb-bin`)

Example check:

./psmdb-bin/mongod --version

## Requirements

- **Docker** installed and the **daemon running**  
  - macOS: Docker Desktop  
  - Linux: Docker Engine (`sudo systemctl start docker`)
- Internet access from the container to fetch the internal build script.

The wrapper **checks** for Docker and will fail early with a helpful message if it’s missing/stopped.

## What `build.sh` does

1. Verifies Docker is installed and running.
2. Creates (if needed) your host output directory (`$PSMDB_OUT`, default `./psmdb-bin`).
3. Runs an `oraclelinux:9` container and **bind-mounts**:
   HOST:$PSMDB_OUT  <->  CONTAINER:/root/psmdb_binary
4. Installs minimal prerequisites (`wget`, `ca-certificates`) in the container.
5. Downloads your internal build script:
   https://raw.githubusercontent.com/adamotonete/compile_psmdb_pro/refs/heads/main/script/build_psmdb.sh
6. Compiles PSMDB, then **moves the final `mongod`** from the build tree to `~/psmdb_binary/mongod` so it appears on the host.
7. Exits and removes the container (`--rm`), leaving your binaries on the host.

> Note: If you also want other binaries (e.g., `mongos`), extend the internal build script to move/copy them into `~/psmdb_binary/` as well.

## Environment variables

You can customize behavior with these optional env vars:

| Variable           | Default                                         | Purpose |
|--------------------|-------------------------------------------------|---------|
| `PSMDB_OUT`        | `./psmdb-bin`                                   | Host directory to receive compiled binaries. |
| `DOCKER_PLATFORM`  | _(unset)_                                       | Force target platform (e.g., `linux/amd64` on Apple Silicon). |
| `IMAGE`            | `oraclelinux:9`                                 | (Advanced) Override base image. |
| `BUILD_URL`        | Raw URL to `script/build_psmdb.sh` in this repo | (Advanced) Point to a different build script (e.g., tag/commit). |

Examples:

# Choose a different output directory
PSMDB_OUT="$HOME/psmdb-out" wget -qO- https://raw.githubusercontent.com/adamotonete/compile_psmdb_pro/refs/heads/main/script/build.sh | bash

# Force x86_64 build on Apple Silicon
DOCKER_PLATFORM=linux/amd64 wget -qO- https://raw.githubusercontent.com/adamotonete/compile_psmdb_pro/refs/heads/main/script/build.sh | bash

## Troubleshooting

- **“the input device is not a TTY”**  
  `build.sh` avoids `-t`, so this shouldn’t happen when piping. If you run `docker run` manually, drop `-t` when piping scripts.

- **“Docker is not installed / daemon not running”**  
  Install Docker and ensure the daemon is running (Docker Desktop on macOS; `sudo systemctl start docker` on Linux).

- **Binary didn’t appear in `psmdb-bin`**  
  Ensure the internal build script moves/copies the artifact(s) into `~/psmdb_binary/` inside the container. That exact path is bind-mounted to your host.

- **Slow builds on Apple Silicon with `linux/amd64`**  
  Cross-arch builds use emulation and can be slower. That’s expected.

## Security & reproducibility

- The wrapper downloads and runs a script via HTTPS. **Review the script** if you’re concerned.
- For stricter pinning, set `BUILD_URL` to a **tag or commit SHA** (e.g., `.../raw/<commit>/script/build_psmdb.sh`) to lock the exact build recipe.

## Windows / WSL2

Run under **WSL2** with Docker Desktop for Windows. Use the same commands; ensure the mounted path (`$PSMDB_OUT`) is within your WSL filesystem for best performance.

## License
MIT - https://en.wikipedia.org/wiki/MIT_License
