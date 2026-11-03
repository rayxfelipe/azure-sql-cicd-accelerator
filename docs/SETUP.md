# Guided setup

## Before running

- Create a new **private** GitHub.com repository from the template. Never point
  setup at the original demonstration repository or its resources.
- The repository must contain all three workflows on default branch `main`.
  Its `origin` must match `repository` in the configuration.
- GitHub Actions and repository self-hosted runners must be allowed.
  Your GitHub plan must support environments and custom deployment branch
  policies for private repositories (for example GitHub Pro/Team/Enterprise).
  Setup fails explicitly if required controls are unavailable.
- Run locally in PowerShell 7.4+ with .NET 10, Azure CLI/Bicep, GitHub CLI,
  Git and `ssh-keygen`. Hosted PR validation does not need Azure sign-in.
- Use a dedicated Azure public-cloud subscription/resource group, permitted
  Ubuntu/SQL SKUs, sufficient regional VM quota and policies permitting the
  private topology. Check the what-if and cost before `-Apply`.
- Run only one setup/cleanup operation for a repository at a time. Existing
  workflows must be finished before rerunning infrastructure setup.

## Initial setup permissions versus routine releases

| Actor | Required access |
|---|---|
| Setup operator, Azure control plane | Create a subscription-scope deployment and dedicated resource group; provision SQL, identities, networking and VM; assign Reader at that group; register required providers; run/delete protected VM Run Commands. |
| Setup operator, SQL | Be the configured Entra SQL administrator, or a member of its configured Entra group, to create contained users and grant permissions. |
| Setup operator, GitHub | Repository administrator; CLI token with repository/workflow/environment, runner, variable and OIDC customization access. Organization SSO/policies may also apply. |
| Routine dev identity | Reader on the dedicated resource group; explicit SQL database creation/definition grants and dbo schema deployment/DML grants in dev only. |
| Routine production identity | Same limited access, but contained-user grants in production only; a different OIDC identity. |
| Runner VM | No Azure managed identity, no inbound public access, no SQL administrator permissions. |

A temporary Owner assignment at the target subscription is a convenient **broad**
setup option, not a routine release requirement. A least-privilege alternative
combines subscription-level deployment/resource-group creation permissions,
Contributor for accelerator resource types, provider registration access, and
Role Based Access Control Administrator on the dedicated group for Reader
assignment. Have the platform team arrange those scopes before provisioning.
Remove temporary elevation after setup. Do not grant deployment identities
Contributor, SQL administrator or `db_owner`.

## Configuration

Copy [the example](../config/setup.example.json) to `config/setup.json`. This local
file, generated SSH keys, parameters and state are Git-ignored.

- `subscriptionId`: explicit target; every Azure command passes it.
- `repository`: exact `owner/repository`, matching this checkout's `origin`.
- `location`: region identifier, such as `eastus`. Resources and Run Commands
  use this value; no inherited demonstration location is required.
- `resourceGroupName`: NEW isolated group. An existing group is accepted only
  when its ownership tags identify this accelerator **and** this repository.
- `resourcePrefix`: 3-16 lowercase letters/digits, starting with a letter.
  SQL server uniqueness includes subscription, group and repository.
  Database, identity, network and VM names derive from the prefix.
- `administratorObjectId`, `administratorLogin`, `administratorPrincipalType`:
  SQL setup administrator user/group, never the deployment identity.
- `runnerVmSize`: regional Ubuntu x64-compatible VM size; default B2s v2.
- `runnerAdminUsername`: non-reserved Linux VM administrator username; this is
  separate from the `githubrunner` service account and does not enable inbound SSH.
- `vnetAddressPrefix`, `runnerSubnetPrefix`, `privateEndpointSubnetPrefix`:
  network-aligned RFC1918 IPv4 ranges. Both subnets must be inside the VNet
  without overlap. Check overlap with your organization's networks too.

The region/SKU must be available and permitted by your subscription. Defaults
are configurable starter values, not a quota or capacity guarantee.

## Preview and apply

```powershell
az login
gh auth login
.\scripts\Setup-Accelerator.ps1 -ConfigurationPath config\setup.json
.\scripts\Setup-Accelerator.ps1 -ConfigurationPath config\setup.json -Apply
```

Preview validates input, reads repository/resource-group state, generates a local
SSH key and parameter file, and runs Azure what-if. It does **not** change GitHub
settings or provision Azure resources. `-Apply` is explicit consent to the shown
topology, GitHub configuration changes and ongoing charges.

Apply:

1. Saves rerun configuration and disables release jobs (`SETUP_COMPLETE=false`).
2. Creates main-only `dev`/`production` environments. Existing reviewers/wait
   timers are preserved; incompatible branch policies fail rather than weaken.
3. Configures the **new repository only** with OIDC claim keys
   `repository_id,context`. Federation subjects are
   `repository_id:<actual repository ID>:environment:dev` and `...:production`.
   This avoids guessing either legacy or immutable default subject formats.
   Existing incompatible custom subject policies are rejected.
4. Registers providers and deploys the isolated Bicep topology.
5. Sets environment-specific Azure/SQL variables and a repository-ID-specific
   runner label; starts and initializes the VM via protected Run Command.
6. Obtains a short-lived setup-administrator SQL token and bootstraps both
   contained users via the private VM. The SID uses the identity's **client ID**,
   not its service principal object ID. Mismatched existing users are rejected.
7. Dispatches `verify-setup.yml`. Hosted jobs check actual emitted OIDC claims;
   private jobs authenticate each identity and check DNS, TCP, SQL identity
   and every required grant. No schema or business data is changed by readiness.
8. Enables releases only after all four verification jobs explicitly succeed.
   A successful workflow with skipped jobs is rejected.

## Reruns and failures

Use the **same** configuration and keep `.azure/setup-state.json` plus the SSH
key pair. Setup upserts variables/grants, reuses correctly owned resources,
preserves the registered runner and resumes partially created main-only
environments. It does not replace mismatched SQL users or foreign runners.
Changing saved configuration is rejected to prevent unintended replacements.

A failed setup leaves deployments disabled but can leave billable resources.
Apply and cleanup refuse active/queued/waiting main-branch CI and promotion
runs; finish or deliberately cancel those runs before infrastructure changes.
Read the reported error, fix it and rerun. Verification waits at most 30 minutes;
check environment approvals, runner status and the linked workflow if it times
out. A missing/stale GitHub runner registration requires deliberate runner
repair, not silently deleting another registration.

Protected Run Commands are deleted in `finally`, including after failures.
If cleanup itself fails, the error is surfaced: inspect and remove the named
command after correcting permissions. Do not publish Run Command diagnostics
or local setup state if they contain sensitive environment details.

After successful setup, dispatch **Database CI and dev deployment** for the
initial schema deployment. Readiness is not a claim that a DACPAC release passed.
Then follow [the fresh-adoption acceptance steps](VALIDATION.md).

## References

- [GitHub OIDC subject customization](https://docs.github.com/en/actions/reference/security/oidc)
- [Azure SQL Entra authentication](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-overview)
- [Azure SQL private endpoints](https://learn.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview)
- [Azure VM managed Run Command](https://learn.microsoft.com/en-us/azure/virtual-machines/run-command-managed)
