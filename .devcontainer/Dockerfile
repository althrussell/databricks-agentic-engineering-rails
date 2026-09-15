# The execution boundary. docs/DECISIONS/0002-execution-boundary.md says what this
# isolates, and why credentials are created inside it rather than mounted into it.
#
# NOT YET BUILT. No container runtime was available on the machine that wrote this
# file. Every pin below is real -- each digest and hash was fetched from its
# registry or its release on 2026-09-15 -- but the image itself has never been
# assembled, so this is a verified recipe rather than a verified environment. The
# gap is g-container-runtime in release-readiness.yml, and the first successful
# `make sandbox-build` is what closes it. Expect to fix something here when it runs.
#
# Everything installed is pinned by content rather than by tag: the base image by
# manifest digest, and each binary by the sha256 of the exact release artifact,
# checked before extraction. HTTPS authenticates a host, not a version.
#
# The one exception is Claude Code, installed from npm by version. npm verifies the
# tarball against the integrity hash the registry serves, which pins the content to
# what that registry says the version is -- a weaker guarantee than the others, and
# named here rather than glossed over.

FROM python:3.12-slim-bookworm@sha256:782412e85d0f0984994c290652577d4018aff08145c85b262bb63dc0c7522254

# pandoc and typst versions match template-version.yml. That is what makes a PDF
# built in here comparable to one built on a laptop, and it is why `make docs-repro`
# refuses to judge reproducibility when they disagree.
ARG PANDOC_VERSION=3.11
ARG PANDOC_SHA256_amd64=37edb3bbcf722f921a009941bf5874e2e0c09263226c9b4a2d980788cb062ab6
ARG PANDOC_SHA256_arm64=56ed5566ec41d22ec9ee0704e6ac0b98ba102e92384efd5306173a22d314c79a
ARG TYPST_VERSION=0.15.1
ARG TYPST_SHA256_amd64=a6d077d0a95eed5a2eba715b2dae06be954f624ccbf85758a03f389ded33118c
ARG TYPST_SHA256_arm64=5aa8d74a3d906e60ea12a66ac2f37f8eef1b14cbad7182a745e393a10c23dcee
ARG NODE_VERSION=22.23.2
ARG NODE_SHA256_amd64=d60acfe00a2932254bb0ad20e01b0d74397a0875595de719654b214f4b03f307
ARG NODE_SHA256_arm64=fff4078c5def658577f92c88db7db3bc0072924bfb93fe52c1e744a54e94abb8
ARG UV_VERSION=0.11.15
ARG UV_SHA256_amd64=b03e572f010bea94a4a52d42671ba72981e12894f71576181a1d26ff68546da7
ARG UV_SHA256_arm64=21a7dd1a03ea17ac0366887455dab15d215b31dba0870dcd65d3714e22f46c81
ARG DATABRICKS_CLI_VERSION=1.1.0
ARG DATABRICKS_CLI_SHA256_amd64=c3a22409e54668c301fae684c83b2600302e2664df10cf1531c194e399f1d397
ARG DATABRICKS_CLI_SHA256_arm64=472276031a2a308de30cd363821c057d608b6636b64ee44abbb6a42439dead1d
ARG CLAUDE_CODE_VERSION=2.1.272

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

# poppler-utils carries pdftotext and pdfinfo, which the PDF overflow check and the
# reproducibility fingerprint shell out to. gawk rather than the default mawk,
# because scripts/link-check.sh and scripts/doctor.sh lean on awk and gawk is what
# they were written and tested against.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git make gawk xz-utils unzip \
        poppler-utils less \
    && rm -rf /var/lib/apt/lists/*

# One download helper for everything. A hash mismatch aborts the build before the
# archive is opened; nothing is extracted and then checked.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) node_tag=x64;   rust_tag=x86_64  ;; \
      arm64) node_tag=arm64; rust_tag=aarch64 ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    fetch() { \
      curl -fsSL --retry 3 --retry-delay 2 -o "$3" "$1"; \
      got="$(sha256sum "$3" | cut -d' ' -f1)"; \
      if [ "$got" != "$2" ]; then \
        echo "hash mismatch for $1" >&2; \
        echo "  expected $2" >&2; \
        echo "  got      $got" >&2; \
        exit 1; \
      fi; \
    }; \
    eval "sha=\$PANDOC_SHA256_$arch"; \
    fetch "https://github.com/jgm/pandoc/releases/download/${PANDOC_VERSION}/pandoc-${PANDOC_VERSION}-linux-${arch}.tar.gz" \
          "$sha" /tmp/pandoc.tgz; \
    tar -xzf /tmp/pandoc.tgz -C /usr/local --strip-components=1 \
        "pandoc-${PANDOC_VERSION}/bin/pandoc"; \
    eval "sha=\$TYPST_SHA256_$arch"; \
    fetch "https://github.com/typst/typst/releases/download/v${TYPST_VERSION}/typst-${rust_tag}-unknown-linux-musl.tar.xz" \
          "$sha" /tmp/typst.txz; \
    tar -xJf /tmp/typst.txz -C /tmp; \
    install -m 0755 "/tmp/typst-${rust_tag}-unknown-linux-musl/typst" /usr/local/bin/typst; \
    eval "sha=\$NODE_SHA256_$arch"; \
    fetch "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_tag}.tar.xz" \
          "$sha" /tmp/node.txz; \
    tar -xJf /tmp/node.txz -C /usr/local --strip-components=1 \
        --exclude CHANGELOG.md --exclude LICENSE --exclude README.md; \
    eval "sha=\$UV_SHA256_$arch"; \
    fetch "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${rust_tag}-unknown-linux-gnu.tar.gz" \
          "$sha" /tmp/uv.tgz; \
    tar -xzf /tmp/uv.tgz -C /tmp; \
    install -m 0755 "/tmp/uv-${rust_tag}-unknown-linux-gnu/uv" /usr/local/bin/uv; \
    install -m 0755 "/tmp/uv-${rust_tag}-unknown-linux-gnu/uvx" /usr/local/bin/uvx; \
    eval "sha=\$DATABRICKS_CLI_SHA256_$arch"; \
    fetch "https://github.com/databricks/cli/releases/download/v${DATABRICKS_CLI_VERSION}/databricks_cli_${DATABRICKS_CLI_VERSION}_linux_${arch}.zip" \
          "$sha" /tmp/dbcli.zip; \
    unzip -q -o /tmp/dbcli.zip -d /tmp/dbcli; \
    install -m 0755 /tmp/dbcli/databricks /usr/local/bin/databricks; \
    rm -rf /tmp/pandoc.tgz /tmp/typst.txz /tmp/node.txz /tmp/uv.tgz /tmp/dbcli.zip \
           /tmp/typst-* /tmp/uv-* /tmp/dbcli; \
    pandoc --version | head -1; \
    typst --version; \
    node --version; \
    uv --version; \
    databricks --version

# An unprivileged user with no sudo and no path to root. A boundary whose first
# available action is `sudo -i` is a costume. UID 1000 matches the usual host UID so
# a bind-mounted repository stays writable without a chown.
RUN useradd --uid 1000 --create-home --shell /bin/bash rails \
    && mkdir -p /work && chown rails:rails /work
USER rails
WORKDIR /work
ENV PATH="/home/rails/.local/bin:/home/rails/.npm-global/bin:${PATH}" \
    NPM_CONFIG_PREFIX="/home/rails/.npm-global"

# The Unity Gateway CLI and Claude Code, both installed as the unprivileged user so
# nothing an agent touches is owned by root.
#
# Both carry licences worth knowing about: unity-gateway is under the Databricks
# License, which permits use in connection with your use of the Databricks Services.
# See NOTICE. Neither is redistributable on this repository's terms, which is why
# they are installed here rather than vendored.
#
# unity-gateway is pinned to a commit, not a branch. A branch name is not a version,
# and `ug --version` reports a commit-qualified string precisely because the commit
# is what identifies a build.
ARG UNITY_GATEWAY_COMMIT=c2e90644341b9fe4057b148d4eea535bcad7f478
RUN uv tool install "git+https://github.com/databricks/unity-gateway@${UNITY_GATEWAY_COMMIT}" \
    && ug --version

RUN npm install --global --no-fund --no-audit \
      "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && claude --version

# Where the harness writes its per-session state. Owned by the unprivileged user and
# outside /work, so a bind-mounted repository never receives a token cache even by
# accident.
ENV XDG_CONFIG_HOME=/home/rails/.config \
    XDG_CACHE_HOME=/home/rails/.cache

# 8020 is the port the reference application binds. Nothing else is published: an
# agent inside the boundary should not be able to expose a service by accident.
EXPOSE 8020

CMD ["/bin/bash"]
