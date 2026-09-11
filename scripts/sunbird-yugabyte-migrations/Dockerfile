FROM yugabytedb/yugabyte:2025.2.0.0-b131@sha256:3f7607281e9169597948792969a984f98683fa1cc327a920fed250616bf5e8d2

# Copy migration scripts from current directory
COPY . /opt/migrations/sunbird-yugabyte-migrations

# Set proper permissions
RUN chmod -R 755 /opt/migrations/sunbird-yugabyte-migrations

# Set working directory
WORKDIR /opt/migrations/sunbird-yugabyte-migrations

# Run as a non-root user -- these scripts only need network access to
# YugabyteDB, not root on the container.
RUN useradd --uid 1001 --home-dir /opt/migrations/sunbird-yugabyte-migrations migrator \
    && chown -R 1001:1001 /opt/migrations/sunbird-yugabyte-migrations
USER 1001

# Default command (can be overridden)
CMD ["/bin/bash"]
