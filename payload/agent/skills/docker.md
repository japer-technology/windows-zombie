<!-- triggers: docker, container, compose, dockerd, image, podman, wsl -->
# Skill: Docker Desktop on Windows 10/11

This skill is loaded when the operator mentions Docker, containers,
images, Compose, or WSL.

Operating rules:

- Docker on Windows 10/11 runs via Docker Desktop (which uses WSL2 or
  Hyper-V). Docker Desktop has its own licensing — confirm with the
  operator that their use is permitted before suggesting an install.
  Podman Desktop is a license-free alternative; do not install either
  without explicit operator approval.
- Use `shell.run` with `docker ps`, `docker images`, `docker inspect`,
  and `docker logs --tail` for diagnostics; they are `read_only` under
  the default policy and run automatically.
- `docker run`, `docker build`, `docker pull`, `docker rm -f`,
  `docker volume rm`, and `docker system prune` are mutating. Prefer
  the most surgical command available and let the policy gate ask the
  operator to approve.
- Do not bind-mount the host's drive root (`-v C:\:/host`) or run
  containers with `--privileged` unless the operator explicitly asked
  and acknowledged the blast radius.
- Never include the operator's secrets file
  (`%ProgramData%\AiZombie\secrets\env`) as a bind mount or build
  argument. Secrets must reach a container only through the
  operator's chosen channel (e.g. `--env-file` on a separate,
  intentionally exported file).
- For Compose, prefer `docker compose ps` / `docker compose logs`
  before suggesting `up`/`down`. Compose `down -v` deletes volumes
  and is destructive; warn explicitly when suggesting it.
- WSL2 may stop or restart when Docker Desktop is updated. If the
  operator is also running Linux distros under WSL, surface that
  before suggesting `wsl --shutdown`.
