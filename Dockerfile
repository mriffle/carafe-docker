# Use Ubuntu as the base image
FROM ubuntu:20.04 AS builder

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/conda/bin:${PATH}" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Set Carafe version as a build argument
ARG CARAFE_VERSION=0.0.1

# Install necessary packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    git \
    unzip \
    openjdk-11-jdk \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh \
    && bash miniconda.sh -b -p /opt/conda \
    && rm miniconda.sh \
    && ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh \
    && echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc \
    && echo "conda activate carafe" >> ~/.bashrc

# Add GitHub to known hosts
RUN mkdir -p /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts

# Clone AlphaPeptDeep-DIA repository
RUN --mount=type=ssh git clone --depth 1 git@github.com:wenbostar/alphapeptdeep_dia.git

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
FROM ubuntu:20.04

# Copy necessary files from builder stage
COPY --from=builder /opt/conda /opt/conda
COPY --from=builder /opt/carafe /opt/carafe
COPY --from=builder /root/.bashrc /root/.bashrc

# Set environment variables
ENV PATH="/opt/conda/bin:${PATH}" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Set environment variables for HuggingFace
ENV HF_HOME=/tmp/huggingface

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-11-jre-headless \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir /tmp/huggingface && chmod 777 /tmp/huggingface \
    && mkdir /peptdeep && chmod 777 /peptdeep

# Set the working directory
WORKDIR /app

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
