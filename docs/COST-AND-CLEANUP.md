# Cost and cleanup

## Cost before applying

The topology creates **two Basic SQL databases, one Ubuntu VM with an OS disk,
a NAT gateway and static egress IP, a private endpoint, and private DNS**.
VNet/NSG/managed identities are also provisioned. A private network is not free.

For this starter topology, use **USD 110-130/month continuously running** or
**USD 50-65/month with the VM deallocated** only as rough historical planning
estimates. These are **not current retail quotes** and not a billing guarantee.
Region, VM size, taxes, transfer, NAT data processing, security tooling,
GitHub plans and hosted-runner minutes affect actual costs.

Check [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
for your selected region/SKU and establish an Azure budget/alert before `-Apply`.
Do not present the Basic database price alone as the total accelerator cost.
No Azure resources are created by local validation or repository creation.

## Isolated cleanup

Export any data you need. Delete only the dedicated adopter-owned resource
group, never a baseline/shared group. Preview first:

```powershell
.\scripts\Remove-Accelerator.ps1 -ConfigurationPath config\setup.json
# DESTRUCTIVE: permanently deletes ALL data/resources in that group:
.\scripts\Remove-Accelerator.ps1 -ConfigurationPath config\setup.json -Apply
```

Cleanup verifies both ownership tags, disables releases, refuses a busy runner,
and records its exact runner IDs in the ignored local setup state. It deletes the
dedicated Azure group and confirms it is absent **before** removing those runner
registrations. If Azure deletion fails, the registrations remain usable.
Review the displayed inventory: all
resources in the owned group, including ones added later, will be deleted.

The GitHub repository, environments, variables and custom OIDC subject policy
are retained. OIDC federation/identities disappear with the resource group.
If GitHub runner removal fails after Azure deletion, fix the reported error and
rerun the same cleanup command with `-Apply`. The saved checkpoint lets it finish
registration cleanup even though the Azure group is already absent. Retry targets
recorded IDs, not a replacement runner with the same name, and refuses mismatched
repository/deployment state.

If no checkpoint exists and a matching runner remains, cleanup refuses to guess
ownership; inspect that registration manually. If both the group and matching
runner are already absent, cleanup returns without changing GitHub settings.
Disable release variables manually if deletion happened outside this script.

After cleanup, preserve local state if you may reprovision with the same
configuration. To adopt elsewhere, use a separate fresh checkout and a new
resource group. Do not commit local keys or setup state.
