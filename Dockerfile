# Set Carafe version as a build argument
ARG CARAFE_VERSION=2.0.0-beta

# Use Ubuntu as the base image
FROM ubuntu:24.04 AS builder

# Set Carafe version as a build argument
ARG CARAFE_VERSION

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/conda/bin:${PATH}" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Install necessary packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    git \
    unzip \
    openjdk-21-jdk \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh \
    && bash miniconda.sh -b -p /opt/conda \
    && rm miniconda.sh \
    && ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh \
    && echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc \
    && echo "conda activate carafe" >> ~/.bashrc \
    && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main \
    && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# Clone AlphaPeptDeep-DIA repository
RUN git clone https://github.com/wenbostar/alphapeptdeep_dia

# Create and activate conda environment
RUN cd alphapeptdeep_dia \
    && conda env create -f conda_environment.yml \
    && conda clean -afy

# Install AlphaPeptDeep-DIA
SHELL ["/bin/bash", "-c"]
RUN source /opt/conda/etc/profile.d/conda.sh \
    && conda activate carafe \
    && cd alphapeptdeep_dia \
    && pip install . \
    && conda clean -afy \
    && find /opt/conda -follow -type f -name '*.a' -delete \
    && find /opt/conda -follow -type f -name '*.js.map' -delete

# Copy and install Carafe from local file
COPY carafe-${CARAFE_VERSION}.zip /tmp/
RUN unzip /tmp/carafe-${CARAFE_VERSION}.zip -d /opt/carafe \
    && rm /tmp/carafe-${CARAFE_VERSION}.zip

# Start a new stage for the final image
FROM ubuntu:24.04

ARG CARAFE_VERSION
ENV CARAFE_VERSION=${CARAFE_VERSION}

# Copy necessary files from builder stage
COPY --from=builder /opt/conda /opt/conda
COPY --from=builder /opt/carafe /opt/carafe
COPY --from=builder /root/.bashrc /root/.bashrc

# Copy other necessary items from local disk
COPY entrypoint.sh /usr/local/bin/
COPY pretrained_models.zip /data/peptdeep/pretrained_models/

# Set environment variables
ENV PATH="/opt/conda/bin:${PATH}" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Set environment variables for HuggingFace
ENV HF_HOME=/tmp/huggingface

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jre-headless \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir /tmp/huggingface && chmod 777 /tmp/huggingface \
    && chmod +x /usr/local/bin/entrypoint.sh

# Set the working directory
WORKDIR /app

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
