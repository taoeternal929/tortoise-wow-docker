# syntax=docker/dockerfile:1
#
# Builds the Tortoise WoW servers (realmd, mangosd) and extractors from the
# upstream source at a pinned commit, plus the patches in ./patches.
#
# Build context is this folder (server/). Examples:
#
#   docker build server --target mangosd \
#     --build-arg UPSTREAM_COMMIT=$(. server/upstream.env; echo $UPSTREAM_COMMIT) \
#     -t tortoise-wow-mangosd
#
#   # just the compiled files, copied to ./out
#   docker build server --target binaries --output type=local,dest=out \
#     --build-arg UPSTREAM_COMMIT=...
#
# The GitHub Actions workflow (.github/workflows/upstream-sync.yml) runs these
# same builds and publishes the images to GHCR.

ARG BASE_IMAGE=ubuntu:26.04

# ---------------------------------------------------------------------------
# builder: compile everything into /opt/tw
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS builder
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build git ca-certificates \
      libace-dev libmariadb-dev libssl-dev zlib1g-dev libbz2-dev \
 && rm -rf /var/lib/apt/lists/*

ARG UPSTREAM_REPO=https://github.com/tortoise-wow/tortoise-wow.git
ARG UPSTREAM_COMMIT
RUN test -n "${UPSTREAM_COMMIT}" \
 || { echo "UPSTREAM_COMMIT build arg is required (see server/upstream.env)" >&2; exit 1; }

# .git is kept so CMake can embed the upstream revision in the version string.
ADD --keep-git-dir=true ${UPSTREAM_REPO}#${UPSTREAM_COMMIT} /src

# Patches are applied in file-name order. A patch that no longer applies fails
# the build here, which is the signal to refresh it (see server/patches/README.md).
COPY patches/ /patches/
WORKDIR /src
RUN set -eu; \
    for p in /patches/*.patch; do \
      [ -e "$p" ] || continue; \
      echo ">>> applying ${p##*/}"; \
      git apply --whitespace=nowarn "$p"; \
    done

# Same options as the hand-run cmake_cmd_release. Do not pass -DPREFIX: with
# CMake 4.x it clashes with a variable CMake uses while detecting the compiler,
# so the install location is set with CMAKE_INSTALL_PREFIX instead.
RUN cmake -S /src -B /build -G Ninja \
      -DCMAKE_INSTALL_PREFIX=/opt/tw \
      -DCMAKE_BUILD_TYPE=Release \
      -DUSE_SCRIPTS=ON \
      -DUSE_EXTRACTORS=ON \
      -DCMAKE_CXX_STANDARD=17 \
      -DCMAKE_CXX_STANDARD_REQUIRED=ON \
      -DUSE_ANTICHEAT=ON \
      -DDEBUG_SYMBOLS=OFF \
      -DCMAKE_EXE_LINKER_FLAGS="-Wl,--strip-all" \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
      -DALLOW_TURTLE_ADDONS=ON \
 && cmake --build /build --parallel \
 && cmake --install /build

# Work out which Ubuntu packages provide the shared libraries the binaries
# need, so the runtime images install exactly those (and keep working when the
# base image's library versions change, e.g. libace-8.0.5 -> a later ACE).
RUN set -eu; \
    for f in /opt/tw/bin/*; do ldd "$f" 2>/dev/null || true; done \
      | awk '$2 == "=>" && $3 ~ /^\// { print $3 }' | sort -u \
      | xargs -r realpath | xargs -r dpkg -S \
      | cut -d: -f1 | sort -u > /opt/tw/runtime-packages.txt; \
    echo ">>> runtime packages:"; cat /opt/tw/runtime-packages.txt

# ---------------------------------------------------------------------------
# runtime: base for the server images
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS runtime
ARG DEBIAN_FRONTEND=noninteractive
COPY --from=builder /opt/tw/runtime-packages.txt /tmp/runtime-packages.txt
RUN apt-get update \
 && xargs -a /tmp/runtime-packages.txt apt-get install -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* /tmp/runtime-packages.txt
ARG UPSTREAM_COMMIT
LABEL org.opencontainers.image.title="Tortoise WoW server" \
      io.github.tortoise-wow.upstream-commit="${UPSTREAM_COMMIT}"
# Fills ${VAR} placeholders in the server config from the environment, then
# exec's the server (see tw-entrypoint.sh).
COPY --chmod=755 tw-entrypoint.sh /usr/local/bin/tw-entrypoint

# realmd: authentication / realm list server
FROM runtime AS realmd
WORKDIR /opt/realmd
COPY --from=builder /opt/tw/bin/realmd ./realmd
RUN if ldd ./realmd | grep 'not found'; then exit 1; fi
EXPOSE 3724
# realmd.conf is bind-mounted by docker-compose.yml; its DB login comes from .env
ENTRYPOINT ["tw-entrypoint"]
CMD ["./realmd", "-c", "realmd.conf"]

# mangosd: world server
FROM runtime AS mangosd
WORKDIR /opt/mangosd
COPY --from=builder /opt/tw/bin/mangosd ./mangosd
RUN if ldd ./mangosd | grep 'not found'; then exit 1; fi
EXPOSE 8085
# mangosd.conf and the data folders are bind-mounted by docker-compose.yml;
# its DB logins come from .env
ENTRYPOINT ["tw-entrypoint"]
CMD ["./mangosd", "-c", "mangosd.conf"]

# tools: map/vmap/mmap extractors, for preparing data/ from a game client
FROM runtime AS tools
COPY --from=builder /opt/tw/bin/ /opt/tools/
RUN rm -f /opt/tools/mangosd /opt/tools/realmd /opt/tools/run-mangosd \
 && for f in /opt/tools/*; do if ldd "$f" | grep 'not found'; then exit 1; fi; done
ENV PATH=/opt/tools:$PATH
WORKDIR /client

# binaries: plain files, for `--output type=local,dest=...`
FROM scratch AS binaries
COPY --from=builder /opt/tw/bin/ /
