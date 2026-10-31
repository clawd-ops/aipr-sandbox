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
$S sbx@127.0.0.1 'git --version && python3 --version && sort --version | head -1'
UID_R=$($S sbx@127.0.0.1 id -u)
[ "$UID_R" = 10001 ] || { echo "FAIL: uid $UID_R" >&2; exit 1; }
echo "non-root ok (uid $UID_R)"
# Forwarding probes. ExitOnForwardFailure plus a bounded timeout: a live session (timeout, rc 124) or
# rc 0 means forwarding WORKED and is a FAIL. Only a prompt ssh failure carrying an explicit
# refusal message counts as a pass. (Explicit ifs: "! cmd" does not trip set -e.)
refused() { # name, then the probe command
  n=$1; shift
  rc=0; "$@" >"$T/probe.out" 2>"$T/probe.err" </dev/null || rc=$?
  if [ "$rc" = 0 ] || [ "$rc" = 124 ]; then echo "FAIL: $n forwarding worked (rc $rc)" >&2; exit 1; fi
  grep -Eqi 'forwarding failed|administratively prohibited|forwarding disabled|open failed' "$T/probe.err" \
    || { echo "FAIL: $n exited rc $rc without an explicit refusal" >&2; cat "$T/probe.err" >&2; exit 1; }
  echo "$n forwarding refused ok (rc $rc)"
}
FO="-o ExitOnForwardFailure=yes -o LogLevel=ERROR"
refused "remote tcp" timeout 15 $S $FO -R 9999:127.0.0.1:2222 -N sbx@127.0.0.1
refused "remote unix" timeout 15 $S $FO -R /tmp/probe.sock:127.0.0.1:2222 -N sbx@127.0.0.1
refused "stdio" timeout 15 $S $FO -W 127.0.0.1:2222 sbx@127.0.0.1
# read-only root: Docker setting must be on, and even root inside the container cannot write /etc
[ "$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' aipr-smoke)" = true ] \
  || { echo "FAIL: container not started read-only" >&2; exit 1; }
if docker exec -u 0 aipr-smoke touch /etc/x 2>/dev/null; then echo "FAIL: root fs writable" >&2; exit 1; fi
echo "read-only root ok"
# writable /tmp and /work
$S sbx@127.0.0.1 'touch /tmp/x /work/x'
echo "writable mounts ok"
# wrong key refused
ssh-keygen -q -t ed25519 -N '' -f "$T/bad"
if ssh -p 2222 -i "$T/bad" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no \
   -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR sbx@127.0.0.1 true 2>/dev/null; then
  echo "FAIL: wrong key accepted" >&2; exit 1
fi
echo "wrong key refused ok"
# effective sshd config (also the password-auth policy check: a client probe cannot prove it)
docker exec aipr-smoke /usr/sbin/sshd -T -f /etc/ssh/sshd_config.aipr 2>/dev/null > "$T/sshd-T"
for kv in 'disableforwarding yes' 'allowtcpforwarding no' 'allowstreamlocalforwarding no' 'passwordauthentication no' 'kbdinteractiveauthentication no' 'permitrootlogin no' 'pubkeyauthentication yes' 'maxauthtries 3' 'logingracetime 20'; do
  grep -qx "$kv" "$T/sshd-T" || { echo "FAIL: sshd -T lacks '$kv'" >&2; exit 1; }
done
echo "effective sshd config ok"
# seed a repo from the host over ssh, commit in the sandbox, pull the patch, apply it on the host
mkdir "$T/src" && cd "$T/src"
git init -q . && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
echo one > f.txt && git add f.txt && git -c user.name=t -c user.email=t@t commit -q -m seed
git bundle create "$T/seed.bundle" HEAD >/dev/null 2>&1
$S sbx@127.0.0.1 'cat > /work/seed.bundle' < "$T/seed.bundle"
$S sbx@127.0.0.1 'cd /work && git clone -q seed.bundle r && cd r && echo two >> f.txt && git -c user.name=t -c user.email=t@t commit -q -am change'
$S sbx@127.0.0.1 'cd /work/r && git diff HEAD~1 HEAD' > "$T/out.patch"
[ -s "$T/out.patch" ] || { echo "FAIL: empty patch" >&2; exit 1; }
git apply "$T/out.patch" || { echo "FAIL: patch does not apply" >&2; exit 1; }
[ "$(cat f.txt)" = "one
two" ] || { echo "FAIL: patched content wrong" >&2; exit 1; }
echo "seed/patch round trip ok"
echo SMOKE-PASS
