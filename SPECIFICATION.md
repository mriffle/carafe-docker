# Carafe Docker Specification

## Overview

This repository builds a Docker image for running Carafe in a controlled Ubuntu-based environment.
It is a packaging repository, not the Carafe application source repository.

The image bundles:

- Ubuntu 24.04
- Java 21
- Miniconda
- A Conda environment named `carafe`
- The `alphapeptdeep_dia` Python package, installed from its upstream GitHub repository
- A Carafe release archive downloaded from GitHub during image build
- A locally supplied pretrained model archive

At runtime, the container activates the `carafe` Conda environment and then executes the command passed to the container entrypoint.

## Repository Purpose

The project exists to:

- Build a Docker image for Carafe execution
- Package Carafe together with its Python and Java dependencies
- Publish the image to one or more container registries
- Provide a thin operational wrapper around the Carafe runtime environment

This repository does **not** contain:

- The Carafe source code
- Tests for Carafe behavior
- A complete release pipeline
- The pretrained model zip required at build time

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
- `entrypoint.sh`: container entrypoint that activates Conda and executes the requested command
- `build.sh`: helper script that requires a Carafe version, builds matching image tags, and optionally pushes them
- `test/test_carafe_image.sh`: local smoke test that builds the image and runs Carafe inside the container
- `.github/workflows/ci.yml`: GitHub Actions workflow that runs the image build and smoke test on push
- `README.md`: minimal placeholder readme
- `LICENSE`: Apache 2.0 license text
- `.gitignore`: note explaining that Carafe release archives are no longer stored locally

## High-Level Architecture

The build uses a two-stage Docker image:

1. Builder stage
2. Final runtime stage

### Builder Stage

The builder stage starts from `ubuntu:24.04` and performs the heavyweight setup:

- Installs OS packages:
  - `wget`
  - `git`
  - `unzip`
  - `openjdk-21-jdk`
- Installs Miniconda into `/opt/conda`
- Accepts Conda terms of service for the default Anaconda channels
- Clones the upstream `alphapeptdeep_dia` repository from GitHub
- Creates the `carafe` Conda environment using `alphapeptdeep_dia/conda_environment.yml`
- Activates the environment and installs `alphapeptdeep_dia` with `pip install .`
- Requires the Docker build argument `CARAFE_VERSION`
- Downloads `carafe-${CARAFE_VERSION}.zip` from the matching GitHub release URL
- Unpacks the downloaded Carafe archive into `/opt/carafe`

The download URL format is:

- `https://github.com/Noble-Lab/Carafe/releases/download/v${CARAFE_VERSION}/carafe-${CARAFE_VERSION}.zip`

For example, `CARAFE_VERSION=2.0.0` downloads:

- `https://github.com/Noble-Lab/Carafe/releases/download/v2.0.0/carafe-2.0.0.zip`

Key outputs from the builder stage:

- `/opt/conda`
- `/opt/carafe`
- `/root/.bashrc`

Expected Carafe layout inside the image:

- `/opt/carafe/carafe-<version>/carafe-<version>.jar`

### Final Runtime Stage

The runtime stage also starts from `ubuntu:24.04` and copies the minimum assets needed to run:

- `/opt/conda` from the builder
- `/opt/carafe` from the builder
- `/root/.bashrc` from the builder
- `entrypoint.sh` into `/usr/local/bin/`
- `pretrained_models.zip` into `/data/peptdeep/pretrained_models/`

The runtime stage then:

- Installs `openjdk-21-jre-headless`
- Creates `/tmp/huggingface`
- Makes `/tmp/huggingface` world-writable
- Makes the entrypoint executable
- Sets `WORKDIR /app`
- Uses `entrypoint.sh` as the image entrypoint

## Runtime Behavior

Container startup is intentionally simple.

`entrypoint.sh` does the following:

1. Enables `set -e`
2. Sources `/opt/conda/etc/profile.d/conda.sh`
3. Activates the `carafe` Conda environment
4. Replaces the shell with the user-provided command via `exec "$@"`

Implications:

- The container will fail immediately if the Conda installation or `carafe` environment is missing
- The container does not define a default command in the Dockerfile
- The caller must provide the command to run unless the orchestration environment injects one

The expected Carafe invocation inside the container is:

```bash
java -Djava.aws.headless=true -jar /opt/carafe/carafe-<version>/carafe-<version>.jar
```

## Required Build Inputs

A fresh clone of this repository is almost sufficient to build the image. Carafe itself is downloaded during `docker build`, so only one local artifact is still required.

### Pretrained models archive

The Dockerfile expects:

- `pretrained_models.zip`

It is copied into:

- `/data/peptdeep/pretrained_models/`

Important implementation detail:

- The Dockerfile copies this file but does **not** unzip it
- Any workflow that expects extracted model files must handle extraction elsewhere, or the Dockerfile must be updated

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

The smoke test does the following:

1. Ensures `pretrained_models.zip` exists
2. Creates a temporary placeholder `pretrained_models.zip` if one is not already present
3. Builds the image by calling `./build.sh <version>`
4. Starts a container from the built image
5. Verifies the entrypoint activated the `carafe` Conda environment
6. Verifies `/data/peptdeep/pretrained_models/pretrained_models.zip` exists in the image
7. Verifies the packaged Carafe JAR exists at `/opt/carafe/carafe-<version>/carafe-<version>.jar`
8. Runs `java -Djava.aws.headless=true -jar /opt/carafe/carafe-<version>/carafe-<version>.jar -h`
9. Confirms the help output contains expected Carafe CLI text

The placeholder model archive exists only to satisfy the current Docker build requirement during testing. The smoke test validates that Carafe is installed and runnable, but it does not validate the contents of the pretrained model archive.

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
- `pretrained_models.zip` in the repository root
- Network access during build for:
  - Ubuntu package installation
  - Miniconda download
  - GitHub clone of `alphapeptdeep_dia`
  - Carafe release download from GitHub
  - Conda environment creation

To run the local smoke test, a developer should also have:

- Docker available to the current user
- the `zip` command available to create the temporary placeholder model archive when needed

## Expected Build Sequence

From a clean checkout, the expected onboarding flow is:

1. Clone this repository
2. Obtain `pretrained_models.zip` and place it in the repo root
3. Choose the Carafe release version you want to build, for example `2.0.0`
4. Run `./build.sh <version>` or a manual `docker build --build-arg CARAFE_VERSION=<version>`
5. Optionally add `--latest-tag` if this build should also publish the `latest` tag
6. Optionally push the tags to the configured registries

## External Dependencies

This repository depends on several systems outside the repo:

- Ubuntu package repositories
- `repo.anaconda.com` for Miniconda and Conda packages
- `github.com/wenbostar/alphapeptdeep_dia`
- GitHub-hosted Carafe release archives following the `v<version>/carafe-<version>.zip` convention
- A local pretrained model archive maintained elsewhere

Because these are external and partly mutable, the build is not fully hermetic or reproducible.

## Paths and Environment Inside the Image

Important filesystem paths:

- `/opt/conda`: Miniconda installation and Conda environments
- `/opt/carafe`: unpacked Carafe distribution
- `/usr/local/bin/entrypoint.sh`: runtime entrypoint
- `/data/peptdeep/pretrained_models/`: location where `pretrained_models.zip` is copied
- `/tmp/huggingface`: Hugging Face cache location
- `/app`: working directory

Important environment variables:

- `PATH=/opt/conda/bin:${PATH}`
- `LANG=C.UTF-8`
- `LC_ALL=C.UTF-8`
- `HF_HOME=/tmp/huggingface`
- `CARAFE_VERSION=<build arg value in final stage>`

## Current Design Assumptions

A new developer or agent should understand these assumptions before making changes:

- The repo assumes Carafe is distributed as a GitHub release zip, not built from source here
- The repo assumes future Carafe releases follow the `v<version>/carafe-<version>.zip` convention
- The repo assumes `alphapeptdeep_dia` defines a Conda environment named `carafe`
- The repo assumes container callers know what command to execute
- The repo assumes model provisioning via `pretrained_models.zip`, but the archive is not expanded during image build
- The repo assumes publishing to both Docker Hub and Quay

## Operational Gaps and Risks

These are current project realities, not theoretical concerns:

- `README.md` does not document the build process
- The repo does not contain `pretrained_models.zip`, which is still required locally
- CI currently validates a fixed Carafe version, `2.0.0`, which will need to be updated over time as releases change
- The Dockerfile uses mutable upstreams:
  - `ubuntu:24.04`
  - `Miniconda3-latest-Linux-x86_64.sh`
  - GitHub-hosted Carafe release assets
  - unpinned `alphapeptdeep_dia` repository HEAD
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
- Verify the container still activates the Conda environment correctly
- Document the expected container command pattern
- Update this specification

### If you change Python or Conda dependencies

- Review how `alphapeptdeep_dia` creates the `carafe` environment
- Verify the environment name still matches `entrypoint.sh`
- Consider pinning upstream revisions for reproducibility
- Update this specification

## Recommended Validation Checklist

After making changes, validate at least the following:

1. `bash -n build.sh`
2. `bash -n entrypoint.sh`
3. `bash -n test/test_carafe_image.sh`
4. Confirm `pretrained_models.zip` exists, or let the smoke test create its temporary placeholder archive
5. Run a Docker build with an explicit `CARAFE_VERSION`
6. Run `./test/test_carafe_image.sh <version>`
7. If applicable, verify pushed tags exist in the target registries

## Suggested Future Improvements

These are the most useful improvements for maintainability:

- Replace the placeholder `README.md` with a concise quickstart that links to this specification
- Expand the smoke test beyond `java -jar ... -h` if a lightweight fully representative Carafe test dataset becomes available
- Replace the placeholder `pretrained_models.zip` test fixture approach with a canonical downloadable test artifact if one becomes available
- Pin the `alphapeptdeep_dia` revision and consider pinning the Miniconda installer source more tightly
- Decide whether `pretrained_models.zip` should be unpacked during the build

## Quickstart for a New Developer or Agent

If you need to work on this repo without reading the source files first, use this checklist:

1. Understand that this repo only packages Carafe into a Docker image
2. Place `pretrained_models.zip` in the repository root
3. Choose the Carafe release version you want to build
4. Ensure Docker works in your environment
5. Run `./build.sh <version>`
6. Run `./test/test_carafe_image.sh <version>` to verify the built image and Carafe installation
7. Use `--latest-tag` only when that version should also become `latest`
8. If the build or smoke test fails, first check Docker permissions, missing `pretrained_models.zip`, network access, and upstream release availability
9. Treat `Dockerfile`, `build.sh`, `entrypoint.sh`, `test/test_carafe_image.sh`, and `.github/workflows/ci.yml` as the key operational codepaths in the repo

That is the full current system.
