# aipr-sandbox

Minimal Alpine-based container image (non-root, UID 10001) that runs an unprivileged OpenSSH server on port 2222 with public-key auth only, plus git, python3 and coreutils. It is the sandbox used by an AI pull request review workflow to receive a repository seed over SSH and return a patch.

Runtime contract in short: the authorized public key comes from `AIPR_AUTHORIZED_KEY` or the file named by `AIPR_AUTHORIZED_KEY_FILE`, an optional host key from `AIPR_HOST_KEY_FILE`; `/tmp` and `/work` must be writable mounts and the root filesystem can be read-only. No password auth, no forwarding. Published as `ghcr.io/clawd-ops/aipr-sandbox`. No license is declared yet.

## Runtime contract (details)

- Run as uid/gid 10001 (`runAsNonRoot`, `allowPrivilegeEscalation: false`, drop ALL capabilities, `seccompProfile: RuntimeDefault`). Works under the Kubernetes restricted Pod Security level and under Kata.
- `readOnlyRootFilesystem: true` is supported. Mount writable volumes at `/tmp` and `/work` (emptyDir; for `/work` set `fsGroup: 10001` or equivalent so uid 10001 can write).
- Required env: `AIPR_AUTHORIZED_KEY` (one public key line) or `AIPR_AUTHORIZED_KEY_FILE` (path to a mounted file). Optional `AIPR_HOST_KEY_FILE` (private host key; otherwise generated at start, fingerprint printed on stdout as `host-key-fingerprint:`).
- Listens on TCP 2222. Login user `sbx`, home and workdir `/work`, shell bash. Key-only auth; no passwords, no port, agent, X11 or tunnel forwarding.
- No credentials, GitHub access or model keys are baked in. Network policy is the caller's job.
