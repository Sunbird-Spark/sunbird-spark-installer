# Use official YugabyteDB image as the base
# This includes ysqlsh and all YugabyteDB client tools
FROM yugabytedb/yugabyte:latest

# Switch to root user to install additional packages
USER root

# Install kubectl and other dependencies
# YugabyteDB image is based on AlmaLinux 8, which uses dnf
RUN dnf install -y curl jq && \
    curl -LO --proto '=https' --tlsv1.2 "https://dl.k8s.io/release/$(curl -L -s --proto '=https' --tlsv1.2 https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/kubectl && \
    dnf clean all

# Copy the SQL script and shell script into the container
COPY execute_query.sh /usr/local/bin/execute_query.sh

# Make the script executable
RUN chmod +x /usr/local/bin/execute_query.sh

# Drop back to non-root for the runtime -- root was only needed above to
# install kubectl/jq. This image (AlmaLinux-based, per the yugabyte base)
# has no pre-existing non-root user, so create one explicitly.
RUN useradd --uid 1001 --home-dir /home/queryrunner queryrunner
USER 1001

# Execute the script when the container starts
CMD ["/usr/local/bin/execute_query.sh"]