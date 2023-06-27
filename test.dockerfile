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
FROM debian:bullseye-slim

ENV PATH="${PATH}:/opt/waiob/bin"
ENV LANG en_US.UTF-8

COPY mysql_pubkey.asc /opt/mysql.gpg

RUN \
  apt-get update && \
  apt-get install -y --no-install-recommends locales && \
  sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
      dpkg-reconfigure --frontend=noninteractive locales && \
      update-locale LANG=en_US.UTF-8 && \
  apt-get install -y --no-install-recommends \
    jq \
    wget \
    gnupg \
    restic \
    ca-certificates \
  && \
  wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.mongodb.org.gpg >/dev/null &&\
  wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null &&\
  apt-key add /opt/mysql.gpg &&\
  echo "deb http://repo.mongodb.org/apt/debian buster/mongodb-org/6.0 main" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list &&\
  echo "deb http://repo.mysql.com/apt/debian/ bullseye mysql-8.0 mysql-tools" | tee /etc/apt/sources.list.d/mysql.list &&\
  echo "deb http://apt.postgresql.org/pub/repos/apt bullseye-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list &&\
  apt-get update &&\
  apt-get install -y --no-install-recommends \
    mongodb-org-shell \
    mongodb-org-tools \
    mysql-community-client \
    mysql-shell \
    postgresql-client-15 \
  && \
  apt-get autoremove -y && \
  apt-get clean

RUN \
  apt-get update &&\
  {\
    echo mysql-cluster-community-server mysql-cluster-community-server/root-pass password root-pwd;\
    echo mysql-cluster-community-server mysql-cluster-community-server/re-root-pass password root-pwd;\
  } | debconf-set-selections &&\
  DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
    mongodb-org \
    mysql-server \
    postgresql-15 \
    unzip &&\
  apt-get autoremove -y && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*


COPY --from=0 /build/restic /usr/local/bin/
COPY bin /opt/waiob/bin
COPY src /opt/waiob/src
COPY test /opt/waiob/test

RUN chmod +x /opt/waiob/bin/*

ENTRYPOINT ["waiob-test"]
CMD []