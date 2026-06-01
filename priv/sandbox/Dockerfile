FROM elixir:1.18-alpine

# Pre-bake an empty Mix project so the stdlib + ExUnit deps are cached in the
# image layer. The sandbox mounts generated source at /input and copies it to
# /work at runtime — no network access is available then.
WORKDIR /prebake

RUN mix local.hex --force && mix local.rebar --force

COPY mix_template.exs mix.exs
RUN mix deps.get && mix deps.compile

# Create a non-root user (uid 65532 matches the --user flag in Sandbox).
# /work is created here so the tmpfs mount point exists when the container starts.
RUN addgroup -g 65532 sandbox && \
    adduser -u 65532 -G sandbox -s /bin/sh -D sandbox && \
    mkdir -p /work && chown sandbox:sandbox /work

USER 65532:65532

WORKDIR /work
