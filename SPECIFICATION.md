# Carafe Docker Specification

## Overview

This repository builds a Docker image for running Carafe in a controlled Ubuntu-based environment.
It is a packaging repository, not the Carafe application source repository.

The image bundles:

- Ubuntu 24.04
- Java 21
- System Python 3
- Python dependencies installed by Carafe's bundled `main.java.util.PyInstaller` bootstrapper during image build
- A Carafe release archive downloaded from GitHub during image build
- A prebuilt Carafe Python virtual environment installed under `/opt/carafe-home/.carafe`
- A uv-managed CPython installation rooted under `/opt/carafe-home/uv-python` so the Carafe venv does not depend on `/root` or `/tmp`

At runtime, the container prepends Carafe's shared virtual environment to `PATH`, forces Java's `user.home` to `/opt/carafe-home` by default, and then executes the command passed to the container entrypoint without Conda activation.

## Repository Purpose

The project exists to:

- Build a Docker image for Carafe execution
- Package Carafe together with its Java runtime and Carafe-managed Python dependencies
- Publish the image to one or more container registries
- Provide a thin operational wrapper around the Carafe runtime environment

This repository does **not** contain:

- The Carafe source code
- Tests for Carafe behavior
- A complete release pipeline

## Specification Maintenance Rule

`SPECIFICATION.md` is part of the project, not optional supporting documentation.

If the project changes, this file must be updated in the same change whenever the change affects:

- build inputs
- build steps
- image contents
- runtime behavior
- versioning
- publishing targets
- required tools
- onboarding steps
- known risks or operational assumptions

Any developer or LLM agent working in this repository should treat keeping this specification current as a required acceptance criterion for project changes.

## Repository Contents

The repository is intentionally small. The current tracked files are:

- `Dockerfile`: multi-stage image build definition
- `entrypoint.sh`: container entrypoint that executes the requested command
- `build.sh`: helper script that requires a Carafe version, builds matching image tags, can write the Docker build output to a log file, and optionally pushes images
- `test/test_carafe_image.sh`: local smoke test that builds the image, can forward build flags and build-log output to `build.sh`, and runs Carafe inside the container
- `.github/workflows/ci.yml`: GitHub Actions workflow that runs the image build and smoke test on push
- `README.md`: minimal placeholder readme
- `LICENSE`: Apache 2.0 license text
- `.gitignore`: note explaining that Carafe release archives are no longer stored locally

## High-Level Architecture

The build uses a two-stage Docker image:

1. Builder stage
2. Final runtime stage

### Builder Stage

The builder stage starts from `ubuntu:24.04` and performs the release download and unpacking:

- Installs OS packages:
  - `ca-certificates`
  - `wget`
  - `unzip`
- Requires the Docker build argument `CARAFE_VERSION`
- Downloads `carafe-${CARAFE_VERSION}.zip` from the matching GitHub release URL
- Unpacks the downloaded Carafe archive into `/opt/carafe`

The download URL format is:

- `https://github.com/Noble-Lab/Carafe/releases/download/v${CARAFE_VERSION}/carafe-${CARAFE_VERSION}.zip`

For example, `CARAFE_VERSION=2.0.0` downloads:

- `https://github.com/Noble-Lab/Carafe/releases/download/v2.0.0/carafe-2.0.0.zip`

Key outputs from the builder stage:

- `/opt/carafe`

Expected Carafe layout inside the image:

- `/opt/carafe/carafe-<version>/carafe-<version>.jar`

### Final Runtime Stage

The runtime stage also starts from `ubuntu:24.04` and copies the minimum assets needed to run:

- `/opt/carafe` from the builder
- `entrypoint.sh` into `/usr/local/bin/`

The runtime stage then:

- Installs `openjdk-21-jre-headless`
- Installs `ca-certificates`
- Installs `python3`, `python-is-python3`, `python3-pip`, and `python3-venv`
- Creates the shared runtime root at `/opt/carafe-home`
- Creates the uv-managed Python install root at `/opt/carafe-home/uv-python`
- Runs `java -cp carafe-<version>.jar main.java.util.PyInstaller /opt/carafe-home/.carafe` from the unpacked Carafe release directory with `HOME=/opt/carafe-home` and `UV_PYTHON_INSTALL_DIR=/opt/carafe-home/uv-python` so the venv's interpreter symlinks stay inside the shared runtime root
- Marks `/opt/carafe-home` world-readable so arbitrary runtime UIDs can execute the installed virtual environment
- Creates `/tmp/huggingface`
- Makes `/tmp/huggingface` world-writable
- Makes the entrypoint executable
- Sets `WORKDIR /app`
- Uses `entrypoint.sh` as the image entrypoint

## Runtime Behavior

Container startup is intentionally simple.

`entrypoint.sh` does the following:

1. Enables `set -euo pipefail`
2. Prepends `/opt/carafe-home/.carafe/.venv/bin` to `PATH` so plain `python` and `python3` resolve to Carafe's installed virtual environment
3. Appends `-Duser.home=/opt/carafe-home` to `JAVA_TOOL_OPTIONS` unless the caller already provided a `user.home` override
4. Replaces the shell with the user-provided command via `exec "$@"`

Implications:

- The container no longer depends on Conda being present
- Carafe's default `~/.carafe/.venv` lookup resolves against `/opt/carafe-home`, not the runtime user's actual home directory
- Arbitrary numeric UIDs can still use the prebuilt Carafe Python environment because it is not stored under `/root`
- The container does not define a default command in the Dockerfile
- The caller must provide the command to run unless the orchestration environment injects one

The expected Carafe invocation inside the container is:

```bash
java -Djava.aws.headless=true -jar /opt/carafe/carafe-<version>/carafe-<version>.jar
```

## Required Build Inputs

A fresh clone of this repository is sufficient to build the image. Carafe itself is downloaded during `docker build`, and the image no longer requires any local model archive.

## Versioning Model

There are two separate version concepts in this repository.

### Carafe payload version

This is controlled by the required Docker build argument:

- `CARAFE_VERSION`

There is no default value in the Dockerfile or `build.sh`.

This value affects:

- which Carafe GitHub release URL is downloaded
- which version tag is applied to the built image
- the `CARAFE_VERSION` environment variable in the final image

### Published image tags

`build.sh` always tags the built image with the version supplied on the command line.

For each registry name:

- `mriffle/carafe`
- `quay.io/protio/carafe`

`./build.sh 2.0.0` produces:

- `mriffle/carafe:2.0.0`
- `quay.io/protio/carafe:2.0.0`

If `--latest-tag` is supplied, the script also adds:

- `mriffle/carafe:latest`
- `quay.io/protio/carafe:latest`

`latest` is intentionally opt-in so an older release build does not accidentally become the latest tag.

## Build Workflow

There are two supported ways to build the image:

1. Use `build.sh`
2. Run `docker build` manually

### Option 1: Build with `build.sh`

The helper script:

- Enables Docker BuildKit
- Requires the Carafe version as a positional argument
- Passes `CARAFE_VERSION` into the Docker build
- Builds versioned tags for each configured registry
- Optionally tees Docker build output to a log file
- Optionally pushes all tags
- Optionally adds `latest` tags

Basic build:

```bash
./build.sh 2.0.0
```

Build and push:

```bash
./build.sh 2.0.0 --push
```

Build and capture the Docker build log:

```bash
./build.sh 2.0.0 --build-log /tmp/carafe-build.log
```

Build, tag as both `2.0.0` and `latest`, and push:

```bash
./build.sh 2.0.0 --push --latest-tag
```

### What `build.sh` actually does

The script constructs and executes a command equivalent to:

```bash
DOCKER_BUILDKIT=1 docker build \
  --build-arg CARAFE_VERSION=2.0.0 \
  -t mriffle/carafe:2.0.0 \
  -t quay.io/protio/carafe:2.0.0 \
  .
```

If `--latest-tag` is also supplied, the build additionally includes:

- `-t mriffle/carafe:latest`
- `-t quay.io/protio/carafe:latest`

If `--push` is supplied, the script pushes the version tag for each registry and pushes `latest` too when `--latest-tag` is enabled.

If `--build-log <path>` is supplied, the script writes the Docker build stdout and stderr stream to the specified file while still streaming it to the terminal.

### Option 2: Build manually

If you want explicit control, use `docker build` directly.

Example for Carafe `2.0.0`:

```bash
DOCKER_BUILDKIT=1 docker build \
  --build-arg CARAFE_VERSION=2.0.0 \
  -t carafe:2.0.0 \
  .
```

The Dockerfile downloads Carafe from:

- `https://github.com/Noble-Lab/Carafe/releases/download/v${CARAFE_VERSION}/carafe-${CARAFE_VERSION}.zip`

For example:

- `--build-arg CARAFE_VERSION=2.1.0`
- downloads `https://github.com/Noble-Lab/Carafe/releases/download/v2.1.0/carafe-2.1.0.zip`

## Test Workflow

This repository includes a smoke test that verifies both image construction and basic Carafe execution.

### Local smoke test

Run:

```bash
./test/test_carafe_image.sh 2.0.0
```

To capture the Docker build log while running the smoke test:

```bash
./test/test_carafe_image.sh 2.0.0 --build-log /tmp/carafe-build.log
```

The smoke test does the following:

1. Builds the image by calling `./build.sh <version>`
2. Starts a container from the built image as a non-root numeric UID
3. Verifies the image no longer exposes the old `/opt/conda` installation path
4. Verifies both `python` and `python3` are available in the image
5. Verifies the shared Carafe virtual environment exists at `/opt/carafe-home/.carafe/.venv`
6. Verifies the shared Carafe virtual environment resolves to an interpreter path inside `/opt/carafe-home`
7. Verifies the entrypoint resolves `python` from that shared virtual environment and can import `torch`
8. Verifies the entrypoint configures Java to use `/opt/carafe-home` as `user.home`
9. Verifies the entrypoint no longer injects a `CONDA_DEFAULT_ENV`
10. Verifies the packaged Carafe JAR exists at `/opt/carafe/carafe-<version>/carafe-<version>.jar`
11. Runs `java -Djava.aws.headless=true -jar /opt/carafe/carafe-<version>/carafe-<version>.jar -h`
12. Confirms the help output contains expected Carafe CLI text

### GitHub Actions CI

GitHub Actions runs the smoke test on every push using:

- `.github/workflows/ci.yml`

The workflow currently tests Carafe version:

- `2.0.0`

That value is defined in the workflow environment as:

- `CARAFE_TEST_VERSION`

When the project moves to a new Carafe release for CI validation, update:

1. `.github/workflows/ci.yml`
2. this specification if the documented test version or process changes

## Build Prerequisites

To build successfully, a developer should have:

- Docker installed
- Permission to run Docker directly
- Network access during build for:
  - Ubuntu package installation
  - Carafe release download from GitHub
  - whatever upstream Python package downloads Carafe's bundled `PyInstaller` performs

To run the local smoke test, a developer should also have:

- Docker available to the current user

## Expected Build Sequence

From a clean checkout, the expected onboarding flow is:

1. Clone this repository
2. Choose the Carafe release version you want to build, for example `2.0.0`
3. Run `./build.sh <version>` or a manual `docker build --build-arg CARAFE_VERSION=<version>`
4. Optionally add `--latest-tag` if this build should also publish the `latest` tag
5. Optionally push the tags to the configured registries

## External Dependencies

This repository depends on several systems outside the repo:

- Ubuntu package repositories
- GitHub-hosted Carafe release archives following the `v<version>/carafe-<version>.zip` convention
- The upstream Python package indexes or other artifact sources used by Carafe's bundled `PyInstaller`

Because these are external and partly mutable, the build is not fully hermetic or reproducible.

## Paths and Environment Inside the Image

Important filesystem paths:

- `/opt/carafe`: unpacked Carafe distribution
- `/opt/carafe-home/.carafe`: Carafe-managed Python environment root
- `/opt/carafe-home/.carafe/.venv/bin/python3`: default Python executable Carafe resolves at runtime
- `/opt/carafe-home/uv-python`: uv-managed CPython installation root used by the Carafe virtual environment
- `/usr/local/bin/entrypoint.sh`: runtime entrypoint
- `/tmp/huggingface`: Hugging Face cache location
- `/app`: working directory

Important environment variables:

- `LANG=C.UTF-8`
- `LC_ALL=C.UTF-8`
- `CARAFE_RUNTIME_HOME=/opt/carafe-home`
- `CARAFE_UV_PYTHON_INSTALL_DIR=/opt/carafe-home/uv-python`
- `HOME=/tmp`
- `HF_HOME=/tmp/huggingface`
- `CARAFE_VERSION=<build arg value in final stage>`
- `JAVA_TOOL_OPTIONS` is extended by the entrypoint to include `-Duser.home=/opt/carafe-home` unless the caller already provided a `user.home` override

## Current Design Assumptions

A new developer or agent should understand these assumptions before making changes:

- The repo assumes Carafe is distributed as a GitHub release zip, not built from source here
- The repo assumes future Carafe releases follow the `v<version>/carafe-<version>.zip` convention
- The repo assumes Carafe's bundled `main.java.util.PyInstaller` remains the supported way to provision Carafe's Python dependencies during image build
- The repo assumes installing Carafe's Python environment into `/opt/carafe-home/.carafe` remains compatible with Carafe's runtime lookup when Java is launched with `-Duser.home=/opt/carafe-home`
- The repo assumes directing uv's managed CPython installation into `/opt/carafe-home/uv-python` keeps the venv self-contained enough for container runtimes that replace `/tmp` or use arbitrary UIDs
- The repo assumes prepending `/opt/carafe-home/.carafe/.venv/bin` to `PATH` is sufficient for Carafe helper code that still invokes plain `python`
- The repo assumes container callers know what command to execute
- The repo assumes publishing to both Docker Hub and Quay

## Operational Gaps and Risks

These are current project realities, not theoretical concerns:

- `README.md` does not document the build process
- CI currently validates a fixed Carafe version, `2.0.0`, which will need to be updated over time as releases change
- The Dockerfile uses mutable upstreams:
  - `ubuntu:24.04`
  - GitHub-hosted Carafe release assets
  - the upstream dependency sources contacted by Carafe's bundled `PyInstaller`
- There are no automated tests or validation steps in this repository

## How to Modify the Project Safely

When updating this repository, check these areas together:

### If you change the Carafe version

- Pass the desired version on the command line or through `--build-arg CARAFE_VERSION=...`
- Ensure the upstream Carafe release follows the expected GitHub URL convention
- Update the build logic only if the release naming convention changes
- Update the CI test version if the smoke test should validate a newer release
- Update this specification

### If you change registries or image names

- Update the `image_names` array in `build.sh`
- Verify authentication for each registry before pushing
- Update onboarding documentation
- Update this specification

### If you change runtime behavior

- Update `entrypoint.sh`
- Verify the container still forwards commands correctly and does not depend on removed bootstrap state
- Document the expected container command pattern
- Update this specification

### If you change Python dependency provisioning

- Review the current Carafe release documentation for `main.java.util.PyInstaller`
- Verify the image still includes the system Python pieces required to run that installer
- Consider pinning or documenting more of the upstream dependency resolution performed by Carafe's installer for reproducibility
- Update this specification

## Recommended Validation Checklist

After making changes, validate at least the following:

1. `bash -n build.sh`
2. `bash -n entrypoint.sh`
3. `bash -n test/test_carafe_image.sh`
4. Run a Docker build with an explicit `CARAFE_VERSION`
5. Run `./test/test_carafe_image.sh <version>`
6. If applicable, verify pushed tags exist in the target registries

## Suggested Future Improvements

These are the most useful improvements for maintainability:

- Replace the placeholder `README.md` with a concise quickstart that links to this specification
- Expand the smoke test beyond `java -jar ... -h` if a lightweight fully representative Carafe test dataset becomes available
- Document or pin more of the dependency resolution performed by Carafe's bundled `PyInstaller`

## Quickstart for a New Developer or Agent

If you need to work on this repo without reading the source files first, use this checklist:

1. Understand that this repo only packages Carafe into a Docker image
2. Choose the Carafe release version you want to build
3. Ensure Docker works in your environment
4. Run `./build.sh <version>`
5. Run `./test/test_carafe_image.sh <version>` to verify the built image and Carafe installation
6. Use `--latest-tag` only when that version should also become `latest`
7. If the build or smoke test fails, first check Docker permissions, network access, and upstream release availability
8. Treat `Dockerfile`, `build.sh`, `entrypoint.sh`, `test/test_carafe_image.sh`, and `.github/workflows/ci.yml` as the key operational codepaths in the repo

That is the full current system.
