# Use the latest Alpine version
FROM alpine:3.18 AS build_stage

# Install necessary build dependencies
RUN apk --update --no-cache add \
        autoconf \
        automake \
        c-ares-dev \
        curl \
        gcc \
        libc-dev \
        libevent-dev \
        libtool \
        make \
        openssl-dev \
        file \
        pkgconf

ARG PGBOUNCER_VERSION

# Download, extract, and build PgBouncer
RUN curl -Lso  "/tmp/pgbouncer.tar.gz" "https://pgbouncer.github.io/downloads/files/${PGBOUNCER_VERSION}/pgbouncer-${PGBOUNCER_VERSION}.tar.gz" && \
        file "/tmp/pgbouncer.tar.gz" && \
        mkdir /tmp/pgbouncer && \
        tar -zxvf /tmp/pgbouncer.tar.gz -C /tmp/pgbouncer --strip-components 1 && \
        cd /tmp/pgbouncer && \
        ./configure --prefix=/usr && \
        make

# Create runtime image
FROM alpine:3.18

# Install runtime dependencies
RUN apk --update --no-cache add \
        libevent \
        openssl \
        ca-certificates \
        c-ares

# Setup directories and user
WORKDIR /etc/pgbouncer
WORKDIR /var/log/pgbouncer
RUN adduser -D postgres && \
        chown -R postgres:root /etc/pgbouncer /var/log/pgbouncer

# Copy build artifacts
USER postgres
COPY --from=build_stage --chown=postgres ["/tmp/pgbouncer", "/opt/pgbouncer"]
COPY --chown=postgres ["entrypoint.sh", "/opt/pgbouncer"]

# Set the entrypoint
WORKDIR /opt/pgbouncer
ENTRYPOINT ["/opt/pgbouncer/entrypoint.sh"]
