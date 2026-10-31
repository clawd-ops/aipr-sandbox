#!/bin/sh
# Usage: smoke.sh IMAGE. Needs docker and ssh. Throwaway key, nothing persisted.
# Runs the image with the same restrictions the Kubernetes pod uses.
set -eu
IMG=$1
T=$(mktemp -d)
N=aipr-smoke
trap 'docker logs $N 2>&1 | tail -20 || true; docker rm -f $N >/dev/null 2>&1 || true; rm -rf "$T"' EXIT
fail() { echo "SMOKE-FAIL: $*" >&2; exit 1; }
ssh-keygen -q -t ed25519 -N '' -f "$T/k"
docker run -d --name $N --user 10001:10001 --read-only --tmpfs /tmp:uid=10001,gid=10001 \
  --tmpfs /work:uid=10001,gid=10001 --cap-drop ALL --security-opt no-new-privileges \
  -p 127.0.0.1:2222:2222 -e AIPR_AUTHORIZED_KEY="$(cat "$T/k.pub")" "$IMG" >/dev/null
up=0
for i in $(seq 1 30); do ssh-keyscan -p 2222 127.0.0.1 >/dev/null 2>&1 && { up=1; break; }; sleep 1; done
[ "$up" = 1 ] || fail "sshd did not come up"
O="-p 2222 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR"
S="ssh $O -i $T/k sbx@127.0.0.1"
$S 'git --version && python3 --version && sort --version | head -1' || fail "tools missing"
[ "$($S id -u)" = 10001 ] || fail "not uid 10001"
echo "non-root ok"
# root fs read-only, /tmp and /work writable
if $S 'touch /etc/x' 2>/dev/null; then fail "root fs writable"; fi
$S 'touch /tmp/x /work/x' || fail "/tmp or /work not writable"
# password auth refused
if ssh $O -o PubkeyAuthentication=no -o PreferredAuthentications=password sbx@127.0.0.1 true 2>/dev/null; then fail "password auth allowed"; fi
# wrong key refused
ssh-keygen -q -t ed25519 -N '' -f "$T/bad"
if ssh $O -i "$T/bad" sbx@127.0.0.1 true 2>/dev/null; then fail "wrong key accepted"; fi
# forwarding refused (stdio forward and local forward)
if ssh $O -i "$T/k" -W 127.0.0.1:2222 sbx@127.0.0.1 </dev/null 2>/dev/null; then fail "forwarding allowed"; fi
docker exec $N /usr/sbin/sshd -T -f /etc/ssh/sshd_config.aipr 2>/dev/null | grep -qx 'allowtcpforwarding no' || fail "sshd config not effective"
# seed a repo from the host over ssh, commit in the sandbox, pull the patch, apply it on the host
mkdir "$T/src" && cd "$T/src"
git init -q . && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
echo one > f.txt && git add f.txt && git -c user.name=t -c user.email=t@t commit -q -m seed
git bundle create "$T/seed.bundle" HEAD >/dev/null 2>&1
$S 'cat > /work/seed.bundle' < "$T/seed.bundle"
$S 'cd /work && git clone -q seed.bundle r && cd r && echo two >> f.txt && git -c user.name=t -c user.email=t@t commit -q -am change'
$S 'cd /work/r && git diff HEAD~1 HEAD' > "$T/out.patch"
[ -s "$T/out.patch" ] || fail "empty patch"
git apply "$T/out.patch" || fail "patch does not apply"
[ "$(cat f.txt)" = "one
two" ] || fail "patched content wrong"
echo SMOKE-PASS
