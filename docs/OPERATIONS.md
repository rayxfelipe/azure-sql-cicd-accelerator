# Releases and operations

Use this reference after [setup](SETUP.md) and
[deployment validation](VALIDATION.md). For your first release, follow
[quick start steps 6-8](../README.md#6-deploy-the-initial-schema-to-dev).
Operate only your own private deployment repository and its resources.

## Pull requests and dev releases

| Action | Result |
|---|---|
| Open a PR targeting `main` | Hosted validation/build with `contents: read`; no Azure OIDC token, private runner or SQL deployment. |
| Merge a change covered by the CI workflow, or dispatch CI on `main` | Builds the release artifact, then deploys dev only if setup is complete and not in progress. The private runner uses a repository-specific label. |

SQL publication blocks possible data loss, retains objects absent from source,
and does not manage security principals, permissions or database options.
Smoke tests check identity/permissions and sample schema behavior, then roll back
synthetic data on success or failure and confirm it is gone.
Existing databases require a reviewed schema import/baseline and migration
strategy; do not copy deployment users into the SQL project.

## Production promotion

In **Actions > Promote verified database to production**, select `main` and enter
the successful dev CI run ID as `source_run_id`. The validator requires:

- A completed successful `database-ci.yml` run from this repository.
- `main` branch and a trusted `push` or `workflow_dispatch` event.
- An explicitly successful `deploy-dev` job, not skipped/failed/cancelled.
- Exactly one unexpired `database-release` artifact.

Confirm `validate-source`, `deploy-production` and production smoke tests pass.
The private production job downloads that **artifact ID from that source run**,
including the DACPAC and scripts; it does not rebuild or check out new SQL source.
Save source/promotion run URLs, commit and artifact ID. If the artifact expired
after 14 days, create a new successful dev release before promoting.

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

These identifiers are configuration, not credentials, but can reveal environment
details. Setup does not store Azure client secrets, SQL passwords or long-lived
runner registration tokens. Never manually set `SETUP_COMPLETE=true` to bypass
a failed setup; follow [setup recovery](SETUP.md#reruns-and-failures).

## Runner lifecycle

Keep the VM running during setup, deployment and verification. Run the following
in the same PowerShell 7 session from your original setup checkout.

**Start the existing VM** using your saved state:

```powershell
$state = Get-Content .azure\setup-state.json -Raw | ConvertFrom-Json
az vm start --subscription $state.deployment.subscriptionId `
  --resource-group $state.deployment.resourceGroup --name $state.deployment.runnerVm
```

**Wait for the runner to be idle/online** before dispatching:

```powershell
gh api "repos/$($state.configuration.repository)/actions/runners" `
  --jq '.runners[] | {name,status,busy}'
```

**Deallocate only after all deployment/verification jobs finish** and no queued
release needs the runner:

```powershell
az vm deallocate --subscription $state.deployment.subscriptionId `
  --resource-group $state.deployment.resourceGroup --name $state.deployment.runnerVm
```

Confirm **Stopped (deallocated)**; shutting down Linux alone can leave compute
billed. SQL, disk and network charges continue; see [costs](COST-AND-CLEANUP.md).
An offline runner causes queued jobs; start it rather than bypassing private DNS.
No inbound SSH is required; administrators use protected Azure Run Command.

If the original setup checkout is unavailable, retrieve its saved state/key pair
from the setup operator rather than guessing resource names. Do not run these
commands against the template maintainer's or baseline VM.

For permanent removal, follow [isolated cleanup](COST-AND-CLEANUP.md#isolated-cleanup).
