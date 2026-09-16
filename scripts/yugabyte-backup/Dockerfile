# syntax=docker/dockerfile:1
# ^ pins the Dockerfile frontend so `ADD --checksum` below (needs 1.4+) works
# on any builder, not just whatever buildx happens to default to.
FROM --platform=linux/amd64 ubuntu:22.04@sha256:829f6df217bcbae2b371026e81711d1a787c61b2967ad09d015063663ebafbf7

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
RUN curl -fsSL --proto '=https' --tlsv1.2 -o /tmp/postgresql.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
    gpg --dearmor -o /usr/share/keyrings/postgresql.gpg /tmp/postgresql.asc && rm -f /tmp/postgresql.asc && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && apt-get install -y postgresql-client-15 && \
    rm -rf /var/lib/apt/lists/*

# Azure CLI -- step-by-step apt install (signed key + repo, same
# one-line sources.list format as the postgres/gcp blocks above)
# instead of piping the aka.ms install script straight into bash.
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL --proto '=https' --tlsv1.2 -o /tmp/microsoft.asc https://packages.microsoft.com/keys/microsoft.asc && \
    gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg /tmp/microsoft.asc && rm -f /tmp/microsoft.asc && \
    chmod go+r /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/azure-cli.list && \
    apt-get update && apt-get install -y --no-install-recommends azure-cli && \
    rm -rf /var/lib/apt/lists/*

# Google Cloud CLI
RUN curl -fsSL --proto '=https' --tlsv1.2 -o /tmp/cloud.google.gpg.asc https://packages.cloud.google.com/apt/doc/apt-key.gpg && \
    gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg /tmp/cloud.google.gpg.asc && rm -f /tmp/cloud.google.gpg.asc && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update && apt-get install -y google-cloud-cli && \
    rm -rf /var/lib/apt/lists/*

# AWS CLI -- ADD instead of curl (docker:S7026), version-pinned URL + checksum so
# the build is reproducible and a corrupted/tampered download fails it.
# To upgrade: pick a version from https://github.com/aws/aws-cli/tags, download
# https://awscli.amazonaws.com/awscli-exe-linux-x86_64-<ver>.zip, `shasum -a 256` it,
# and update both AWSCLI_VERSION and the checksum together.
ARG AWSCLI_VERSION=2.36.43
ADD --checksum=sha256:ef606eb55f9a93ac404cc4a6869c0a791c234b898d93ec6af3bba8c491b391e9 \
    https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip /tmp/awscliv2.zip
RUN unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# Python cassandra-driver for YCQL backup, then create the runtime user.
# "backup" collides with Ubuntu's own standard system account
# (backup:x:34:34:backup:/var/backups:/usr/sbin/nologin, from base-passwd) --
# useradd fails with exit 9 either way, whether or not --uid is given, since
# the name itself is taken. Also skip an explicit --uid: one of the
# postgres/azure/gcp/aws CLI installs above already claims uid 1001 here.
# Merged into one RUN to avoid an extra layer.
COPY ./requirements.txt /requirements.txt
RUN pip3 install --require-hashes --only-binary :all: -r /requirements.txt && \
    useradd --create-home --home-dir /home/ycqlbackup ycqlbackup

# Owned by root, not the runtime user (docker:S6504) -- these scripts
# shouldn't be writable by the process that runs them. World-readable is
# enough for the runtime user to read/execute; chmod +x below covers execute.
COPY ./backup.sh /backup.sh
COPY ./ycql_backup.py /ycql_backup.py

RUN chmod +x /backup.sh /ycql_backup.py

USER ycqlbackup

ENTRYPOINT ["bash", "/backup.sh"]
