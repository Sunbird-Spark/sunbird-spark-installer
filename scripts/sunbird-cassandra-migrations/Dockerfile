FROM cassandra:5.0.9-bookworm@sha256:7ee3eda0f01d80fa4cf93cefb2b1b993bd356a98b7200827d2af5113475534d1

COPY . /opt/migrations/sunbird-cassandra-migrations

RUN chmod -R 755 /opt/migrations/sunbird-cassandra-migrations \
    && chown -R 999:999 /opt/migrations/sunbird-cassandra-migrations

WORKDIR /opt/migrations/sunbird-cassandra-migrations

ENV HOME=/opt/migrations/sunbird-cassandra-migrations

USER 999

ENTRYPOINT []
CMD ["/bin/bash"]
