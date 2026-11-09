# Cost and cleanup

## Cost before applying

The topology creates **two Basic SQL databases, one Ubuntu VM with an OS disk,
a NAT gateway and static egress IP, a private endpoint, and private DNS**.
VNet/NSG/managed identities are also provisioned. A private network is not free.

### Dated starter estimate: November 9, 2026

The isolated West US 2 adoption environment was checked against Microsoft's
[Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices).
For that sizing, budget approximately **USD 120-130/month continuously running**
or **USD 56-65/month with the runner VM deallocated for the whole month**.
These are planning ranges, not a billing guarantee or a promise of future rates.

| Resource | Monthly fixed-cost estimate (USD) |
|---|---:|
| One Linux `Standard_B2s_v2` runner at $0.0832/hour | 60.74 |
| Standard NAT gateway at $0.045/hour | 32.85 |
| Two Basic, 5-DTU SQL databases at $0.161/day each | 9.79 |
| One private endpoint at $0.01/hour | 7.30 |
| One Standard public IPv4 address at $0.005/hour | 3.65 |
| One 32-GiB Standard HDD LRS OS disk | 1.54 |
| One private DNS zone | 0.50 |
| **Fixed-cost total** | **116.37** |

Assumptions: **USD public pay-as-you-go rates and 730 hours/month**, before
taxes, subscription discounts and credits. The planning ranges allow for light
demo usage; they are not spending caps. NAT data processing ($0.045/GB),
private-endpoint data processing (initial tier $0.01/GB in each direction),
applicable bandwidth, DNS queries, disk operations and any additional backup
usage can add charges. Different regions/SKUs, security tooling and other
resource groups are outside this estimate. GitHub plans, storage and
hosted-runner minutes may incur separate GitHub charges.

Deallocating the VM removes about **USD 60.74/month** of compute if it stays
deallocated all month, leaving a fixed-cost floor of about **USD 55.63/month**.
Starting it for demos adds approximately $0.0832 per running hour. The runner
must be online for deployments; do not deallocate it during an active workflow.
Confirm **Stopped (deallocated)** rather than merely shutting down Linux;
[allocated stopped VMs remain compute-billed](https://learn.microsoft.com/en-us/azure/virtual-machines/states-billing).
SQL, disk, NAT, public IP, private endpoint and DNS charges continue.

Keeping only the GitHub repository does not require Azure hosting. Each
separately provisioned customer environment incurs its own Azure costs; multiple
people viewing one reference environment do not multiply its fixed charges.

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
