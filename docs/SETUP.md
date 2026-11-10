# Guided setup

Start with the [README quick start](../README.md#quick-start).
Use this reference for permissions, configuration and recovery.
Run commands locally in PowerShell 7.4+ from your private deployment repository.

## Before running

- Create a new **private** GitHub.com repository from the template. Its default
  branch must be `main`, include the three deployment workflows, and match the
  configured `repository` and local `origin`.
- Check the [tools and access prerequisites](../README.md#1-check-prerequisites),
  including private-repository environment/branch-policy support. GitHub Actions
  and repository self-hosted runners must be allowed.
- Select a new dedicated Azure public-cloud resource group, approved region,
  network ranges and Ubuntu/SQL SKUs, with sufficient VM quota. Never target a
  baseline, shared group or another adopter's resources.
- Review the what-if and [costs](COST-AND-CLEANUP.md#cost-before-applying).
  Finish or deliberately cancel main-branch CI/promotion runs first; only one
  setup/cleanup operation may run for a repository at a time.

## Initial setup permissions versus routine releases

| Actor | Required access |
|---|---|
| Setup operator, Azure control plane | Create a subscription-scope deployment and dedicated resource group; provision SQL, identities, networking and VM; assign Reader at that group; register required providers; run/delete protected VM Run Commands. |
| Setup operator, SQL | Be the configured Entra SQL administrator, or a member of its configured Entra group, to create contained users and grant permissions. |
| Setup operator, GitHub | Repository administrator; CLI token with repository/workflow/environment, runner, variable and OIDC customization access. Organization SSO/policies may also apply. |
| Routine dev identity | Reader on the dedicated resource group; explicit SQL database creation/definition grants and dbo schema deployment/DML grants in dev only. |
| Routine production identity | Same limited access, but contained-user grants in production only; a different OIDC identity. |
| Runner VM | No Azure managed identity, no inbound public access, no SQL administrator permissions. |

A temporary subscription Owner assignment is a **broad setup option**, not a
release requirement. Have your platform team arrange narrower deployment/group
creation, resource provisioning, provider registration and scoped role-assignment
permissions where appropriate (for example Role Based Access Control Administrator
on the dedicated group for Reader assignments). Remove temporary elevation after
setup. Never grant deployment identities Contributor, SQL administrator or `db_owner`.

## Finding the SQL setup administrator

Use the Entra identity that is actually running `az login` for the target tenant.
For an interactive user setup, after selecting your tenant/subscription:

```powershell
az account show --query '{subscriptionId:id,tenantId:tenantId}' --output table
az ad signed-in-user show --query '{objectId:id,displayName:displayName}' --output json
```

Put `objectId` into `administratorObjectId`, `displayName` into
`administratorLogin`, and use `administratorPrincipalType: "User"`.
For a guest account, use the guest's object ID **in the target tenant**, not its
home-tenant ID. If Microsoft Graph lookup is blocked by policy, obtain those
values from the target tenant's Microsoft Entra **Users** page or your tenant
administrator; do not substitute a subscription ID or an application's client ID.

Alternatively, have your platform team provide an Entra group's object ID and
display name, use `administratorPrincipalType: "Group"`, and ensure the signed-in
setup operator is a member. The deployment identities created by Bicep must
**not** be chosen as SQL administrator.

## Configuration

Copy [the example](../config/setup.example.json) to `config/setup.json`.
This local file, SSH keys, generated parameters and setup state are Git-ignored.

| Setting | Choose |
|---|---|
| `subscriptionId`, `repository` | Your explicit subscription and exact `owner/repository`, matching this checkout's `origin`. |
| `location`, `resourceGroupName` | An approved region and new dedicated group. Existing groups require ownership tags for this accelerator **and** your repository. |
| `resourcePrefix` | 3-16 lowercase letters/digits, starting with a letter. Names derive from it; the SQL server also includes a uniqueness suffix. |
| `administratorObjectId`, `administratorLogin`, `administratorPrincipalType` | The SQL setup administrator user/group in the target tenant, not a deployment identity. |
| `runnerVmSize`, `runnerAdminUsername` | An approved Ubuntu x64 VM size (default B2s v2) and non-reserved Linux administrator name. This is separate from the `githubrunner` service account and does not enable inbound SSH. |
| `vnetAddressPrefix`, `runnerSubnetPrefix`, `privateEndpointSubnetPrefix` | Network-aligned RFC1918 IPv4 ranges. Subnets must be inside the VNet, separate and non-overlapping; also check overlap with organizational networks. |

Defaults are starter values, not a quota, capacity or policy guarantee.

## Preview and apply

```powershell
az login --tenant 'YOUR-TENANT-ID'
az account set --subscription 'YOUR-SUBSCRIPTION-ID'
gh auth login
.\scripts\Setup-Accelerator.ps1 -ConfigurationPath config\setup.json
.\scripts\Setup-Accelerator.ps1 -ConfigurationPath config\setup.json -Apply
```

Preview validates input, reads repository/resource-group state, generates a local
SSH key and parameter file, and runs Azure what-if. It does **not** change GitHub
settings or provision Azure resources. `-Apply` is explicit consent to the shown
topology, GitHub configuration changes and ongoing charges.

Apply performs five stages:

1. Saves recovery state, disables releases, and creates main-only
   `dev`/`production` environments. Existing reviewers/wait timers are preserved;
   incompatible branch policies fail rather than weaken.
2. Configures OIDC for **your repository only**, using `repository_id,context`
   claims and environment-specific trust. Incompatible custom policies are rejected.
3. Provisions infrastructure, sets Azure/SQL variables and a repository-specific
   runner label, then starts and initializes the VM using protected Run Command.
4. Uses a short-lived setup-administrator SQL token to create the two contained
   users and explicit grants through the private VM. Mismatched users are rejected.
5. Dispatches `verify-setup.yml` to check OIDC claims, private DNS/TCP, SQL identity
   and grants. Releases are enabled only when all four OIDC/SQL jobs succeed,
   never when skipped. Readiness does not change schema or business data.

After `Setup verified`, continue with [quick start step 6](../README.md#6-deploy-the-initial-schema-to-dev)
for the initial schema, then [validate your deployment](VALIDATION.md).

## Reruns and failures

1. Keep the **same configuration**, `.azure/setup-state.json` and SSH key pair.
   Do not edit saved targets or discard state to force a rerun.
2. Fix the reported error, finish/cancel blocking main-branch runs, then rerun the
   same `-Apply` command. Setup reuses owned resources, preserves runner metadata
   and environment protections, and refuses mismatched SQL users/foreign runners.
3. If verification reaches its 30-minute wait limit, inspect the linked workflow,
   approval requests and runner status. A missing/stale registration requires
   deliberate runner repair, not deletion of another runner.
4. If cleanup also fails, inspect the reported Run Command name or protected local
   request path. Correct permissions and remove only the named leftover item.
   Execution and cleanup failures are both reported; neither means setup succeeded.

Failed setup leaves releases disabled but resources may still incur charges.
Retained outputs/verification URLs are recovery diagnostics, not current readiness.
Keep local state and unredacted diagnostics private. If state is missing, recover
the original setup checkout/state from its operator; do not guess resource names.
For an already-completed setup with a stopped VM, use
[runner lifecycle](OPERATIONS.md#runner-lifecycle), not setup again.

## Authentication and common blockers

| Symptom | Check / action |
|---|---|
| Customer repository not found | Sign into the correct GitHub account, set `repository` to your new private copy, and verify its `origin`. The public source template is not the deployment target. |
| GitHub API 403 / environment creation unavailable | Verify repository admin rights, organization SSO, token permissions, Actions policies and the GitHub plan's private-environment support. Do not switch to a public deployment repository to bypass this. |
| Git push reports insufficient OAuth scope | For a GitHub CLI OAuth login, use `gh auth refresh --hostname github.com --scopes repo,workflow`, then reauthorize organization SSO as required. Fine-grained tokens/app credentials need equivalent permitted operations; an OAuth refresh does not repair those credentials. Never paste tokens into source/config. |
| Git commit reports an unknown author identity | Set `git config user.name "YOUR-NAME"` and `git config user.email "YOUR-APPROVED-COMMIT-EMAIL"` inside the customer repository, then retry. Use your organization's approved commit identity. |
| Azure permission or provider-registration failure | Confirm the selected tenant/subscription and ask the platform team to provide the setup permissions above. Routine deployment identities are not setup operators. |
| Entra SQL bootstrap rejects the operator | Verify the configured administrator user/group is in the target tenant and the signed-in operator is that user/a member. Renew `az login` if group membership changed. |
| Windows reports `The command line is too long` | Older copies need the file-backed Run Command transport in `scripts/Common.ps1`. Review the [transport fix](https://github.com/rayxfelipe/azure-sql-cicd-accelerator/commit/89f1cb21e72db3e18eb188167b3914c307af40a3), retain configuration/state/keys, and rerun the same `-Apply`. Template updates do not automatically update existing copies. |
| VM SKU, quota, address-range or policy failure | Select approved available sizing/region/networks before the first apply. After state is saved, do not edit targets or discard state to force a rerun; resolve the blocker or deliberately clean up and start an isolated new adoption. |
| Setup refuses an active main-branch run | Let that run finish, or cancel it deliberately in GitHub, then rerun the same configuration. Setup intentionally does not alter infrastructure during releases. |
| Verification waits or a deployment is queued | Check environment approval requests and the runner's online status. See [runner lifecycle](OPERATIONS.md#runner-lifecycle); do not open public SQL access or manually enable setup gates. |
| Green workflow, but deployment skipped | Check job-level results, the main branch and setup variables. Build-only success is not a dev release and cannot be promoted. |

Never open public SQL access or manually enable setup gates to bypass a blocker.

## References

- [GitHub OIDC subject customization](https://docs.github.com/en/actions/reference/security/oidc)
- [Azure SQL Entra authentication](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-overview)
- [Azure SQL private endpoints](https://learn.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview)
- [Azure VM managed Run Command](https://learn.microsoft.com/en-us/azure/virtual-machines/run-command-managed)
