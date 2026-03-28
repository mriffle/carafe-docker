#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
carafe_version=""
image_tag=""
build_args=()

print_usage() {
    cat <<'EOF'
Usage: ./test/test_carafe_image.sh <carafe-version> [--push] [--latest-tag] [--build-log <path>]

Builds the Carafe image and runs a basic in-container smoke test that:
- verifies the image uses the new Python bootstrap path instead of Conda
- runs the packaged Carafe JAR with -h and checks for help output

Any `--push`, `--latest-tag`, or `--build-log <path>` options are forwarded to `./build.sh`.
EOF
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
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

(
    cd "${repo_root}"
    ./build.sh "${build_args[@]}"
)

image_tag="mriffle/carafe:${carafe_version}"

docker run --rm --entrypoint /bin/bash --user 12345:12345 "${image_tag}" -lc '
    set -euo pipefail

    test ! -d /opt/conda
    command -v python >/dev/null 2>&1
    command -v python3 >/dev/null 2>&1
    test -z "${CONDA_DEFAULT_ENV:-}"
    test -x /opt/carafe-home/.carafe/.venv/bin/python3

    resolved_python="$(readlink -f /opt/carafe-home/.carafe/.venv/bin/python3)"
    case "${resolved_python}" in
        /opt/carafe-home/*) ;;
        *)
            echo "Expected Carafe venv python to resolve inside /opt/carafe-home, got: ${resolved_python}" >&2
            exit 1
            ;;
    esac

    python -c "import sys, torch; print(sys.executable); print(torch.__version__)" > /tmp/python-check.txt
    grep -q "^/opt/carafe-home/.carafe/.venv/bin/python" /tmp/python-check.txt

    test "${JAVA_TOOL_OPTIONS:-}" = "-Duser.home=/opt/carafe-home"
    java -XshowSettings:properties -version > /tmp/java-settings.txt 2>&1
    grep -q "user.home = /opt/carafe-home" /tmp/java-settings.txt

    jar_path="/opt/carafe/carafe-'"${carafe_version}"'/carafe-'"${carafe_version}"'.jar"
    if [[ ! -f "${jar_path}" ]]; then
        echo "Expected Carafe JAR was not found at ${jar_path}" >&2
        exit 1
    fi

    java -Djava.aws.headless=true -jar "${jar_path}" -h > /tmp/carafe-help.txt 2>&1

    grep -qi "usage:" /tmp/carafe-help.txt
    grep -q -- "-db" /tmp/carafe-help.txt
'
