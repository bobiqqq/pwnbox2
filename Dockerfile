FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# essential packages
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    file \
    sudo \
    curl \
    wget \
    strace \
    ltrace \
    python3 \
    python3-pip \
    python3-dev \
    ipython3 \
    gdb \
    socat \
    git \
    netcat-openbsd \
    net-tools \
    iputils-ping \
    libffi-dev \
    libssl-dev \
    build-essential \
    zsh \
    patchelf \
    vim \
    vim-common \
    nano; \
    rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir --upgrade pwntools --break-system-packages
# RUN python3 -m pip install --no-cache-dir --upgrade flare-floss --break-system-packages

RUN git clone --depth=1 https://github.com/hugsy/gef.git /opt/gef && \
    echo "source /opt/gef/gef.py" > /root/.gdbinit
RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /root/.oh-my-zsh && \
    cp /root/.oh-my-zsh/templates/zshrc.zsh-template /root/.zshrc && \
    echo 'DISABLE_AUTO_UPDATE="true"' >> /root/.zshrc
RUN echo "export LC_CTYPE=C.UTF-8" >> /root/.zshenv
RUN curl -qsL 'https://install.pwndbg.re' | sh -s -- -t pwndbg-gdb

WORKDIR /box
