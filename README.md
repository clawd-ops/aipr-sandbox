# aipr-sandbox

Minimal Alpine-based image (non-root uid/gid 10001) running an unprivileged OpenSSH server on port 2222 with public-key auth only, plus git, python3 and coreutils. It is the sandbox used by an AI pull request review workflow: the caller seeds a repository over SSH, runs commands, and pulls a patch back.

Image: `ghcr.io/clawd-ops/aipr-sandbox`, tagged `v<VERSION>-<12-char commit sha>` (immutable, no `latest`). Base: `alpine:3.24.3` pinned by digest.

## Runtime contract

- Run as uid/gid 10001 (`runAsNonRoot`, `allowPrivilegeEscalation: false`, drop ALL capabilities, `seccompProfile: RuntimeDefault`). Works under the Kubernetes restricted Pod Security level and under Kata.
- `readOnlyRootFilesystem: true` is supported. Mount writable volumes at `/tmp` and `/work` (emptyDir; for `/work` set `fsGroup: 10001` or equivalent so uid 10001 can write).
- Required env: `AIPR_AUTHORIZED_KEY` (one public key line) or `AIPR_AUTHORIZED_KEY_FILE` (path to a mounted file). Optional `AIPR_HOST_KEY_FILE` (private host key; otherwise generated at start, fingerprint printed on stdout as `host-key-fingerprint:`).
- Listens on TCP 2222. Login user `sbx`, home and workdir `/work`, shell bash. Key-only auth; no passwords, no port, agent, X11 or tunnel forwarding.
- No credentials, GitHub access or model keys are baked in. Network policy is the caller's job.

## Layout

- `image/` Dockerfile, `sshd_config`, `entrypoint.sh`
- `tests/smoke.sh IMAGE` ssh, git and patch round-trip checks, run in CI before publishing
- `VERSION` bumped by hand for a new release line
- `.github/workflows/image.yml` builds and smoke-tests on every PR and push; publishes to GHCR on push to `main` or manual dispatch with `publish`

No license is declared yet.
