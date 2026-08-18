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
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && apt-get install -y postgresql-client-15 && \
    rm -rf /var/lib/apt/lists/*

# Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Google Cloud CLI
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update && apt-get install -y google-cloud-cli && \
    rm -rf /var/lib/apt/lists/*

# AWS CLI
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# Python cassandra-driver for YCQL backup
RUN pip3 install cassandra-driver

COPY ./backup.sh /backup.sh
COPY ./ycql_backup.py /ycql_backup.py

RUN chmod +x /backup.sh

ENTRYPOINT ["bash", "/backup.sh"]
