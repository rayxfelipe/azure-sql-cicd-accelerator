#!/usr/bin/env bash
set -euo pipefail
: "${RunnerToken:?Protected runner registration token is required.}"
: "${Repository:?Repository is required.}"
: "${RunnerName:?RunnerName is required.}"
: "${RunnerLabel:?RunnerLabel is required.}"
: "${SqlServerFqdn:?SqlServerFqdn is required.}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y ca-certificates curl git gnupg jq libicu74
package=$(mktemp --suffix=.deb)
archive=$(mktemp --suffix=.tar.gz)
trap 'rm -f "$package" "$archive"' EXIT
curl --fail --silent --show-error --location https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -o "$package"
dpkg -i "$package"
curl --fail --silent --show-error https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor --yes -o /usr/share/keyrings/microsoft-azure-cli.gpg
echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-azure-cli.gpg] https://packages.microsoft.com/repos/azure-cli/ noble main' > /etc/apt/sources.list.d/azure-cli.list
apt-get update -qq
apt-get install -y powershell dotnet-sdk-10.0 azure-cli
pwsh -NoProfile -Command 'Install-Module SqlServer -RequiredVersion 22.4.5.1 -Scope AllUsers -Force -AllowClobber -ErrorAction Stop'
if ! id githubrunner >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash githubrunner
fi
install -d -o githubrunner -g githubrunner /opt/github-runner
cd /opt/github-runner
if [ -f .runner ]; then
  test "$(jq -r .gitHubUrl .runner)" = "https://github.com/$Repository" || {
    echo 'Existing runner belongs to a different repository; refusing to replace it.' >&2
    exit 1
  }
  test "$(jq -r .agentName .runner)" = "$RunnerName" || {
    echo 'Existing runner name differs; use the original setup configuration.' >&2
    exit 1
  }
else
  curl --fail --silent --show-error --location https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-linux-x64-2.338.2.tar.gz -o "$archive"
  echo "baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40  $archive" | sha256sum --check
  tar xzf "$archive"
  chown -R githubrunner:githubrunner /opt/github-runner
  ./bin/installdependencies.sh
  runuser -u githubrunner -- ./config.sh --url "https://github.com/$Repository" --token "$RunnerToken" --name "$RunnerName" --labels "$RunnerLabel" --unattended --work _work
fi
if [ ! -f .service ]; then
  ./svc.sh install githubrunner
fi
./svc.sh start
getent hosts "$SqlServerFqdn"
systemctl is-active "$(cat .service)"
echo 'Private runner initialization complete.'
