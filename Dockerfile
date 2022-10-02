FROM golang:1.19

ARG RESTIC_COMMIT="f0bb4f8708b1e09e09897463d70b5c89b20eec01"

ENV PATH="$PATH:/opt/waiob/bin"

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

ENV PATH="$PATH:/opt/waiob/bin"
ENV LANG en_US.UTF-8

RUN \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    jq \
    wget \
    gnupg \
    restic \
    ca-certificates \
    postgresql-client-13 \
  && \
  wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add - &&\
  echo "deb http://repo.mongodb.org/apt/debian buster/mongodb-org/6.0 main" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list &&\
  echo "deb http://deb.debian.org/debian bullseye main" >> /etc/apt/sources.list && \
  echo "deb http://repo.mysql.com/apt/debian/ bullseye mysql-8.0 mysql-tools" | tee /etc/apt/sources.list.d/mysql.list &&\
  apt-key adv --keyserver pgp.mit.edu --recv-keys 3A79BD29 &&\
  apt-get update &&\
  apt-get install -y --no-install-recommends \
    mongodb-org-shell \
    mongodb-org-tools \
    mysql-community-client \
    mysql-shell \
  && \
  apt-get autoremove -y && \
  apt-get clean

COPY --from=0 /build/restic /usr/local/bin/
COPY bin /opt/waiob/bin
RUN chmod -R +x /opt/waiob/bin
COPY lib /opt/waiob/lib
RUN chmod -R +x /opt/waiob/lib
COPY src /opt/waiob/src
RUN chmod -R +x /opt/waiob/src
COPY waiob.sh /opt/waiob/
RUN chmod +x /opt/waiob/waiob.sh

ENTRYPOINT [ "waiob" ]
CMD ["--help"]
