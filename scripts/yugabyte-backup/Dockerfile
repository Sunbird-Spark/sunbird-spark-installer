FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    bash \
    bzip2 \
    ca-certificates \
    gnupg \
    lsb-release \
    python3 \
    python3-pip \
    gzip \
    tar \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# PostgreSQL 15 client (Ubuntu 22.04's default postgresql-client package is v14,
# but pg_dump refuses to dump from a server reporting a newer major version —
# YugabyteDB reports itself as PG 15-compatible, so v14's pg_dump aborts with
# "server version mismatch" on every database).
RUN curl -fsSL --proto '=https' --tlsv1.2 https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && apt-get install -y postgresql-client-15 && \
    rm -rf /var/lib/apt/lists/*

# Azure CLI -- step-by-step apt install (signed key + repo, same
# one-line sources.list format as the postgres/gcp blocks above)
# instead of piping the aka.ms install script straight into bash.
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL --proto '=https' --tlsv1.2 https://packages.microsoft.com/keys/microsoft.asc | \
      gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg && \
    chmod go+r /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/azure-cli.list && \
    apt-get update && apt-get install -y azure-cli && \
    rm -rf /var/lib/apt/lists/*

# Google Cloud CLI
RUN curl -fsSL --proto '=https' --tlsv1.2 https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update && apt-get install -y google-cloud-cli && \
    rm -rf /var/lib/apt/lists/*

# AWS CLI
RUN curl -fsSL --proto '=https' --tlsv1.2 "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# Python cassandra-driver for YCQL backup
RUN pip3 install --only-binary :all: cassandra-driver==3.30.1

RUN useradd --uid 1001 --home-dir /home/backup backup

COPY --chown=1001:1001 ./backup.sh /backup.sh
COPY --chown=1001:1001 ./ycql_backup.py /ycql_backup.py

RUN chmod +x /backup.sh

USER 1001

ENTRYPOINT ["bash", "/backup.sh"]
