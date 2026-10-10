# syntax=docker/dockerfile:1.7

FROM ubuntu:26.04 AS app-release
ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive
RUN test "${TARGETARCH}" = "amd64" || { echo "This image supports amd64 only (got ${TARGETARCH:-unset})" >&2; exit 1; } \
    && apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates curl python3 \
    && rm -rf /var/lib/apt/lists/*
COPY scripts/latest-app-release.sh /usr/local/bin/latest-app-release
ARG APP_RELEASE_TAG
ARG APP_RELEASE_ASSET_URL
ARG APP_RELEASE_SHA256
RUN set -eu; \
    chmod 0755 /usr/local/bin/latest-app-release; \
    APP_RELEASE_TAG="${APP_RELEASE_TAG:-}"; \
    APP_RELEASE_ASSET_URL="${APP_RELEASE_ASSET_URL:-}"; \
    APP_RELEASE_SHA256="${APP_RELEASE_SHA256:-}"; \
    if [ -z "$APP_RELEASE_TAG" ] && [ -z "$APP_RELEASE_ASSET_URL" ] && [ -z "$APP_RELEASE_SHA256" ]; then \
        release="$(/usr/local/bin/latest-app-release)"; \
        tag="$(printf '%s\n' "$release" | sed -n 's/^tag=//p')"; \
        asset_url="$(printf '%s\n' "$release" | sed -n 's/^asset_url=//p')"; \
        sha256="$(printf '%s\n' "$release" | sed -n 's/^sha256=//p')"; \
        test -n "$tag" && test -n "$asset_url" && test -n "$sha256"; \
        version="${tag#v}"; \
    elif [ -n "$APP_RELEASE_TAG" ] && [ -n "$APP_RELEASE_ASSET_URL" ] && [ -n "$APP_RELEASE_SHA256" ]; then \
        APP_RELEASE_TAG="$APP_RELEASE_TAG" APP_RELEASE_ASSET_URL="$APP_RELEASE_ASSET_URL" APP_RELEASE_SHA256="$APP_RELEASE_SHA256" python3 -c 'import os, re; \
            repository = "dsh-tauri/deepseek-harness-desktop"; \
            tag = os.environ["APP_RELEASE_TAG"]; asset_url = os.environ["APP_RELEASE_ASSET_URL"]; digest = os.environ["APP_RELEASE_SHA256"]; \
            assert re.fullmatch(r"v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag), "APP_RELEASE_TAG must be a stable semantic version"; \
            version = tag[1:] if tag.startswith("v") else tag; \
            expected = "https://github.com/" + repository + "/releases/download/" + tag + "/Deepseek.Harness.Desktop_" + version + "_amd64.deb"; \
            assert asset_url == expected, "APP_RELEASE_ASSET_URL does not match the official release asset"; \
            assert re.fullmatch(r"[0-9a-fA-F]{64}", digest), "APP_RELEASE_SHA256 must contain exactly 64 hexadecimal characters"' ; \
        tag="$APP_RELEASE_TAG"; \
        version="${tag#v}"; \
        asset_url="$APP_RELEASE_ASSET_URL"; \
        sha256="$(printf '%s' "$APP_RELEASE_SHA256" | tr '[:upper:]' '[:lower:]')"; \
    else \
        echo "APP_RELEASE_TAG, APP_RELEASE_ASSET_URL, and APP_RELEASE_SHA256 must all be set or all be empty" >&2; \
        exit 1; \
    fi; \
    curl --fail --location --silent --show-error "$asset_url" -o /tmp/deepseek-harness-desktop.deb; \
    printf '%s  %s\n' "$sha256" /tmp/deepseek-harness-desktop.deb | sha256sum --check -; \
    test "$(dpkg-deb --field /tmp/deepseek-harness-desktop.deb Package)" = deepseek-harness-desktop; \
    test "$(dpkg-deb --field /tmp/deepseek-harness-desktop.deb Architecture)" = amd64; \
    test "$(dpkg-deb --field /tmp/deepseek-harness-desktop.deb Version)" = "$version"

FROM ghcr.io/selkies-project/selkies/desktop:2.0.0-ubuntu26.04 AS lxqt-panel-build
USER 0
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /tmp
COPY docker/patches/lxqt-panel-start-hidden.patch /tmp/lxqt-panel-start-hidden.patch
RUN set -eu; \
    sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources; \
    apt-get update; \
    apt-get install --no-install-recommends -y build-essential dpkg-dev patch; \
    panel_version="$(dpkg-query -W -f='${Version}' lxqt-panel)"; \
    apt-get build-dep --no-install-recommends -y "lxqt-panel=$panel_version"; \
    apt-get source "lxqt-panel=$panel_version"; \
    source_dir="$(find /tmp -mindepth 1 -maxdepth 1 -type d -name 'lxqt-panel-*' -print -quit)"; \
    cd "$source_dir"; \
    patch -p1 --forward < /tmp/lxqt-panel-start-hidden.patch; \
    dpkg-buildpackage -b -uc -us; \
    cp "/tmp/lxqt-panel_${panel_version}_amd64.deb" /tmp/lxqt-panel-patched.deb; \
    rm -rf /var/lib/apt/lists/*

FROM ghcr.io/selkies-project/selkies/desktop:2.0.0-ubuntu26.04
ARG TARGETARCH
USER 0
COPY --from=app-release /tmp/deepseek-harness-desktop.deb /tmp/deepseek-harness-desktop.deb
COPY --from=lxqt-panel-build /tmp/lxqt-panel-patched.deb /tmp/lxqt-panel-patched.deb
# Copy client only; Docker daemon runs in the separate privileged DinD service.
COPY --from=docker:29.8.0-cli /usr/local/bin/docker /usr/local/bin/docker
COPY docker/deepseek-harness-autostart.desktop /etc/xdg/autostart/deepseek-harness.desktop
COPY docker/launch-deepseek-harness.sh /usr/local/bin/launch-deepseek-harness
RUN test "${TARGETARCH}" = "amd64" || { echo "This image supports amd64 only (got ${TARGETARCH:-unset})" >&2; exit 1; } \
    && apt-get update \
    && apt-get install --no-install-recommends -y libglib2.0-bin /tmp/deepseek-harness-desktop.deb \
    && dpkg -i /tmp/lxqt-panel-patched.deb \
    && test -f "/usr/share/applications/Deepseek Harness Desktop.desktop" \
    && test -x /usr/bin/wmctrl \
    && chmod 0755 /usr/local/bin/launch-deepseek-harness \
    && install -d -o 1000 -g 1000 /home/ubuntu /workspaces \
    && chown 1000:1000 /home/ubuntu /workspaces \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/deepseek-harness-desktop.deb /tmp/lxqt-panel-patched.deb
COPY docker/lxqt-panel.conf /etc/xdg/lxqt/panel.conf
ENV HOME=/home/ubuntu
WORKDIR /workspaces
VOLUME ["/home/ubuntu", "/workspaces"]
USER 1000:1000
# Set shared-group creation mode before Selkies starts its s6 supervisor.
ENTRYPOINT ["/bin/sh", "-c", "umask 0002; exec /etc/container-entrypoint.sh \"$@\"", "--"]
