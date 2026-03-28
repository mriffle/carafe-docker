#!/usr/bin/env bash

set -euo pipefail

carafe_python_root="${CARAFE_RUNTIME_HOME:-/opt/carafe-home}/.carafe/.venv/bin"
export PATH="${carafe_python_root}:${PATH}"

if [[ "${JAVA_TOOL_OPTIONS:-}" != *"-Duser.home="* ]]; then
    export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:+${JAVA_TOOL_OPTIONS} }-Duser.home=${CARAFE_RUNTIME_HOME:-/opt/carafe-home}"
fi

exec "$@"
