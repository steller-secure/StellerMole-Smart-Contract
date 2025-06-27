# StarkMole Smart Contracts Development Environment
FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV RUST_VERSION=1.75.0
ENV SCARB_VERSION=2.6.3
ENV SNFOUNDRY_VERSION=0.30.0

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    pkg-config \
    libssl-dev \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain ${RUST_VERSION}
ENV PATH="/root/.cargo/bin:${PATH}"

# Install Scarb
RUN curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh -s -- -v ${SCARB_VERSION}
ENV PATH="/root/.local/bin:${PATH}"

# Install SNFoundry
RUN curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install_starknet_foundry.sh | sh -s -- -v ${SNFOUNDRY_VERSION}
ENV PATH="/root/.local/bin:${PATH}"

# Set work directory
WORKDIR /workspace

# Copy project files
COPY . .

# Make scripts executable
RUN chmod +x scripts/*.sh

# Install dependencies and build
RUN scarb build

# Default command
CMD ["/bin/bash"]
