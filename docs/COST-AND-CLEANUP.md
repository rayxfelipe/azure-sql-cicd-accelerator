# Cost and cleanup

Choose between keeping the environment, deallocating its runner, or permanently
removing it. Deallocation reduces cost; it does not remove the deployment.

## Cost before applying

The topology creates **two Basic SQL databases, one Ubuntu VM with an OS disk,
a NAT gateway and static egress IP, a private endpoint, and private DNS**.
VNet/NSG/managed identities are also provisioned. A private network is not free.

### Dated starter estimate: November 9, 2026

For the starter's West US 2 sizing, plan **USD 120-130/month continuously running**
or **USD 56-65/month with the runner deallocated all month**. This dated estimate
was checked against Microsoft's
[Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices).
It is not a spending cap, billing guarantee or promise of future rates.

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

### Reduce cost between releases

Use [runner lifecycle](OPERATIONS.md#runner-lifecycle) to deallocate after all
jobs finish. This estimate removes about **USD 60.74/month** of compute if the
VM stays deallocated all month, leaving a fixed-cost floor of **USD 55.63/month**.
Running the VM adds approximately $0.0832/hour. Confirm **Stopped (deallocated)**,
not just a Linux shutdown;
[allocated stopped VMs remain compute-billed](https://learn.microsoft.com/en-us/azure/virtual-machines/states-billing).
SQL, disk, NAT, public IP, private endpoint and DNS charges continue.

Keeping only the GitHub repository requires no Azure hosting. Separate
deployments each incur costs; viewers of one reference environment do not
multiply its fixed charges.

Check [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
for your selected region/SKU and establish an Azure budget/alert before `-Apply`.
Do not present the Basic database price alone as the total accelerator cost.
No Azure resources are created by local validation or repository creation.

## Isolated cleanup

**Cleanup permanently deletes the group's data and resources**, including ones
added after setup. Target only your dedicated adopter-owned group, never a
baseline/shared group. Export needed data and finish all release jobs first.

1. Preview and check the displayed subscription, group and resource inventory:

```powershell
.\scripts\Remove-Accelerator.ps1 -ConfigurationPath config\setup.json
```

2. Only after confirming the target, apply:

```powershell
.\scripts\Remove-Accelerator.ps1 -ConfigurationPath config\setup.json -Apply
```

Cleanup checks ownership tags, disables releases, and refuses active releases
or a busy runner. It records exact runner IDs in local state, deletes the Azure
group, confirms it is gone, then removes those runner registrations.

| Removed | Retained |
|---|---|
| Group and all its Azure resources/data, including identities/federation; recorded runner registrations | GitHub repository, environments, variables, OIDC subject customization and local recovery state. Release gates remain disabled after successful cleanup. |

### If cleanup fails

- **Azure deletion fails:** runner registrations remain usable. Fix the error,
  keep local state and rerun the same cleanup command with `-Apply`.
- **Azure is gone but runner removal fails:** keep the saved checkpoint and
  rerun with the same configuration. Cleanup uses recorded runner IDs, not a
  replacement runner with the same name.
- **Runner ownership cannot be proven:** cleanup refuses to guess. Inspect the
  registration and original setup state; do not remove unrelated runners.

If both group and matching runner are already absent, cleanup does not change
GitHub settings. If resources were deleted outside the script, ensure release
gates are disabled rather than assuming cleanup configured them.

After cleanup, preserve local state if you may reprovision with the same
configuration. To adopt elsewhere, use a separate fresh checkout and a new
resource group. Do not commit local keys or setup state.
