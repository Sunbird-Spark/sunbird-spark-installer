FROM yugabytedb/yugabyte:latest

# Copy migration scripts from current directory
COPY . /opt/migrations/sunbird-yugabyte-migrations

# Set proper permissions
RUN chmod -R 755 /opt/migrations/sunbird-yugabyte-migrations

# Set working directory
WORKDIR /opt/migrations/sunbird-yugabyte-migrations

# Default command (can be overridden)
CMD ["/bin/bash"]
