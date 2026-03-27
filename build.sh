#!/usr/bin/env bash

set -euo pipefail

# Docker image names
image_names=("mriffle/carafe" "quay.io/protio/carafe")

# Build options
carafe_version=""
push=false
tag_latest=false

print_usage() {
    cat <<'EOF'
Usage: ./build.sh <carafe-version> [--push] [--latest-tag]

Arguments:
  <carafe-version>  Carafe release version, for example: 2.0.0

Options:
  --push            Push images after building
  --latest-tag      Also tag and optionally push the images as :latest
  -h, --help        Show this help message

Examples:
  ./build.sh 2.0.0
  ./build.sh 2.0.0 --push
  ./build.sh 2.0.0 --push --latest-tag
EOF
}

build_images() {
    local build_command=(
        docker
        build
        --build-arg
        "CARAFE_VERSION=${carafe_version}"
    )

    local name
    for name in "${image_names[@]}"; do
        build_command+=(-t "${name}:${carafe_version}")
        if [[ "${tag_latest}" == true ]]; then
            build_command+=(-t "${name}:latest")
        fi
    done

    build_command+=(.)

    echo "Building images for Carafe ${carafe_version}..."
    printf 'Executing: DOCKER_BUILDKIT=1'
    printf ' %q' "${build_command[@]}"
    printf '\n'

    DOCKER_BUILDKIT=1 "${build_command[@]}"
}

push_images() {
    local name

    echo "Pushing images..."
    for name in "${image_names[@]}"; do
        echo "Pushing ${name}:${carafe_version}"
        docker push "${name}:${carafe_version}"

        if [[ "${tag_latest}" == true ]]; then
            echo "Pushing ${name}:latest"
            docker push "${name}:latest"
        fi
    done
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --push)
            push=true
            ;;
        --latest-tag)
            tag_latest=true
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
            ;;
    esac
    shift
done

if [[ -z "${carafe_version}" ]]; then
    echo "A Carafe version is required." >&2
    print_usage
    exit 1
fi

build_images

if [[ "${push}" == true ]]; then
    push_images
fi
