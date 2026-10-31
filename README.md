# aipr-sandbox

Minimal Alpine-based container image (non-root, UID 10001) that runs an unprivileged OpenSSH server on port 2222 with public-key auth only, plus git, python3 and coreutils. It is the sandbox used by an AI pull request review workflow to receive a repository seed over SSH and return a patch.

Runtime contract in short: the authorized public key comes from `AIPR_AUTHORIZED_KEY` or the file named by `AIPR_AUTHORIZED_KEY_FILE`, an optional host key from `AIPR_HOST_KEY_FILE`; `/tmp` and `/work` must be writable mounts and the root filesystem can be read-only. No password auth, no forwarding. Published as `ghcr.io/clawd-ops/aipr-sandbox`. No license is declared yet.
