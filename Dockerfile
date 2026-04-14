# Set Carafe version as a build argument
ARG CARAFE_VERSION

# Use Ubuntu as the base image
FROM ubuntu:24.04 AS builder

# Set Carafe version as a build argument
ARG CARAFE_VERSION

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Install necessary packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Download and install Carafe from the matching GitHub release
RUN test -n "${CARAFE_VERSION}" || (echo "CARAFE_VERSION build arg is required" >&2; exit 1) \
    && wget -O /tmp/carafe.zip "https://github.com/Noble-Lab/Carafe/releases/download/v${CARAFE_VERSION}/carafe-${CARAFE_VERSION}.zip" \
    && unzip /tmp/carafe.zip -d /opt/carafe \
    && rm /tmp/carafe.zip

# Start a new stage for the final image
FROM ubuntu:24.04

ARG CARAFE_VERSION
ENV CARAFE_VERSION=${CARAFE_VERSION} \
    CARAFE_RUNTIME_HOME=/opt/carafe-home \
    CARAFE_UV_PYTHON_INSTALL_DIR=/opt/carafe-home/uv-python

# Copy necessary files from builder stage
COPY --from=builder /opt/carafe /opt/carafe

# Copy other necessary items from local disk
COPY entrypoint.sh /usr/local/bin/

# Set environment variables
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/tmp \
    HF_HOME=/tmp/huggingface \
    PATH="/opt/carafe-home/.carafe/.venv/bin:${PATH}" \
    JAVA_TOOL_OPTIONS="-Duser.home=/opt/carafe-home"

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    openjdk-21-jre-headless \
    python3 \
    python-is-python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p "${CARAFE_RUNTIME_HOME}" "${CARAFE_UV_PYTHON_INSTALL_DIR}" \
    && chmod +x /usr/local/bin/entrypoint.sh \
    && cd "/opt/carafe/carafe-${CARAFE_VERSION}" \
    && HOME="${CARAFE_RUNTIME_HOME}" UV_PYTHON_INSTALL_DIR="${CARAFE_UV_PYTHON_INSTALL_DIR}" \
        java -cp "carafe-${CARAFE_VERSION}.jar" main.java.util.PyInstaller "${CARAFE_RUNTIME_HOME}/.carafe" \
    && chmod -R a+rX "${CARAFE_RUNTIME_HOME}" \
    && chmod -R a+rX /opt/carafe \
    && find /opt/carafe -type f -path '*/bin/*' -exec chmod a+x {} +

# Pre-download peptdeep pretrained models at build time to /data/peptdeep.
# Carafe's models.py checks /data/peptdeep/pretrained_models/ as a fallback
# location regardless of HOME, and /data survives Apptainer's /tmp overlay.
RUN mkdir -p /data \
    && HOME=/data python -c "import peptdeep.pretrained_models" \
    && chmod -R a+rX /data/peptdeep

# Set the working directory
WORKDIR /app

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
