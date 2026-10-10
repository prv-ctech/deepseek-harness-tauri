# DeepSeek Harness Tauri remote desktop

Runs the official Linux amd64 desktop in Selkies. Docker Compose includes a private Docker-in-Docker (DinD) sidecar for workloads launched by the desktop.

## Proxy network setup

Selkies Basic Auth and HTTPS are disabled; backend is unauthenticated HTTP on container port `8080`. Default remote ingress is through a reverse proxy that enforces authentication and TLS. The trusted Docker host and every member of the trusted DinD bridge can also reach the desktop listener by its bridge IP. Treat `dsh-dind` (Unraid) and Compose's project-private `dind` network as trusted: only desktop and DinD may join; never attach unrelated containers. Keep the DinD service off `dsh-proxy`; that bridge is dedicated to desktop and reverse proxy only. Create the proxy bridge once on the Docker host and attach the reverse-proxy container:

```sh
docker network create --driver bridge dsh-proxy
docker network connect dsh-proxy <reverse-proxy-container-name>
```

Docker provides container-name DNS on user-defined bridges ([bridge network docs](https://docs.docker.com/engine/network/drivers/bridge/)); configure proxy upstream as `desktop:8080` in Compose or `deepseek-harness-desktop:8080` on Unraid. By default, publish no Selkies host port. If the reverse proxy runs as a host process, use a local Compose override with only this loopback mapping:

```yaml
services:
  desktop:
    ports:
      - "127.0.0.1:8080:8080"
```

Docker Engine `28.0.0` or newer is required unless a host firewall protects the port: older Engine versions may expose localhost-published ports to same-L2 peers. Upgrade or apply host firewall rules before using the override. Never wildcard-publish (`8080:8080`). Selkies authentication details are in [Secure Mode](https://docs.selkies.io/latest/secure-mode).

## Docker Compose

Requires Docker Engine with the Compose plugin on an amd64 host. Set `PROXY_NETWORK` in `.env` to the existing proxy bridge (default `dsh-proxy`), then start:

```sh
cp .env.example .env
docker compose up -d
```

Compose connects desktop service `desktop` to the project-private DinD bridge and external proxy bridge; DinD joins only the private bridge. DinD retains outbound connectivity for image pulls, while port `2375` is not published. Compose persists named volumes `home` (`/home/ubuntu`), `workspaces` (`/workspaces`), and `docker-data` (`/var/lib/docker`). To pull the latest published image, run `docker compose pull desktop` then `docker compose up -d`. To build locally from the latest upstream stable release without reusing a cached resolver layer, run:

```sh
docker compose build --no-cache desktop
docker compose up -d
```

CPU rendering is the default. For optional Intel graphics, ensure the host render device is available, set `RENDER_GID` in `.env` to its numeric group ID (for example, `stat -c '%g' /dev/dri/renderD128`), then start with the override:

```sh
docker compose -f compose.yaml -f compose.intel.yaml up -d
```

## Podman Desktop

For a local browser test, create the external proxy bridge once if needed and copy `.env.example` to `.env` on first setup only. Keep `COMPOSE_PROJECT_NAME` unchanged for builds and updates so Podman reuses the same named volumes. Do not use `down -v` unless you intend to delete settings and workspace data:

```sh
podman network create dsh-proxy
cp .env.example .env
podman compose build --no-cache desktop
printf 'services:\n  desktop:\n    ports:\n      - "127.0.0.1:18080:8080"\n' | podman compose -f compose.yaml -f - up -d
```

Open `http://127.0.0.1:18080`. The host port is loopback-only because Selkies has no login in this setup. The `deepseek-harness_home` volume stores Tauri settings under `/home/ubuntu/.local/share/dsh-tauri`, DSH data under `/home/ubuntu/.dsh`, and the default workspace under `/home/ubuntu/Documents/deepseek-harness/default-workspace`. `deepseek-harness_workspaces` stores `/workspaces`, and `deepseek-harness_docker-data` stores the DinD images and volumes. Container recreation and image updates keep these volumes. Inspect their host storage paths with `podman volume inspect deepseek-harness_home deepseek-harness_workspaces deepseek-harness_docker-data`.

## Unraid

Use both [desktop](templates/deepseek-harness-desktop.xml) and [DinD](templates/deepseek-harness-dind.xml) v2 templates. Create the private DinD bridge before installing either container; it is a normal bridge with outbound access, not an `internal` network:

```sh
docker network create --driver bridge dsh-dind
```

Both templates use primary network `custom:dsh-dind`; Docker DNS resolves DinD as `deepseek-harness-dind`. Treat `dsh-dind` as trusted and attach only the desktop and DinD; unrelated containers must not join. Only desktop has `<ExtraNetworks>dsh-proxy</ExtraNetworks>` and joins `dsh-proxy`, which is dedicated to the desktop and reverse proxy only; unrelated containers must not join, and DinD must stay off it. The trusted Docker host and `dsh-dind` members can reach the unauthenticated desktop listener on `8080` by its bridge IP, so default remote ingress must remain through the reverse proxy at `deepseek-harness-desktop:8080`. Neither web port nor DinD `2375` is host-published by default, and the desktop template has no direct WebUI. Do not use Unraid's `Custom: br0` for these private links: `br0` is a LAN-facing custom macvlan/ipvlan network, not a private bridge ([Unraid container networking](https://docs.unraid.net/unraid-os/using-unraid-to/run-docker-containers/managing-and-customizing-containers/)).

The current Unraid Docker Manager source reads template `<ExtraNetworks>`, splits comma/space-separated network names, and connects them after container creation ([manager creation path](https://github.com/unraid/webgui/blob/master/emhttp/plugins/dynamix.docker.manager/include/CreateDocker.php), [network connection helper](https://github.com/unraid/webgui/blob/master/emhttp/plugins/dynamix.docker.manager/include/Helpers.php)). Actual support depends on the installed Unraid version; confirm that its Docker Manager supports this field before using the template.

Default persistent host paths:

| Container path    | Unraid host path                                 | Data                                                               |
| ----------------- | ------------------------------------------------ | ------------------------------------------------------------------ |
| `/home/ubuntu`    | `/mnt/user/appdata/deepseek-harness/home`        | App settings, logs, user-installed tools, and default `$HOME/.dsh` |
| `/workspaces`     | `/mnt/user/appdata/deepseek-harness/workspaces`  | Project files                                                      |
| `/var/lib/docker` | `/mnt/user/appdata/deepseek-harness/docker-data` | DinD images, containers, and volumes                               |

The upstream Selkies desktop runs as UID `1000`; the template keeps that non-root runtime user and adds supplemental GID `100`. Do not use PUID/PGID remapping or run the desktop as root. Unraid appdata is commonly owned by `nobody:users` (`99:100`). Setgid on the app's home/workspaces directories makes new children inherit GID `100`; the image sets the session umask to `0002`, supplying group-write for ordinary new files created with the usual `0666` mode. Selkies 2.0.0's [`/etc/container-entrypoint.sh`](https://github.com/selkies-project/selkies/blob/2.0.0/addons/base/container-entrypoint.sh) hands off via `exec s6-svscan /etc/service`, so this umask is inherited by its supervised session ([startup docs](https://docs.selkies.io/latest/components/base-image#how-it-starts)). Local mode reproduction: setgid directory plus umask `0022` produced `0644` with GID `100`; umask `0002` produced `0664` with GID `100`.

Before adding/applying the Unraid desktop template, prepare host bind paths from the Unraid terminal so template Apply cannot start the desktop against unprepared mounts. For an existing install, stop the desktop first. Bind mounts hide image-owned directory metadata, so home/workspaces host roots need GID `100` and setgid before first start; umask controls file modes, not host ownership or setgid. Run:

```sh
mkdir -p /mnt/user/appdata/deepseek-harness/home /mnt/user/appdata/deepseek-harness/workspaces
chown -R 99:100 /mnt/user/appdata/deepseek-harness/home /mnt/user/appdata/deepseek-harness/workspaces
find /mnt/user/appdata/deepseek-harness/home /mnt/user/appdata/deepseek-harness/workspaces -type d -exec chmod u+rwx,g+rwx,g+s {} +
find /mnt/user/appdata/deepseek-harness/home /mnt/user/appdata/deepseek-harness/workspaces -type f -exec chmod g+rwX {} +
```

`mkdir -p` is safe for existing directories. If you replace template host paths, substitute your chosen home/workspaces paths in every command. After preparation, install/apply and start the desktop. If template Apply auto-starts before preparation and this cannot be avoided, stop the desktop immediately, run this sequence with it stopped, then restart before use. These commands affect only this app's home and workspaces; do not apply them to DinD data or chmod all of `/mnt/user/appdata`. To verify new-file behavior, open a Selkies desktop terminal (not `docker exec`, whose process does not inherit PID 1's umask) and run:

```sh
(
  umask
  probe="/workspaces/.dsh-umask-check-$(date +%s%N)-$$"
  ( set -C; : > "$probe" ) || exit 1
  trap 'rm -- "$probe"' EXIT
  stat -c '%a %g' -- "$probe"
)
```

Expect umask `0002` and `stat` output `664 100`. The exact unique probe is removed on exit. This container's Unraid runtime/filesystem was unavailable during development; repeat the check after deploying to the actual Unraid host. Mount any custom `DSH_HOME` separately if it is outside `/home/ubuntu`. Install per-user applications through Selkies' app panel (`proot-apps`) without root; system package changes belong in the Dockerfile/image build, not an elevated running desktop. See [Selkies desktop image docs](https://docs.selkies.io/latest/components/desktop-image) and [Unraid shares docs](https://docs.unraid.net/unraid-os/using-unraid-to/manage-storage/shares/).

## Image updates

GitHub Actions builds `linux/amd64` on pull requests without publishing. Pushes to `main` and a daily schedule resolve the latest upstream stable release, then publish `ghcr.io/prv-ctech/deepseek-harness-tauri:latest` and the normalized app-version tag (for example, `:0.22.4`). The build uses the shared release resolver and verifies the official amd64 Debian package SHA-256 and package metadata.

## Security

Selkies Basic Auth and HTTPS are disabled in the provided deployments, so the backend is unauthenticated HTTP. The reverse proxy is the default remote ingress and must enforce authentication **and** TLS; TLS alone is insufficient. Although no port is published by default, the trusted Docker host and any `dsh-dind` bridge member can connect to the listener by desktop bridge IP. Keep `dsh-dind` limited to desktop+DinD and `dsh-proxy` limited to desktop+reverse proxy; neither network is for unrelated containers. See [Selkies Secure Mode](https://docs.selkies.io/latest/secure-mode) for Selkies authentication modes.

DinD runs `privileged: true`: desktop users can control its unauthenticated Docker daemon, and a compromised privileged container can threaten the host. Keep port `2375` private (the provided Compose/Unraid setup does not publish it), never mount the host Docker socket, and run only on a trusted or isolated host.
