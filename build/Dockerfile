# Use Chainguard FIPS-compatible glibc base image for build stage
FROM --platform=${TARGETPLATFORM} cgr.dev/mattermost.com/glibc-openssl-fips:14-dev AS build_stage

# Switch to root for package installation
USER root

# Install necessary build dependencies for FIPS-compatible build
RUN apk --update --no-cache add \
        autoconf \
        automake \
        c-ares-dev \
        curl \
        gcc \
        glibc-dev \
        libevent-dev \
        libtool \
        make \
        openssl-dev \
        file \
        pkgconf

ARG PGBOUNCER_VERSION

# Download and extract PgBouncer
RUN curl -Lso  "/tmp/pgbouncer.tar.gz" "https://pgbouncer.github.io/downloads/files/${PGBOUNCER_VERSION}/pgbouncer-${PGBOUNCER_VERSION}.tar.gz" && \
        file "/tmp/pgbouncer.tar.gz" && \
        mkdir /tmp/pgbouncer && \
        tar -zxvf /tmp/pgbouncer.tar.gz -C /tmp/pgbouncer --strip-components 1

# Copy FIPS-compatible replacement files
COPY build/postgres_compat_fips.h /tmp/pgbouncer/include/common/postgres_compat.h
WORKDIR /tmp/pgbouncer

# Configure and build PgBouncer with OpenSSL support for FIPS compatibility
RUN ./configure --prefix=/usr --with-openssl --enable-debug && \
        make

# Create directory structure and setup postgres user in build stage
RUN adduser -D postgres && \
    mkdir -p /etc/pgbouncer /var/log/pgbouncer /opt/pgbouncer && \
    chown -R postgres:postgres /etc/pgbouncer /var/log/pgbouncer /opt/pgbouncer

# Copy the built pgbouncer and entrypoint to the final location
COPY build/entrypoint.sh /opt/pgbouncer/entrypoint.sh
RUN chown postgres:postgres /opt/pgbouncer/entrypoint.sh && \
    chmod +x /opt/pgbouncer/entrypoint.sh

# Create runtime image using Chainguard FIPS-enabled glibc runtime (distroless)
FROM --platform=${TARGETPLATFORM} cgr.dev/mattermost.com/glibc-openssl-fips:14

# Copy everything from build stage: user, directories, built binaries
COPY --from=build_stage /etc/passwd /etc/passwd
COPY --from=build_stage /etc/group /etc/group
COPY --from=build_stage /etc/pgbouncer /etc/pgbouncer
COPY --from=build_stage /var/log/pgbouncer /var/log/pgbouncer
COPY --from=build_stage /opt/pgbouncer /opt/pgbouncer
COPY --from=build_stage /tmp/pgbouncer /opt/pgbouncer/bin

# Switch to postgres user and set working directory
USER postgres
WORKDIR /opt/pgbouncer

# Set the entrypoint
ENTRYPOINT ["/opt/pgbouncer/entrypoint.sh"]
