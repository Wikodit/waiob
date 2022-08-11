FROM debian:stable-20220801-slim

RUN \
  echo "deb http://deb.debian.org/debian bullseye main" >> /etc/apt/sources.list && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    wget \
    restic \
    mariadb-client-10.5 \
    postgresql-client-13 \
  && \
  TMP="$(mktemp)" && \
    wget --no-check-certificate -O "${TMP}" 'https://fastdl.mongodb.org/tools/db/mongodb-database-tools-debian11-x86_64-100.5.4.deb' && \
    dpkg -i "${TMP}" && \
    rm "${TMP}" \
  && \
  apt-get remove -y --purge wget && \
  apt-get autoremove -y && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/bin/sh", "-c"]