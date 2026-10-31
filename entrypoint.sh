#!/bin/sh
# Starts sshd as the non-root sbx user. Writable paths: /tmp and /work (emptyDir).
# Authorized key: AIPR_AUTHORIZED_KEY (env) or file AIPR_AUTHORIZED_KEY_FILE.
# Optional host key: file AIPR_HOST_KEY_FILE (otherwise generated at start).
set -eu
umask 077
S=/tmp/sshd
mkdir -p "$S"
chmod 700 "$S"
if [ -n "${AIPR_AUTHORIZED_KEY_FILE:-}" ]; then
  cp "$AIPR_AUTHORIZED_KEY_FILE" "$S/authorized_keys"
elif [ -n "${AIPR_AUTHORIZED_KEY:-}" ]; then
  printf '%s\n' "$AIPR_AUTHORIZED_KEY" > "$S/authorized_keys"
else
  echo "entrypoint: set AIPR_AUTHORIZED_KEY or AIPR_AUTHORIZED_KEY_FILE" >&2
  exit 64
fi
chmod 600 "$S/authorized_keys"
if [ -n "${AIPR_HOST_KEY_FILE:-}" ]; then
  cp "$AIPR_HOST_KEY_FILE" "$S/ssh_host_ed25519_key"
  chmod 600 "$S/ssh_host_ed25519_key"
else
  ssh-keygen -q -t ed25519 -N '' -f "$S/ssh_host_ed25519_key"
fi
ssh-keygen -y -f "$S/ssh_host_ed25519_key" > "$S/ssh_host_ed25519_key.pub"
echo "host-key-fingerprint: $(ssh-keygen -lf "$S/ssh_host_ed25519_key.pub")"
exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config.aipr
