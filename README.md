# Azure SQL CI/CD accelerator

A private-network-first GitHub template for passwordless Azure SQL releases.
Start from a new private repository, run guided setup, and deploy reviewed SQL
changes through GitHub Actions. No SQL passwords or client secrets.

## Architecture

```text
PR -> GitHub-hosted validation and DACPAC build (no Azure permissions)
main -> immutable database-release artifact -> dev environment
                                               |
                                  dedicated private Linux runner
                                               |
                                  repository-specific GitHub OIDC
                                               |
                                  Entra token -> SQL private endpoint
                                               |
                                  deploy DACPAC -> rollback smoke tests

Manual promotion -> validate successful dev job + exact unexpired artifact ID
                 -> production environment -> separate deployment identity
                 -> same DACPAC and scripts, no rebuild -> rollback smoke tests
```

The runner has no public IP, no attached Azure identity, and denies all inbound
traffic. NAT provides outbound access. SQL is Entra-only with public access
disabled. Deployment identities receive resource-group Reader plus explicit
contained-user grants, not SQL administrator or `db_owner`.

## Quick start

This walkthrough takes a **fresh private repository** through Azure setup, a
first dev release, an additive schema PR and same-artifact production promotion.
Use synthetic data and a new resource group, not existing production databases.
**Only step 5 provisions Azure resources and starts ongoing Azure charges.**
GitHub usage charges may apply separately.

Commands below use **PowerShell 7.4+ on Windows**. Run them in the same terminal,
from your new repository root unless told otherwise. Replace all `YOUR-...`
placeholders. Stop at any failed check; do not bypass setup gates.
If you open a new terminal, return to your cloned repository root. Once
`config/setup.json` exists, restore `$Repository` with
`$Repository = (Get-Content config\setup.json -Raw | ConvertFrom-Json).repository`.

### 1. Check prerequisites

- Install [PowerShell 7](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows),
  [.NET SDK 10](https://dotnet.microsoft.com/en-us/download/dotnet/10.0),
  [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows),
  [GitHub CLI](https://cli.github.com/) and [Git](https://git-scm.com/downloads/win).
  Enable the [OpenSSH client](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)
  for `ssh-keygen`. Use `pwsh`, not Windows PowerShell 5.1.
- You need repository administrator access and a GitHub plan that supports
  environments/branch policies in **private** repositories: personal Pro,
  organization Team, or applicable Enterprise. GitHub Free is insufficient for
  this private deployment flow; do not make the deployment repository public
  as a workaround. See [GitHub environment availability](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).
- Arrange the [initial Azure and SQL setup permissions](docs/SETUP.md#initial-setup-permissions-versus-routine-releases).
  Confirm regional VM quota, Azure policy compatibility and the
  [cost estimate](docs/COST-AND-CLEANUP.md) before applying.

In a PowerShell 7 terminal:

```powershell
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$PSVersionTable.PSVersion
Get-Command pwsh, dotnet, az, gh, git, ssh-keygen
dotnet --list-sdks
az bicep version
```

**Expected:** all commands exist, PowerShell is 7.4+ and a `10.0.*` SDK is listed.
If Bicep is missing, run `az bicep install`, then repeat its version check.

### 2. Create YOUR deployment repository

On the template's GitHub page, select **Use this template > Create a new
repository**. Choose your account/organization, a unique name such as
`azure-sql-cicd-trial`, and **Private**. Keep the default branch `main`; copying
all branches is unnecessary. A private template requires access to its source.

**Do not clone the accelerator source directly, fork it, or reuse its runner.**
The customer repository needs its own GitHub settings, OIDC trust and Azure
resources. These settings are not copied from the template.

```powershell
gh auth login --hostname github.com
gh auth status --hostname github.com
$Repository = 'YOUR-OWNER/azure-sql-cicd-trial'
gh repo clone $Repository
Set-Location ($Repository.Split('/')[1])
git remote get-url origin
gh repo view $Repository --json nameWithOwner,isPrivate,defaultBranchRef
```

If prompted, allow GitHub CLI to configure Git authentication. Your credentials
must permit private repository, environment, runner, variable, workflow and OIDC
administration; complete organization SSO authorization if required.
See [authentication troubleshooting](docs/SETUP.md#authentication-and-common-blockers).

**Expected:** `origin` names **your** new repository, `isPrivate` is `true`, and
the default branch is `main`. Open
[the workspace file](Azure%20SQL%20CI-CD%20Accelerator.code-workspace) from this
new checkout in VS Code; do not continue from the template's original checkout.
If GitHub Actions is disabled, enable it under **Settings > Actions > General**.
No Azure provisioning happens when you create or clone the repository.

### 3. Select your tenant/subscription and configure setup

```powershell
$TenantId = 'YOUR-TENANT-ID'
$SubscriptionId = 'YOUR-SUBSCRIPTION-ID'
az login --tenant $TenantId
az account set --subscription $SubscriptionId
az account show --query '{subscription:name,subscriptionId:id,tenantId:tenantId}' --output table
Copy-Item config\setup.example.json config\setup.json
```

Verify the displayed tenant/subscription are the intended isolated target.
Edit `config/setup.json` in VS Code:

| Field | Set to |
|---|---|
| `subscriptionId` | The selected subscription ID, not the tenant ID. |
| `repository` | Your exact `$Repository` (`owner/name`), **not the source template**. |
| `administratorObjectId`, `administratorLogin` | The setup operator's Entra user object ID and display name **in this tenant**, or a group of which that operator is a member. Set `administratorPrincipalType` accordingly. [How to find these](docs/SETUP.md#finding-the-sql-setup-administrator). |
| `resourceGroupName` | A new dedicated group, for example `rg-sqlcicd-trial`. Never a baseline/shared resource group. |
| `resourcePrefix` | A unique lowercase alphanumeric prefix such as `sqltrial`; use the same value throughout the test. |
| `location`, `runnerVmSize` | A permitted region and available Ubuntu x64 VM size; defaults are starting points, not a capacity guarantee. |
| Network ranges | Nonoverlapping private subnets inside the VNet; confirm no conflict with your organization's networks. |

Keep the remaining settings unless your environment requires changes.
Configuration, SSH keys and local state are Git-ignored; never add them to a PR.
Do not overwrite this configuration on subsequent runs.

### 4. Validate locally and preview (no provisioning)

```powershell
.\scripts\Test-Accelerator.ps1
.\scripts\Setup-Accelerator.ps1
```

**Expected:** regression tests, DACPAC build and Bicep compilation pass. The setup
command shows an Azure **what-if** targeting only your new resource group and
finishes with **Preview only**. It generates local parameters/SSH keys but does
not provision Azure resources or change GitHub settings.

Before applying, wait for any initial main-branch CI run in your new repository
to finish. If one ran before setup, its `build` should pass and `deploy-dev`
should be **skipped**. A skipped deployment at this point is intentional.
If no initial run was created by template generation, the local validation above
is sufficient to proceed.

### 5. Apply setup (creates billable Azure resources)

Review the what-if, [costs and cleanup](docs/COST-AND-CLEANUP.md), then explicitly
opt in:

```powershell
.\scripts\Setup-Accelerator.ps1 -Apply
```

Keep the terminal open until completion. Setup provisions SQL databases,
identities and private networking; initializes/starts the private runner;
bootstraps SQL grants; and configures GitHub environments and variables. It then
prints a link to **Verify accelerator setup**. If your environments require
approval, approve the verification jobs in GitHub during this wait.

**Expected:** all four jobs **`OIDC (dev)`**, **`OIDC (production)`**,
**`SQL (dev)`**, **`SQL (production)`** succeed, and the script prints
**Setup verified**. A green run with skipped verification jobs is not success.
Check your repository's **Settings > Actions > Runners**: its private runner
must be **Idle/online**, not Offline.

```powershell
gh variable list --repo $Repository
gh api "repos/$Repository/actions/runners" --jq '.runners[] | {name,status,busy}'
```

`SETUP_COMPLETE` must be `true` and `SETUP_IN_PROGRESS` must be `false`.
On failure, deployments remain disabled but resources may incur charges.
Fix the reported problem and rerun **the same configuration**; never manually
set the completion gate. Preserve `.azure/setup-state.json` and the SSH keys.
See [setup failures](docs/SETUP.md#reruns-and-failures).

**Readiness does not deploy your SQL schema. Continue to step 6.**

### 6. Deploy the initial schema to dev

In **your repository > Actions**, select **Database CI and dev deployment >
Run workflow**, choose branch **main**, and run it. CLI equivalent:

```powershell
gh workflow run database-ci.yml --repo $Repository --ref main
```

Open the newly created run in GitHub. Both `build` **and** `deploy-dev` must
succeed, including **Deploy dev and run SQL smoke tests**. Expect the smoke-test
output to report `PASS` for identity, least privilege, defaults, insert, query
and rollback. Synthetic data is not retained.

If `deploy-dev` is queued, check runner status and
[start the adopter VM](docs/OPERATIONS.md#runner-lifecycle) if needed. If it is
skipped, check setup completion and the selected branch. A green build by itself
does not prove a SQL release. Keep the runner online through step 8.

### 7. Make and release an additive schema change through a PR

From your new repository checkout:

```powershell
git status --short --branch
git switch main
git pull --ff-only
git switch -c add-customer-note
```

The working tree should be clean before switching branches; do not discard
unrelated changes to force this step.

In [the sample table](database/Tables/ServiceRequest.sql), add this nullable
column before the existing `Priority` column, retaining the comma:

```sql
    [CustomerNote] NVARCHAR(100) NULL,
```

In [the smoke test](tests/Smoke.sql), after the existing missing-table/view checks
and **before `BEGIN TRY`**, add an assertion so the deployment proves the new
column exists in both environments:

```sql
IF COL_LENGTH(N'dbo.ServiceRequest', N'CustomerNote') IS NULL
    THROW 51008, 'CustomerNote column is missing.', 1;
```

```powershell
.\scripts\Test-Accelerator.ps1
git add -- database\Tables\ServiceRequest.sql tests\Smoke.sql
git diff --cached --check
git commit -m "Add nullable CustomerNote column and smoke assertion"
git push --set-upstream origin add-customer-note
gh pr create --repo $Repository --base main --head add-customer-note --web
```

Complete the repository's PR template in the browser. Wait for PR validation:
`build` must pass and `deploy-dev` must be **skipped**; PRs never deploy or use
the private runner. Review and merge the PR following your branch protection
rules. Do not select the PR run for production.

After merging, open the new **push-to-main** CI run. Require `build` and
`deploy-dev` to pass again, including the new column assertion. Save the **run
ID**: it is the numeric value after `/actions/runs/` in the run URL, **not** the
displayed run number, job ID or artifact ID.

### 8. Promote that exact dev artifact to production

Open **Actions > Promote verified database to production > Run workflow**.
Choose **main** and enter the successful **post-merge dev run ID** from step 7
as `source_run_id`. CLI equivalent:

```powershell
$DevRunId = 'YOUR-SUCCESSFUL-POST-MERGE-DEV-RUN-ID'
gh workflow run promote-production.yml --repo $Repository --ref main -f "source_run_id=$DevRunId"
```

Approve deployment if a production reviewer gate is configured.
**Expected:** `validate-source` and `deploy-production` both pass. The validator
summary records the source commit/run and artifact ID; the production job
downloads that ID and publishes it without rebuilding. Its SQL smoke tests,
including the new `CustomerNote` assertion, must pass.

The artifact expires after 14 days. If expired, create a new successful
main-branch dev release and promote that new run; do not rebuild production
separately. Save both run URLs, source commit and artifact ID as your evidence.

**You have completed the happy-path customer test when steps 5-8 all pass.**
Before real production use, enforce reviewed `main` changes and production
approvals where supported; setup creates main-only environments, not branch
protection or two-person approval. Rerun/recovery/cleanup acceptance and broader
production hardening remain separate [release checks](docs/VALIDATION.md).

### When you finish

Keep the resources for further testing, or follow
[runner deallocation](docs/OPERATIONS.md#runner-lifecycle) after all jobs finish.
Deallocation still incurs SQL/network/disk charges. To permanently remove the
isolated test environment, review the
[destructive cleanup instructions](docs/COST-AND-CLEANUP.md#isolated-cleanup).

## Working with the accelerator

- [Setup and reruns](docs/SETUP.md)
- [Releases, permissions and operations](docs/OPERATIONS.md)
- [Costs and isolated cleanup](docs/COST-AND-CLEANUP.md)
- [Validation and fresh-repository acceptance](docs/VALIDATION.md)
- [MIT license](LICENSE)

Local validation (does not deploy anything):

```powershell
.\scripts\Test-Accelerator.ps1
```

Change [the SQL project](database/Database.sqlproj) through a PR. After setup,
merging to `main` deploys dev. Dispatch **Promote verified database to production**
with the successful dev run ID to reuse its exact artifact.

## Scope and honest status

This is a generalized accelerator derived from a working private demonstration,
not a replacement for that baseline. Its historical deployment evidence is
**not** proof that a fresh accelerator environment passed.

Version 1 supports **GitHub.com private repositories and Azure public cloud**,
fixed `dev`/`production` environment names, Ubuntu 24.04 x64 and one persistent
dedicated runner. Names, region, repository, identities, databases and network
ranges are adopter-specific. The two Basic databases and shared runner are
starter sizing, not a highly available production architecture.

Protect `main`, restrict repository write access and configure production
reviewers where your GitHub plan permits. A manual dispatch alone is not
two-person approval. Deploy-to-Azure buttons are intentionally omitted:
infrastructure provisioning is only one part of CI/CD onboarding.
