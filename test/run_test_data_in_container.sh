#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
carafe_version=""
image_tag=""
skip_build=false
build_args=()

print_usage() {
    cat <<'EOF'
Usage: ./test/run_test_data_in_container.sh <carafe-version> [--skip-build] [--push] [--latest-tag] [--build-log <path>]

Builds the Carafe image unless --skip-build is provided, then runs
`test-data/test-carafe.sh` inside the container with `test-data/` mounted at `/test-data`.

Options:
  --skip-build      Use an existing local image tag instead of rebuilding it
  --push            Forwarded to ./build.sh
  --latest-tag      Forwarded to ./build.sh
  --build-log PATH  Forwarded to ./build.sh
  -h, --help        Show this help message
EOF
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --skip-build)
            skip_build=true
            ;;
        --push|--latest-tag)
            build_args+=("$1")
            ;;
        --build-log)
            if [[ "$#" -lt 2 ]]; then
                echo "--build-log requires a path argument." >&2
                print_usage
                exit 1
            fi
            build_args+=("$1" "$2")
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            print_usage
            exit 1
            ;;
        *)
            if [[ -n "${carafe_version}" ]]; then
                echo "Carafe version already set to ${carafe_version}; unexpected extra argument: $1" >&2
                print_usage
                exit 1
            fi
            carafe_version="$1"
            build_args=("${carafe_version}" "${build_args[@]}")
            ;;
    esac
    shift
done

if [[ -z "${carafe_version}" ]]; then
    print_usage
    exit 1
fi

if [[ "${skip_build}" != true ]]; then
    (
        cd "${repo_root}"
        ./build.sh "${build_args[@]}"
    )
fi

image_tag="mriffle/carafe:${carafe_version}"

docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e CARAFE_VERSION="${carafe_version}" \
    -v "${repo_root}/test-data:/test-data" \
    -w /test-data \
    "${image_tag}" \
    /bin/bash -lc 'bash ./test-carafe.sh'
