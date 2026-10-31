# syntax=docker/dockerfile:1
FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

ARG UID=10001
ARG GID=10001

RUN apk add --no-cache openssh-server git python3 coreutils bash tar \
 && addgroup -g "${GID}" sbx \
 && adduser -D -u "${UID}" -G sbx -h /work -s /bin/bash sbx \
 && sed -i 's/^sbx:!:/sbx:*:/' /etc/shadow

COPY sshd_config /etc/ssh/sshd_config.aipr
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

USER 10001:10001
WORKDIR /work
EXPOSE 2222
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
