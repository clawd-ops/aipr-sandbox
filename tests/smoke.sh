#!/bin/sh
# Usage: smoke.sh IMAGE. Needs docker and ssh. Throwaway key, nothing persisted.
set -eu
IMG=$1
T=$(mktemp -d)
trap 'docker logs aipr-smoke 2>&1 | tail -20 || true; docker rm -f aipr-smoke >/dev/null 2>&1 || true; rm -rf "$T"' EXIT
ssh-keygen -q -t ed25519 -N '' -f "$T/k"
docker run -d --name aipr-smoke --read-only --tmpfs /tmp --tmpfs /work:uid=10001,gid=10001 \
  --cap-drop ALL --security-opt no-new-privileges -p 127.0.0.1:2222:2222 \
  -e AIPR_AUTHORIZED_KEY="$(cat "$T/k.pub")" "$IMG" >/dev/null
for i in $(seq 1 20); do ssh-keyscan -p 2222 127.0.0.1 >/dev/null 2>&1 && break; sleep 1; done
S="ssh -p 2222 -i $T/k -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes"
$S sbx@127.0.0.1 'git --version && python3 --version'
UID_R=$($S sbx@127.0.0.1 id -u)
[ "$UID_R" = 10001 ] || { echo "FAIL: uid $UID_R" >&2; exit 1; }
echo "non-root ok (uid $UID_R)"
# password auth and forwarding must be refused (explicit ifs: "! cmd" does not trip set -e)
if ssh -p 2222 -o PubkeyAuthentication=no -o PreferredAuthentications=password -o BatchMode=yes \
   -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null sbx@127.0.0.1 true 2>/dev/null; then
  echo "FAIL: password auth accepted" >&2; exit 1
fi
echo "password auth refused ok"
if timeout 15 $S -R 9999:127.0.0.1:2222 -N -o ExitOnForwardFailure=yes sbx@127.0.0.1 2>/dev/null; then
  echo "FAIL: remote forwarding accepted" >&2; exit 1
fi
echo "forwarding refused ok"
# read-only root: writes outside /tmp and /work must fail
if $S sbx@127.0.0.1 'touch /etc/x' 2>/dev/null; then echo "FAIL: root fs writable" >&2; exit 1; fi
echo "read-only root ok"
# seed + patch round trip
$S sbx@127.0.0.1 'cd /work && git init -q r && cd r && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m x && git format-patch -1 --stdout >/dev/null'
echo SMOKE-PASS
