# PostgreSQL 16 + pgvector + Apache AGE
# Built on the official pgvector image; AGE is compiled from source.
#
# AGE release: PG16/v1.5.0-rc0 (Apache only ships -rc0 tags for PG16)
# Source:      https://github.com/apache/age (cloned by setup.sh)
# Archive dir: age-PG16-v1.5.0-rc0/  (matches AGE_DIR_NAME in setup.sh)
#
# age.tar.gz is pre-packaged by setup.sh into setup/postgres/deps/
# (git clone + tar) to avoid Docker-build-time SSL/rate-limit issues
# with GitHub in WSL2 Docker Desktop.
#
# Build:   docker compose -f setup/postgres/docker-compose.yml build
# Run:     docker compose -f setup/postgres/docker-compose.yml up -d

FROM pgvector/pgvector:pg16

ARG AGE_TAG=PG16/v1.5.0-rc0
ARG AGE_DIR=age-PG16-v1.5.0-rc0

# age.tar.gz is pre-downloaded by setup.sh into setup/postgres/deps/
# to avoid Docker-build-time SSL/rate-limit issues with GitHub in WSL2.
COPY deps/age.tar.gz /tmp/age.tar.gz

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential flex bison libreadline-dev zlib1g-dev \
      postgresql-server-dev-16 \
 && tar xzf /tmp/age.tar.gz -C /tmp \
 && cd /tmp/${AGE_DIR} \
 && make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config \
 && make install PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config \
 && apt-get purge -y --auto-remove \
      build-essential flex bison libreadline-dev zlib1g-dev postgresql-server-dev-16 \
 && rm -rf /tmp/age.tar.gz /tmp/${AGE_DIR} /var/lib/apt/lists/*
