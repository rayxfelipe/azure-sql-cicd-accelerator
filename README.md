# Azure SQL CI/CD accelerator

A private-network-first GitHub template for passwordless Azure SQL releases.
Start from a new private repository, run guided setup, and deploy reviewed SQL
changes through GitHub Actions. No SQL passwords or client secrets.

**Preview:** use isolated resources and synthetic data. Review the
[security policy and documented infrastructure exceptions](SECURITY.md) before
adoption. The distribution repository is build-only; Azure releases belong in
your own private deployment repository.

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
The primary path uses the **GitHub UI** to create the repository and dispatch
workflows, and **PowerShell** for local setup, editing and Git commands.
[Optional CLI alternatives](#optional-cli-alternatives) are separate; do not
dispatch the same workflow through both routes.
If resuming an existing setup, use [Returning later](#returning-later) rather
than creating another repository or overwriting its configuration.

### 1. Check prerequisites

**Before you begin, confirm all four items:**

- [ ] **Tools:** [PowerShell 7.4+](https://learn.microsoft.com/en-us/powershell/scripting/installing-powershell-on-windows),
  [.NET SDK 10](https://dotnet.microsoft.com/en-us/download/dotnet/10.0),
  [Azure CLI with Bicep](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows),
  [GitHub CLI](https://cli.github.com/) and [Git](https://git-scm.com/downloads/win).
  Enable the [OpenSSH client](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)
  for `ssh-keygen`. Use `pwsh`, not Windows PowerShell 5.1.
- [ ] **GitHub access and plan:** access to the source template, repository
  administrator rights on your new copy, and a plan that supports
  environments/branch policies in **private** repositories: personal Pro,
  organization Team, or applicable Enterprise. GitHub Free is insufficient for
  this private deployment flow; do not make the deployment repository public
  as a workaround. Actions and repository self-hosted runners must be allowed.
  See [GitHub environment availability](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).
- [ ] **Azure and SQL setup access:** permission to provision resources and
  assign the required role in the target subscription, plus an Entra SQL
  administrator user/group that the setup operator can use.
  Arrange the [full initial setup permissions](docs/SETUP.md#initial-setup-permissions-versus-routine-releases)
  before starting; routine deployment permissions are not sufficient.
- [ ] **An isolated, approved target:** a new dedicated resource group, permitted
  network ranges/SKUs, sufficient regional VM quota and compatible Azure policies.
  Review the [cost estimate](docs/COST-AND-CLEANUP.md#cost-before-applying) and
  arrange a budget/alert before applying.

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

**Complete both actions:** first create your repository in the GitHub UI, then
clone that new repository using the PowerShell commands below. They are not
alternative ways to do the same thing: the template creates an independent
repository with fresh history; cloning downloads your new repository locally.
Run the clone commands from the parent folder where you want it created, not
inside an existing clone. `YOUR-OWNER` is the GitHub username or organization
that owns your new repository, not your Azure tenant or subscription owner.

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

> **Budget checkpoint:** allow approximately **USD 120-130/month** for the
> starter topology running continuously in West US 2, or **USD 56-65/month**
> with the runner VM deallocated. These November 9, 2026 retail-based planning
> ranges assume 730 hours/month, before taxes, discounts and credits; region,
> sizing and usage change the total. SQL, disk and networking remain billable
> when the VM is deallocated. See the [dated breakdown](docs/COST-AND-CLEANUP.md#cost-before-applying).

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

Under **Settings > Secrets and variables > Actions > Variables**, confirm the
repository variables `SETUP_COMPLETE=true` and `SETUP_IN_PROGRESS=false`.
[Optional CLI checks](#check-setup-readiness) are available below.
On failure, deployments remain disabled but resources may incur charges.
Fix the reported problem and rerun **the same configuration**; never manually
set the completion gate. Preserve `.azure/setup-state.json` and the SSH keys.
See [setup failures](docs/SETUP.md#reruns-and-failures).

**Readiness does not deploy your SQL schema. Continue to step 6.**

### 6. Deploy the initial schema to dev

In **your new private deployment repository > Actions** (not the accelerator
template), select **Database CI and dev deployment > Run workflow**, choose
branch **main**, and run it once.
The [optional CLI equivalent](#dispatch-the-initial-dev-workflow) is separate
from this primary UI path.

Open the newly created run in GitHub. Both `build` **and** `deploy-dev` must
succeed, including **Deploy dev and run SQL smoke tests**. Expect the smoke-test
output to report `PASS` for identity, least privilege, defaults, insert, query
and rollback. Synthetic data is not retained.

If `deploy-dev` is queued, check runner status and
[start the adopter VM](docs/OPERATIONS.md#runner-lifecycle) if needed. If it is
skipped, check setup completion and the selected branch. A green build by itself
does not prove a SQL release. Keep the runner online through step 8.

### 7. Make and release an additive schema change through a PR

Run every Git command in this step in **PowerShell 7 inside your local clone of
the new private deployment repository**. Check the directory and remote before
creating the feature branch:

```powershell
Get-Location
git remote get-url origin
git status --short --branch
git switch main
git pull --ff-only
git switch -c add-customer-note
```

The working tree should be clean before switching branches; do not discard
unrelated changes to force this step. `origin` must name your new repository,
not the accelerator template.

**Edit the following files locally in VS Code on `add-customer-note`.**
Links viewed on the template's GitHub page show template files as references;
open the corresponding files in your local trial checkout instead. Do not edit
the template or make these changes directly on `main`.

In [database/Tables/ServiceRequest.sql](database/Tables/ServiceRequest.sql), add
this nullable column before the existing `Priority` column, retaining the comma:

```sql
    [CustomerNote] NVARCHAR(100) NULL,
```

In [tests/Smoke.sql](tests/Smoke.sql), after the existing missing-table/view
checks and **before `BEGIN TRY`**, add an assertion so the deployment proves the
new column exists in both environments:

```sql
IF COL_LENGTH(N'dbo.ServiceRequest', N'CustomerNote') IS NULL
    THROW 51008, 'CustomerNote column is missing.', 1;
```

**Save both files before continuing.** These snippets are file edits, not SQL
commands to execute manually against Azure SQL. Local validation checks syntax
and builds the project; the workflows execute smoke tests after deployment.

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

If you did not save it, reopen that run under **your repository > Actions** and
copy the number from its URL. Confirm it belongs to your merged change and that
`deploy-dev` and its SQL smoke-test step succeeded; a workflow-level `success`
can also describe an earlier build-only run.
An [optional CLI lookup](#recover-a-dev-run-id) is available below.

### 8. Promote that exact dev artifact to production

In **the same new private deployment repository**, open **Actions > Promote
verified database to production > Run workflow**.
Choose **main** and enter the successful **post-merge dev run ID** from step 7
as `source_run_id`, then run it once.
The [optional CLI equivalent](#dispatch-production-promotion) is available below.

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

### Completion checklist

- [ ] **Setup complete (step 5):** `Setup verified` printed, all four OIDC/SQL
  readiness jobs passed, and the private runner is online.
- [ ] **Initial dev release (step 6):** `build`, `deploy-dev` and SQL smoke tests
  passed; a skipped deployment does not count.
- [ ] **PR validation (step 7):** `build` passed and `deploy-dev` was skipped.
- [ ] **Merged dev release (step 7):** the push-to-main deployment and smoke tests,
  including the new column assertion, passed; save its run URL/ID.
- [ ] **Production promotion (step 8):** source validation, exact-artifact
  deployment and production SQL smoke tests passed; save the promotion URL.

The first checkbox means setup is ready for releases. **All five** mean the
end-to-end happy-path walkthrough passed, not that every production-hardening
or recovery check is complete.

### When you finish

Keep the resources for further testing, or follow
[runner deallocation](docs/OPERATIONS.md#runner-lifecycle) after all jobs finish.
Deallocation still incurs SQL/network/disk charges. To permanently remove the
isolated test environment, review the
[destructive cleanup instructions](docs/COST-AND-CLEANUP.md#isolated-cleanup).

### Returning later

1. Reopen **the same local deployment repository** in VS Code and use PowerShell
   7 from its root. Keep `config/setup.json`, `.azure/setup-state.json` and the
   SSH keys; do not recreate or overwrite them merely to resume.
2. Restore the terminal settings and repository name, and confirm the remote
   still points to your private copy:

   ```powershell
   $ErrorActionPreference = 'Stop'
   $PSNativeCommandUseErrorActionPreference = $true
   $Repository = (Get-Content config\setup.json -Raw | ConvertFrom-Json).repository
   git remote get-url origin
   ```

   Renew GitHub/Azure sign-in if necessary, using the original configured
   tenant/subscription and repository. Do not change configuration to match an
   unintended signed-in account.
3. If deallocated, **start the existing runner VM** before deployment or
   verification. Wait for **Settings > Actions > Runners** in your repository to
   show it **Idle/online**. See [runner lifecycle](docs/OPERATIONS.md#runner-lifecycle).
   Starting the VM resumes compute charges; completed setup does not need
   `-Apply` again just because its VM was deallocated.
4. Resume from the appropriate completion checkpoint. If a dev artifact expired
   after **14 days**, dispatch a fresh main-branch dev release as in step 6,
   verify deployment/smoke tests, and promote that new run as in step 8.
   Do not repeat the `CustomerNote` edit if it is already merged, or rebuild
   production separately. For incomplete setup, follow
   [same-configuration recovery](docs/SETUP.md#reruns-and-failures).

## Optional CLI alternatives

These are alternatives to the GitHub UI actions above, not additional steps.
Use PowerShell in your new deployment repository and ensure `$Repository`
identifies that private copy. If needed, restore it using
[Returning later](#returning-later). Use **one** dispatch method per run.

### Check setup readiness

```powershell
gh variable list --repo $Repository
gh api "repos/$Repository/actions/runners" --jq '.runners[] | {name,status,busy}'
```

Require `SETUP_COMPLETE=true`, `SETUP_IN_PROGRESS=false` and an online runner;
never set the variables manually to bypass readiness.

### Dispatch the initial dev workflow

```powershell
gh workflow run database-ci.yml --repo $Repository --ref main
```

Open the run in your repository's Actions page and apply the success checks
from [step 6](#6-deploy-the-initial-schema-to-dev). To open the repository in a
browser, use `gh repo view $Repository --web`; this command does not dispatch a run.

### Recover a dev run ID

```powershell
gh run list --repo $Repository --workflow database-ci.yml --branch main --event push --limit 5 --json databaseId,displayTitle,status,conclusion,url
```

For step 7, select the post-merge run for your change. Use its `databaseId` only
after opening its `url` and confirming `deploy-dev` and SQL smoke tests passed.
This lookup filters to push events; manual step-6 runs are not listed.

### Dispatch production promotion

```powershell
$DevRunId = 'YOUR-SUCCESSFUL-POST-MERGE-DEV-RUN-ID'
gh workflow run promote-production.yml --repo $Repository --ref main -f "source_run_id=$DevRunId"
```

Use the validated dev run ID, not a PR run, displayed run number or artifact ID.
Apply the success checks from [step 8](#8-promote-that-exact-dev-artifact-to-production),
including any configured production approval.

## Working with the accelerator

- [Setup and reruns](docs/SETUP.md)
- [Releases, permissions and operations](docs/OPERATIONS.md)
- [Costs and isolated cleanup](docs/COST-AND-CLEANUP.md)
- [Validation and fresh-repository acceptance](docs/VALIDATION.md)
- [Security policy and preview exceptions](SECURITY.md)
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
**not** proof that a fresh accelerator environment passed. A separate
fresh-repository Windows walkthrough subsequently passed setup, dev deployment,
a schema-change PR and same-artifact production promotion; see the
[dated acceptance evidence and remaining checks](docs/VALIDATION.md#fresh-repository-walkthrough-november-9-2026).
That live walkthrough predates the subsequent pinned Action upgrades; hosted
builds and static checks do not replace a new Azure acceptance run after upgrades.

Version 1 supports **GitHub.com private repositories and Azure public cloud**,
fixed `dev`/`production` environment names, Ubuntu 24.04 x64 and one persistent
dedicated runner. Names, region, repository, identities, databases and network
ranges are adopter-specific. The two Basic databases and shared runner are
starter sizing, not a highly available production architecture.

Protect `main`, restrict repository write access and configure production
reviewers where your GitHub plan permits. A manual dispatch alone is not
two-person approval.

### Could this use a Deploy to Azure button?

Yes, for the Azure infrastructure portion. Microsoft's
[Deploy to Azure button](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/deploy-to-azure-button)
loads a remotely accessible **ARM JSON** template, not a Bicep source file.
Subscription scope is supported, so this topology could be compiled and
published for that path. The current private source repository would need an
accessible template-hosting solution.

However, a standard portal deployment does not by itself create/configure your
private GitHub repository, establish repository-specific OIDC subjects, register
the runner, bootstrap SQL administrator-authorized grants or verify the release
gates. Those steps still require the appropriate GitHub and Entra permissions
and coordinated onboarding. An infrastructure-only button could leave billable
resources with CI/CD incomplete.

Version 1 therefore keeps the guided setup command as its complete onboarding
path. No portal button is implemented. Adding one would require a tested handoff
to that setup flow, including configuration/state and rerun ownership checks,
not just a badge linking to the infrastructure template.
