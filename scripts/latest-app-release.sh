#!/usr/bin/env bash
set -euo pipefail

readonly repository="dsh-tauri/deepseek-harness-desktop"
readonly api_url="https://api.github.com/repos/${repository}/releases/latest"
architecture="${TARGETARCH:-$(uname -m)}"
case "$architecture" in
  amd64|x86_64) ;;
  *) printf 'latest-app-release: amd64 is required (got %s)\n' "$architecture" >&2; exit 1 ;;
esac

curl --fail --location --silent --show-error \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2022-11-28' \
  "$api_url" |
python3 -c '
import json
import re
import sys

repository = "dsh-tauri/deepseek-harness-desktop"
def reject(reason):
    print("latest-app-release: " + reason, file=sys.stderr)
    raise SystemExit(1)

try:
    release = json.load(sys.stdin)
except (json.JSONDecodeError, UnicodeDecodeError):
    reject("GitHub returned invalid release JSON")
if not isinstance(release, dict):
    reject("GitHub response is not a release object")

tag = release.get("tag_name")
if not isinstance(tag, str) or not re.fullmatch(r"v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag):
    reject("release tag is not a stable semantic version")
if release.get("draft") is not False or release.get("prerelease") is not False:
    reject("latest release is a draft or prerelease")
if release.get("url") != "https://api.github.com/repos/" + repository + "/releases/" + str(release.get("id")):
    reject("release API URL is not from the official repository")
if release.get("html_url") != "https://github.com/" + repository + "/releases/tag/" + tag:
    reject("release page is not from the official repository")

version = tag[1:] if tag.startswith("v") else tag
asset_name = "Deepseek.Harness.Desktop_" + version + "_amd64.deb"
assets = release.get("assets")
if not isinstance(assets, list):
    reject("release assets are missing")
matches = [asset for asset in assets if isinstance(asset, dict) and asset.get("name") == asset_name]
if len(matches) != 1:
    reject("expected exactly one non-Bundle amd64 Debian asset: " + asset_name)
asset = matches[0]
asset_url = "https://github.com/" + repository + "/releases/download/" + tag + "/" + asset_name
if asset.get("browser_download_url") != asset_url:
    reject("asset download URL is not from the official repository")
if not isinstance(asset.get("url"), str) or not re.fullmatch(
    r"https://api\.github\.com/repos/" + re.escape(repository) + r"/releases/assets/\d+",
    asset["url"],
):
    reject("asset API URL is not from the official repository")
digest = asset.get("digest")
if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
    reject("asset has no valid GitHub SHA-256 digest")
if type(asset.get("size")) is not int or asset["size"] <= 0:
    reject("asset size is missing or invalid")

print("tag=" + tag)
print("asset_url=" + asset_url)
print("sha256=" + digest.removeprefix("sha256:").lower())
'