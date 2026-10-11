# DeepSeek Harness Tauri remote desktop

Runs the official Linux amd64 desktop in Selkies. Docker Compose includes a Docker-in-Docker (DinD) sidecar for workloads launched by the desktop.

## Network setup

Selkies Basic Auth and HTTPS are disabled in both deployments. Selkies serves HTTP on container port `8080`; Pangolin handles browser authentication and public HTTPS, then forwards to the desktop over HTTP ([resource types](https://docs.pangolin.net/manage/resources/understanding-resources), [HTTP target setup](https://docs.pangolin.net/manage/common-api-routes)). No Unraid host port is needed: configure the Pangolin HTTP target as `deepseek-harness-tauri:8080`. For Compose, the target is `desktop:8080`.

Select the same existing **user-defined Docker bridge network** for the desktop, DinD, and Pangolin Site connector. Docker supplies container-name DNS on user-defined bridges, so each service can reach the others by container name ([bridge network docs](https://docs.docker.com/engine/network/drivers/bridge/)). For Unraid, choose the same network in both templates and connect the Pangolin Site connector to it. For Compose and Podman, set `DSH_NETWORK` to that existing network's name. The templates and Compose file do not create or assume a network name.

All containers on a shared bridge can reach each other's container ports. The DinD API requires client-authenticated TLS; only the desktop gets the client certificates. Do not publish the DinD API port `2376` on the host. The desktop WebUI also has no host-published port by default. If a Compose reverse proxy runs as a host process, use a local override with only this loopback mapping:

```yaml
services:
  desktop:
    ports:
      - "127.0.0.1:8080:8080"
```

Docker Engine `28.0.0` or newer is required unless a host firewall protects the port: older Engine versions may expose localhost-published ports to same-L2 peers. Upgrade or apply host firewall rules before using the override. Never wildcard-publish (`8080:8080`). Selkies authentication details are in [Secure Mode](https://docs.selkies.io/latest/secure-mode).

## Docker Compose

Requires Docker Engine with the Compose plugin on an amd64 host. Copy `.env.example`, then set `DSH_NETWORK` in `.env` to the existing user-defined Docker network shared with Pangolin. The example value is a placeholder:

```sh
cp .env.example .env
# Replace the DSH_NETWORK placeholder in .env with your existing network name.
docker network inspect your-existing-docker-network
docker compose up -d
```

Use the same network name in `docker network inspect` and `.env`. Compose connects both services to that existing network. DinD retains outbound connectivity for image pulls and serves its client-authenticated TLS API on container port `2376`, with no host port published. Compose persists named volumes `home` (`/home/ubuntu`), `workspaces` (`/workspaces`), `docker-data` (`/var/lib/docker`), `docker-certs-ca` (DinD CA), and `docker-certs-client` (client certificates; mounted read-only in the desktop). To pull the latest published image, run `docker compose pull desktop` then `docker compose up -d`. To build locally from the latest upstream stable release without reusing a cached resolver layer, run:

```sh
docker compose build --no-cache desktop
docker compose up -d
```

CPU rendering is the default. For optional Intel graphics, ensure the host render device is available, set `RENDER_GID` in `.env` to its numeric group ID (for example, `stat -c '%g' /dev/dri/renderD128`), then start with the override:

```sh
docker compose -f compose.yaml -f compose.intel.yaml up -d
```

## Podman Desktop

For a local browser test, set `DSH_NETWORK` in `.env` to an existing user-defined Podman network shared with Pangolin. Copy `.env.example` on first setup and replace its placeholder value. Keep `COMPOSE_PROJECT_NAME` unchanged for builds and updates so Podman reuses the same named volumes. Do not use `down -v` unless you intend to delete settings and workspace data:

```sh
cp .env.example .env
# Replace the DSH_NETWORK placeholder in .env first.
podman network inspect your-existing-docker-network
podman compose build --no-cache desktop
printf 'services:\n  desktop:\n    ports:\n      - "127.0.0.1:18080:8080"\n' | podman compose -f compose.yaml -f - up -d
```

Open `http://127.0.0.1:18080`. This local Compose test uses HTTP without Selkies login, so keep the host port loopback-only. The `deepseek-harness_home` volume stores Tauri settings under `/home/ubuntu/.local/share/dsh-tauri`, DSH data under `/home/ubuntu/.dsh`, and the default workspace under `/home/ubuntu/Documents/deepseek-harness/default-workspace`. `deepseek-harness_workspaces` stores `/workspaces`, and `deepseek-harness_docker-data` stores the DinD images and volumes. Container recreation and image updates keep these volumes. Inspect their host storage paths with `podman volume inspect deepseek-harness_home deepseek-harness_workspaces deepseek-harness_docker-data`.

## Unraid

The [desktop template](templates/deepseek-harness-tauri.xml) runs the Selkies browser desktop. Access it through a Pangolin HTTP/HTTPS resource; the Unraid template does not publish port `8080` on the host. The [DinD template](templates/deepseek-harness-dind.xml) supplies a Docker daemon for container workloads; it is not the desktop WebUI. Install and start DinD first so it generates TLS client certificates. Then install the desktop template.

In each template, select the same existing user-defined Docker network and connect the Pangolin Site connector to it. The template's initial `bridge` selection is a neutral placeholder—change it to your network. Keep the DinD container name `deepseek-harness-dind`; Docker DNS and the TLS server certificate use that name. DinD listens on container port `2376`, and the desktop mounts only its client certificate directory read-only at `/certs/client`. If you change DinD's certificate host path, update the desktop client certificate host path to the matching `client` subdirectory. Do not add an Unraid Port mapping for `2376`: containers on the shared network can connect directly, and TLS verifies the client. Pangolin's HTTP target is `deepseek-harness-tauri:8080`. Selkies authentication and HTTPS are disabled; Pangolin owns browser authentication and public TLS. Do not use Unraid's `Custom: br0` when you need container-name DNS: Docker documents automatic name resolution on user-defined bridge networks, while the default bridge and other drivers differ ([Unraid container networking](https://docs.unraid.net/unraid-os/using-unraid-to/run-docker-containers/managing-and-customizing-containers/), [Docker bridge networking](https://docs.docker.com/engine/network/drivers/bridge/)).

Default persistent host paths:

| Container path    | Unraid host path                                  | Data                                                                 |
| ----------------- | ------------------------------------------------- | -------------------------------------------------------------------- |
| `/home/ubuntu`    | `/mnt/user/appdata/deepseek-harness/home`         | App settings, logs, user-installed tools, and default `$HOME/.dsh`   |
| `/workspaces`     | `/mnt/user/appdata/deepseek-harness/workspaces`   | Project files                                                        |
| `/var/lib/docker` | `/mnt/user/appdata/deepseek-harness/docker-data`  | DinD images, containers, and volumes                                 |
| `/certs`          | `/mnt/user/appdata/deepseek-harness/docker-certs` | DinD TLS certificates; desktop mounts only `/certs/client` read-only |

The upstream Selkies desktop runs as UID:GID `1000:1000`; the template keeps that non-root runtime identity and adds supplemental GID `100`. Do not use PUID/PGID remapping or run the desktop as root. Unraid appdata is commonly owned by `nobody:users` (`99:100`). Setgid on the app's home/workspaces directories makes new children inherit GID `100`; the image sets the session umask to `0002`, supplying group-write for ordinary new files created with the usual `0666` mode. Selkies 2.0.0's [`/etc/container-entrypoint.sh`](https://github.com/selkies-project/selkies/blob/2.0.0/addons/base/container-entrypoint.sh) hands off via `exec s6-svscan /etc/service`, so this umask is inherited by its supervised session ([startup docs](https://docs.selkies.io/latest/components/base-image#how-it-starts)). Local mode reproduction: setgid directory plus umask `0022` produced `0644` with GID `100`; umask `0002` produced `0664` with GID `100`.

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

Selkies Basic Auth and HTTPS are disabled because Pangolin handles browser authentication, access rules, and public HTTPS. No host port is published by default. The desktop's trusted network peers can reach its HTTP listener on container port `8080`; see [Pangolin resources](https://docs.pangolin.net/manage/resources/understanding-resources) and [Selkies settings](https://docs.selkies.io/latest/reference/settings).

DinD runs `privileged: true`: desktop users can control its Docker daemon through the client certificate, and a compromised privileged container can threaten the host. The daemon requires mutual TLS on port `2376`; keep the client certificate protected, do not publish the port, never mount the host Docker socket, and run only on a trusted host.
