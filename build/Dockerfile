# Use the latest Alpine version
FROM --platform=${TARGETPLATFORM} alpine:3.19 AS build_stage

# Install necessary build dependencies
RUN apk --update --no-cache add \
        autoconf \
        automake \
        libtool \
        pkgconfig \
        c-ares-dev \
        curl \
        gcc \
        libc-dev \
        libevent-dev \
        openssl-dev \
        file \
        git \
        pandoc \
        make && \
    make --version
ARG PGBOUNCER_VERSION

# Clone the specific branch, initialize submodules, and run autogen.sh
RUN git clone --branch pgbouncer-1.20-no-894 https://github.com/JelteF/pgbouncer.git /tmp/pgbouncer && \
    cd /tmp/pgbouncer && \
    git submodule init && \
    git submodule update && \
    chmod +x ./autogen.sh && \
    ./autogen.sh

# Extract and build PgBouncer
RUN cd /tmp/pgbouncer && \
    ./configure --prefix=/usr && \
    make

# Create runtime image
FROM --platform=${TARGETPLATFORM} alpine:3.19

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
