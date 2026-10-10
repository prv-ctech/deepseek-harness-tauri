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
desktop = ET.parse(root / "deepseek-harness-desktop.xml").getroot()
dind = ET.parse(root / "deepseek-harness-dind.xml").getroot()

def variables(template):
    return {
        item.attrib["Target"]: item.attrib.get("Default")
        for item in template.findall("./Config[@Type='Variable']")
    }

assert variables(desktop) == {
    "SELKIES_ENABLE_BASIC_AUTH": "false",
    "SELKIES_ENABLE_HTTPS": "false",
    "DOCKER_HOST": "tcp://deepseek-harness-dind:2375",
}
assert variables(dind) == {"DOCKER_TLS_CERTDIR": ""}
assert desktop.findtext("Name") == "deepseek-harness-desktop"
assert desktop.findtext("Network") == "custom:dsh-dind"
assert desktop.findtext("ExtraNetworks") == "dsh-proxy"
assert dind.findtext("Name") == "deepseek-harness-dind"
assert dind.findtext("Network") == "custom:dsh-dind"
assert desktop.find("./Config[@Target='/home/ubuntu']").get("Default") == "/mnt/user/appdata/deepseek-harness/home"
assert desktop.find("./Config[@Target='/workspaces']").get("Default") == "/mnt/user/appdata/deepseek-harness/workspaces"
assert dind.find("./Config[@Target='/var/lib/docker']").get("Default") == "/mnt/user/appdata/deepseek-harness/docker-data"
assert not desktop.findall("./Config[@Type='Port']")
assert not dind.findall("./Config[@Type='Port']")

compose = json.loads(subprocess.check_output(
    ["docker", "compose", "--env-file", ".env.example", "config", "--format", "json"],
    text=True,
))
assert compose["name"] == "deepseek-harness"
assert compose["volumes"]["home"]["name"] == "deepseek-harness_home"
assert compose["volumes"]["workspaces"]["name"] == "deepseek-harness_workspaces"
assert compose["volumes"]["docker-data"]["name"] == "deepseek-harness_docker-data"
PY
