#!/bin/bash

# Docker image names
image_names=("mriffle/carafe" "quay.io/protio/carafe")

# Versions
versions=("latest" "0.0.1")

# SSH key path (default to ~/.ssh/id_rsa)
SSH_KEY_PATH="$HOME/.ssh/id_rsa"

# Function to print usage
print_usage() {
    echo "Usage: $0 [--push] [--ssh-key PATH]"
    echo "  --push              Push images after building"
    echo "  --ssh-key PATH      Specify the SSH key path (default: ~/.ssh/id_rsa)"
}

# Function to build images
build_images() {
    build_command="DOCKER_BUILDKIT=1 sudo docker build --ssh default=$SSH_KEY_PATH"
    
    # Add tags
    for name in "${image_names[@]}"; do
        for version in "${versions[@]}"; do
            build_command+=" -t ${name}:${version}"
        done
    done
    
    build_command+=" ."
    
    echo "Building images..."
    echo "Executing: $build_command"
    eval $build_command
}

# Function to push images
push_images() {
    echo "Pushing images..."
    for name in "${image_names[@]}"; do
        for version in "${versions[@]}"; do
            echo "Pushing ${name}:${version}"
            sudo docker push "${name}:${version}"
        done
    done
}

# Main script
push=false

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --push) push=true ;;
        --ssh-key) SSH_KEY_PATH="$2"; shift ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown parameter: $1"; print_usage; exit 1 ;;
    esac
    shift
done

# Build images
build_images

# Push images if --push is specified
if $push; then
    push_images
fi
