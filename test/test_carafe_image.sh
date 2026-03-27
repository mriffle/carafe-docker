#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
carafe_version="${1:-}"
created_pretrained_models_archive=false
image_tag=""

print_usage() {
    cat <<'EOF'
Usage: ./test/test_carafe_image.sh <carafe-version>

Builds the Carafe image and runs a basic in-container smoke test that:
- verifies the Conda environment is activated by the entrypoint
- verifies the pretrained model archive is present in the image
- runs the packaged Carafe JAR with -h and checks for help output
EOF
}

cleanup() {
    if [[ "${created_pretrained_models_archive}" == true ]]; then
        rm -f "${repo_root}/pretrained_models.zip"
    fi
}

trap cleanup EXIT

if [[ -z "${carafe_version}" ]]; then
    print_usage
    exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
    echo "The 'zip' command is required to create a test pretrained_models.zip archive." >&2
    exit 1
fi

if [[ ! -f "${repo_root}/pretrained_models.zip" ]]; then
    tmp_dir="$(mktemp -d)"
    printf 'Placeholder archive created by CI smoke test.\n' > "${tmp_dir}/README.txt"
    (
        cd "${tmp_dir}"
        zip -q "${repo_root}/pretrained_models.zip" README.txt
    )
    rm -rf "${tmp_dir}"
    created_pretrained_models_archive=true
fi

(
    cd "${repo_root}"
    ./build.sh "${carafe_version}"
)

image_tag="mriffle/carafe:${carafe_version}"

docker run --rm "${image_tag}" /bin/bash -lc '
    set -euo pipefail

    test "${CONDA_DEFAULT_ENV:-}" = "carafe"
    test -f /data/peptdeep/pretrained_models/pretrained_models.zip

    jar_path="/opt/carafe/carafe-'"${carafe_version}"'/carafe-'"${carafe_version}"'.jar"
    if [[ ! -f "${jar_path}" ]]; then
        echo "Expected Carafe JAR was not found at ${jar_path}" >&2
        exit 1
    fi

    java -Djava.aws.headless=true -jar "${jar_path}" -h > /tmp/carafe-help.txt 2>&1

    grep -qi "usage:" /tmp/carafe-help.txt
    grep -q -- "-db" /tmp/carafe-help.txt
'
