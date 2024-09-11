#!/usr/bin/env bash

set -e

# Activate the Conda environment
source /opt/conda/etc/profile.d/conda.sh
conda activate carafe

exec "$@"
