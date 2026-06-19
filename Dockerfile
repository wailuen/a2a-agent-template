# syntax=docker/dockerfile:1
# Build:  docker build --ssh default -t {{AGENT_NAME}} .
# The SSH key is mounted only for the install step and never enters a layer.

FROM ghcr.io/astral-sh/uv:latest AS uv

FROM python:3.12-slim AS build

COPY --from=uv /uv /usr/local/bin/uv

RUN apt-get update && apt-get install -y --no-install-recommends git openssh-client \
    && rm -rf /var/lib/apt/lists/*

# GitHub's PUBLISHED host-key fingerprints, baked statically.
# Never `ssh-keyscan` at build time — that is trust-on-first-use.
# Source: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
RUN mkdir -p -m 0700 /root/.ssh && cat > /root/.ssh/known_hosts <<'EOF'
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
EOF

WORKDIR /app
# PREREQUISITE: uv.lock must exist before running `docker build`.
# The raw template ships no lockfile — pyproject.toml contains unresolved
# {{SDK_GIT_URL}}/{{SDK_SHA}} placeholders that `uv lock` cannot resolve.
# Run `/setup` or `/new-agent` first (scaffold Phase 2 renders placeholders
# and generates uv.lock). Building from the unscaffolded template repo will
# fail here with "COPY failed: file not found in build context: uv.lock".
COPY pyproject.toml uv.lock ./
COPY src ./src

# --frozen pins to the committed lockfile — no fresh resolution at build time.
# UV_LINK_MODE=copy avoids hardlink failures when the venv is copied across
# overlay filesystem boundaries in the multi-stage build.
# The ssh mount is never committed to a layer; it exists only for this RUN.
# Dev deps live under [project.optional-dependencies].dev (an *extra*, not a
# dependency-group), so they are excluded by default — no --extra flag needed.
# Do not add --no-dev here: that flag targets [dependency-groups], not extras,
# and would be a silent no-op against this layout.
ENV UV_LINK_MODE=copy
RUN --mount=type=ssh \
    uv sync --frozen


FROM python:3.12-slim

RUN useradd --create-home --uid 10001 agent \
    && mkdir -p /data && chown agent:agent /data
COPY --from=build /app/.venv /app/.venv
COPY --chown=agent:agent src /app/src

USER agent
WORKDIR /app
VOLUME ["/data"]
ENV DATA_DIR=/data PORT=8000 PATH="/app/.venv/bin:$PATH"
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD python -c "import urllib.request,os;urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\",\"8000\")}/health')" || exit 1

# Exactly one worker — the task store, SSE queues and rate limiter are
# process-local (SDK deployment invariant). Scale by replicating origins,
# not workers.
CMD ["sh", "-c", "uvicorn src.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1"]
