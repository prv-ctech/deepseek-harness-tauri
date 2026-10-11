#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

docker compose --env-file .env.example config --quiet
sh -n tests/container-config.sh
bash -n scripts/latest-app-release.sh
bash -n tests/panel-hidden.sh

for path in .env docs/private-plan.md personal/notes.txt secrets/credentials.json certificate.pem id_rsa.key app.sqlite app.db .agent-teams/archive.json .fallow/graph-cache.bin .codebase-memory/graph.db; do
    git check-ignore --quiet "$path"
done
if git check-ignore --quiet .env.example; then
    echo ".env.example must remain trackable" >&2
    exit 1
fi

python3 - <<'PY'
import json
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path("templates")
desktop = ET.parse(root / "deepseek-harness-tauri.xml").getroot()
dind = ET.parse(root / "deepseek-harness-dind.xml").getroot()

def variables(template):
    return {
        item.attrib["Target"]: item.attrib.get("Default")
        for item in template.findall("./Config[@Type='Variable']")
    }

assert variables(desktop) == {
    "SELKIES_ENABLE_BASIC_AUTH": "false",
    "SELKIES_ENABLE_HTTPS": "false",
    "DOCKER_HOST": "tcp://deepseek-harness-dind:2376",
    "DOCKER_TLS_VERIFY": "1",
    "DOCKER_CERT_PATH": "/certs/client",
}
assert variables(dind) == {
    "DOCKER_TLS_CERTDIR": "/certs",
    "DOCKER_TLS_SAN": "DNS:deepseek-harness-dind",
}
assert desktop.findtext("Name") == "deepseek-harness-tauri"
assert desktop.findtext("Network") == "bridge"
assert desktop.findtext("ExtraNetworks") is None
assert dind.findtext("Name") == "deepseek-harness-dind"
assert dind.findtext("Network") == "bridge"
assert "deepseek-harness-dind" in dind.findtext("Overview", "")
assert "2376" in dind.findtext("Overview", "")
assert desktop.find("./Config[@Target='/home/ubuntu']").get("Default") == "/mnt/cache/appdata/deepseek-harness-tauri/home"
assert desktop.find("./Config[@Target='/workspaces']").get("Default") == "/mnt/cache/appdata/deepseek-harness-tauri/workspaces"
assert dind.find("./Config[@Target='/var/lib/docker']").get("Default") == "/mnt/cache/appdata/deepseek-harness-tauri/docker-data"
assert dind.find("./Config[@Target='/certs']").get("Default") == "/mnt/cache/appdata/deepseek-harness-tauri/docker-certs"
client_certs = desktop.find("./Config[@Target='/certs/client']")
assert client_certs.get("Default") == "/mnt/cache/appdata/deepseek-harness-tauri/docker-certs/client"
assert client_certs.get("Mode") == "ro"
assert not desktop.findall("./Config[@Type='Port']")
assert desktop.find("./Config[@Target='PASSWD']") is None
assert desktop.find("./Config[@Target='PUID']") is None
assert desktop.find("./Config[@Target='PGID']") is None
assert not dind.findall("./Config[@Type='Port']")

compose = json.loads(subprocess.check_output(
    ["docker", "compose", "--env-file", ".env.example", "config", "--format", "json"],
    text=True,
))
assert compose["name"] == "deepseek-harness"
assert compose["volumes"]["home"]["name"] == "deepseek-harness_home"
assert compose["volumes"]["workspaces"]["name"] == "deepseek-harness_workspaces"
assert compose["volumes"]["docker-data"]["name"] == "deepseek-harness_docker-data"
assert compose["networks"]["shared"]["name"] == "your-existing-docker-network"
assert compose["networks"]["shared"]["external"] is True
assert compose["services"]["desktop"]["environment"]["DOCKER_HOST"] == "tcp://deepseek-harness-dind:2376"
assert compose["services"]["desktop"]["environment"]["DOCKER_TLS_VERIFY"] == "1"
assert compose["services"]["desktop"]["environment"]["DOCKER_CERT_PATH"] == "/certs/client"
assert compose["services"]["dind"]["environment"]["DOCKER_TLS_CERTDIR"] == "/certs"
assert compose["services"]["dind"]["environment"]["DOCKER_TLS_SAN"] == "DNS:deepseek-harness-dind"
assert set(compose["services"]["desktop"]["networks"]) == {"shared"}
assert set(compose["services"]["dind"]["networks"]) == {"shared"}
assert compose["services"]["dind"]["networks"]["shared"]["aliases"] == ["deepseek-harness-dind"]
assert {mount["target"]: mount.get("read_only", False) for mount in compose["services"]["desktop"]["volumes"]}["/certs/client"] is True
desktop_cert_mount = next(mount for mount in compose["services"]["desktop"]["volumes"] if mount["target"] == "/certs/client")
dind_mounts = {mount["target"]: mount for mount in compose["services"]["dind"]["volumes"]}
assert dind_mounts["/certs/ca"]["source"] == "docker-certs-ca"
assert dind_mounts["/certs/client"]["source"] == desktop_cert_mount["source"] == "docker-certs-client"
assert compose["services"]["dind"]["healthcheck"]["test"] == ["CMD", "docker", "--host=unix:///var/run/docker.sock", "info"]
assert "2376" in compose["services"]["dind"]["expose"]
assert not compose["services"]["desktop"].get("ports")
assert not compose["services"]["dind"].get("ports")
PY
