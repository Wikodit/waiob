FROM golang:1.19

ARG RESTIC_COMMIT="f0bb4f8708b1e09e09897463d70b5c89b20eec01"

WORKDIR /build

RUN \
  git init -b main && \
  git remote add origin https://github.com/restic/restic && \
  git fetch --depth 1 origin "$RESTIC_COMMIT" && \
  git reset --hard FETCH_HEAD && \
  unset GOPATH && \
  go run build.go

#---
FROM debian:stable-20220801-slim

ENV PATH="${PATH}:/opt/waiob/bin"

RUN \
  echo "deb http://deb.debian.org/debian bullseye main" >> /etc/apt/sources.list && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    jq \
    wget \
    gnupg \
    restic \
    ca-certificates \
    mariadb-client-10.5 \
    postgresql-client-13 \
  && \
  wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add - &&\
  echo "deb http://repo.mongodb.org/apt/debian buster/mongodb-org/6.0 main" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list &&\
  apt-get update &&\
  apt-get install -y --no-install-recommends mongodb-org-shell mongodb-org-tools && \
  apt-get autoremove -y && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Mongo
RUN \
  wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add - &&\
  echo "deb http://repo.mongodb.org/apt/debian buster/mongodb-org/6.0 main" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list &&\
  apt-get update &&\
  apt-get install -y --no-install-recommends mongodb-org &&\
  apt-get autoremove -y && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

COPY --from=0 /build/restic /usr/local/bin/
COPY . /opt/waiob

ENTRYPOINT ["waiob-test"]
CMD []