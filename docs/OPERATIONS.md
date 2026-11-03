# Releases and operations

## Pull requests and dev releases

PRs targeting `main` run on GitHub-hosted Windows runners with `contents: read`
only. They validate PowerShell/JSON, run regression tests, compile Bicep and
build the DACPAC. They never run on the private runner and cannot request Azure
OIDC tokens.

Trusted pushes to `main` or manual main-branch CI dispatches use the same build
and artifact. Dev deployment runs only when setup is complete and not in
progress. Repository-ID-specific runner labels isolate repositories. SQL
publication blocks possible data loss, retains objects absent from source and
does not manage security principals, permissions or database options.

Smoke tests assert database/user identity, absence of `db_owner`, the sample
table/view, the Priority default and query behavior. They roll back synthetic
data on both success and failure, then confirm it is gone.

## Production promotion

Dispatch `promote-production.yml` from `main` with the successful dev CI run ID.
The hosted validator requires:

- A completed successful `database-ci.yml` run from this repository.
- `main` branch and a trusted `push` or `workflow_dispatch` event.
- An explicitly successful `deploy-dev` job, not skipped/failed/cancelled.
- Exactly one unexpired `database-release` artifact.

The private production job downloads that **artifact ID from that source run**,
including its DACPAC and deployment scripts. It does not rebuild or check out
new SQL source. Artifact retention is 14 days; create another verified dev
release if the artifact has expired.

Set production required reviewers and prevent self-review where supported.
Protect `main` with reviewed changes and required CI. The default manual dispatch
is **not** an approval policy and this shared persistent runner is **not** strong
dev/production compute isolation. Evaluate dedicated/ephemeral environment
runners and production database tiers before using this for regulated workloads.

## Variables

Repository variables:

| Variable | Meaning |
|---|---|
| `SETUP_COMPLETE` | Releases allowed only when exactly `true`. |
| `SETUP_IN_PROGRESS` | Releases blocked while exactly `true`. |
| `RUNNER_LABEL` | `sql-private-<repository ID>`; never a shared demo label. |

Environment variables in `dev` and `production`:
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `SQL_SERVER_FQDN`,
`SQL_DATABASE_NAME`, `SQL_DEPLOYMENT_USER`, `SQL_PRIVATE_ENDPOINT_CIDR`,
`EXPECTED_OIDC_SUBJECT`.

These identifiers are configuration, not credentials. Setup does not store
Azure client secrets, SQL passwords or long-lived runner registration tokens.
Never manually set `SETUP_COMPLETE=true` to bypass a failed setup.

## Runner lifecycle

Keep the VM running during setup, deployment and verification. To start or stop
the **adopter's** VM, load the local setup state:

```powershell
$state = Get-Content .azure\setup-state.json -Raw | ConvertFrom-Json
az vm start --subscription $state.deployment.subscriptionId `
  --resource-group $state.deployment.resourceGroup --name $state.deployment.runnerVm
gh api "repos/$($state.configuration.repository)/actions/runners" `
  --jq '.runners[] | {name,status,busy}'
# Only after all deployments finish:
az vm deallocate --subscription $state.deployment.subscriptionId `
  --resource-group $state.deployment.resourceGroup --name $state.deployment.runnerVm
```

Deallocation stops compute billing, not disk/NAT/IP/SQL/private-endpoint charges.
An offline runner causes queued jobs; start it rather than bypassing private DNS.
No inbound SSH is required; administrators use protected Azure Run Command.

Do not copy baseline contained users into the SQL project. Existing databases
require a reviewed schema import/baseline and migration strategy; the sample
project is intended for fresh isolated databases.
