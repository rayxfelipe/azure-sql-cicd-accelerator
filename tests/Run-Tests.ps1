. (Join-Path (Split-Path $PSScriptRoot) 'scripts/Common.ps1')
$script:passed = 0
function Assert-Test {
    param([bool] $Condition, [string] $Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}
function Assert-Throws {
    param([scriptblock] $Action, [string] $MessagePattern, [string] $Name)
    $caught = $false
    try { & $Action }
    catch {
        if ($_.Exception.Message -notmatch $MessagePattern) { throw }
        $caught = $true
    }
    Assert-Test $caught $Name
}

Assert-Test (Test-AddressInCidr '10.42.2.4' '10.42.2.0/24') 'Configured private subnet is accepted (not a demo-specific range)'
Assert-Test (-not (Test-AddressInCidr '10.42.3.4' '10.42.2.0/24')) 'Wrong private subnet is rejected'
Assert-Test (-not (Test-AddressInCidr '20.42.2.4' '10.42.2.0/24')) 'Public SQL address is rejected'
Assert-Test (-not (Test-AddressInCidr '::1' '10.42.2.0/24')) 'IPv6 does not bypass the IPv4 private-endpoint check'
Assert-Test (Test-AddressInCidr '10.42.2.0' '10.42.2.0/24') 'CIDR first address is included'
Assert-Test (Test-AddressInCidr '10.42.2.255' '10.42.2.0/24') 'CIDR last address is included'
Assert-Throws { Get-Ipv4Cidr '10.42.2.0/33' } 'Invalid IPv4 CIDR' 'Invalid prefix is rejected'
Assert-Throws { Get-Ipv4Cidr 'not-a-network' } 'Invalid IPv4 CIDR' 'Malformed CIDR is rejected'

$owned = [pscustomobject]@{ tags = [pscustomobject]@{ 'managed-by' = 'azure-sql-cicd-accelerator'; repository = 'owner/adopter' } }
Assert-OwnedResourceGroup $owned 'owner/adopter'
Assert-Test $true 'Matching accelerator-owned resource group can be reused'
Assert-Throws { Assert-OwnedResourceGroup $owned 'owner/another' } 'Refusing' 'Different repository resource group is protected'
Assert-Throws { Assert-OwnedResourceGroup ([pscustomobject]@{ tags = $null }) 'owner/adopter' } 'Refusing' 'Untagged baseline resource group is protected'
Assert-Throws { Assert-OwnedResourceGroup ([pscustomobject]@{ tags = [pscustomobject]@{ project = 'demo' } }) 'owner/adopter' } 'Refusing' 'Baseline-style resource group is protected'

$config = @{
    subscriptionId = '11111111-1111-1111-1111-111111111111'; repository = 'owner/adopter'
    location = 'eastus'; resourceGroupName = 'rg-adopter'; resourcePrefix = 'adopter'
    administratorObjectId = '22222222-2222-2222-2222-222222222222'; administratorLogin = 'Setup Admin'
    administratorPrincipalType = 'Group'; runnerVmSize = 'Standard_B2s_v2'; runnerAdminUsername = 'runneradmin'
    vnetAddressPrefix = '172.20.0.0/16'; runnerSubnetPrefix = '172.20.1.0/24'; privateEndpointSubnetPrefix = '172.20.2.0/24'
}
$temporaryFile = Join-Path ([IO.Path]::GetTempPath()) "sql-accelerator-test-$([guid]::NewGuid().ToString('N')).json"
function Write-TestConfiguration {
    param([hashtable] $Value)
    $Value | ConvertTo-Json | Set-Content -LiteralPath $temporaryFile
}
try {
    Write-TestConfiguration $config
    $actual = Read-SetupConfiguration $temporaryFile
    Assert-Test ($actual.resourcePrefix -eq 'adopter' -and $actual.location -eq 'eastus') 'Fresh adopter configuration works outside baseline region and names'
    foreach ($case in @(
        @{ Field = 'subscriptionId'; Value = '00000000-0000-0000-0000-000000000000'; Pattern = 'nonzero GUID'; Name = 'Placeholder subscription is rejected' },
        @{ Field = 'repository'; Value = 'YOUR-OWNER/YOUR-PRIVATE-REPOSITORY'; Pattern = 'owner/name'; Name = 'Placeholder repository is rejected' },
        @{ Field = 'resourcePrefix'; Value = 'Bad Prefix'; Pattern = 'resourcePrefix'; Name = 'Invalid resource name is rejected' },
        @{ Field = 'runnerSubnetPrefix'; Value = '172.21.1.0/24'; Pattern = 'inside'; Name = 'Subnet outside VNet is rejected' },
        @{ Field = 'runnerSubnetPrefix'; Value = '172.20.2.0/25'; Pattern = 'overlap'; Name = 'Overlapping subnets are rejected' },
        @{ Field = 'runnerSubnetPrefix'; Value = '172.20.1.5/24'; Pattern = 'network-aligned'; Name = 'Non-aligned subnet is rejected' },
        @{ Field = 'vnetAddressPrefix'; Value = '20.20.0.0/16'; Pattern = 'RFC1918'; Name = 'Public VNet range is rejected' }
    )) {
        $changed = $config.Clone()
        $changed[$case.Field] = $case.Value
        Write-TestConfiguration $changed
        Assert-Throws { Read-SetupConfiguration $temporaryFile } $case.Pattern $case.Name
    }
}
finally { Remove-Item -LiteralPath $temporaryFile }

$run = [pscustomobject]@{
    status = 'completed'; conclusion = 'success'; head_branch = 'main'; path = '.github/workflows/database-ci.yml'
    event = 'push'; head_repository = [pscustomobject]@{ full_name = 'owner/adopter' }
}
$jobs = @([pscustomobject]@{ name = 'build'; conclusion = 'success' }, [pscustomobject]@{ name = 'deploy-dev'; conclusion = 'success' })
$artifacts = @([pscustomobject]@{ id = 123; name = 'database-release'; expired = $false })
$artifact = Assert-TrustedRelease $run $jobs $artifacts 'owner/adopter'
Assert-Test ($artifact.id -eq 123) 'Successful trusted dev release returns the exact artifact ID'
foreach ($case in @(
    @{ Field = 'event'; Value = 'pull_request'; Name = 'PR run cannot be promoted' },
    @{ Field = 'head_branch'; Value = 'feature'; Name = 'Non-main run cannot be promoted' },
    @{ Field = 'conclusion'; Value = 'failure'; Name = 'Failed run cannot be promoted' },
    @{ Field = 'status'; Value = 'in_progress'; Name = 'Incomplete run cannot be promoted' },
    @{ Field = 'path'; Value = '.github/workflows/other.yml'; Name = 'Different workflow cannot be promoted' }
)) {
    $changed = $run | ConvertTo-Json | ConvertFrom-Json
    $changed.($case.Field) = $case.Value
    Assert-Throws { Assert-TrustedRelease $changed $jobs $artifacts 'owner/adopter' } 'Only a successful trusted' $case.Name
}
Assert-Throws { Assert-TrustedRelease $run $jobs $artifacts 'owner/another' } 'Only a successful trusted' 'Foreign repository cannot be promoted'
foreach ($conclusion in @('skipped', 'failure', 'cancelled')) {
    $badJobs = @([pscustomobject]@{ name = 'deploy-dev'; conclusion = $conclusion })
    Assert-Throws { Assert-TrustedRelease $run $badJobs $artifacts 'owner/adopter' } 'did not successfully deploy dev' "Dev $conclusion is not promotion evidence"
}
Assert-Throws { Assert-TrustedRelease $run @() $artifacts 'owner/adopter' } 'did not successfully deploy dev' 'Missing dev job is rejected'
Assert-Throws { Assert-TrustedRelease $run $jobs @([pscustomobject]@{ name = 'database-release'; expired = $true }) 'owner/adopter' } 'unexpired' 'Expired artifact is rejected'
Assert-Throws { Assert-TrustedRelease $run $jobs @() 'owner/adopter' } 'exactly one' 'Missing artifact is rejected'
Assert-Throws { Assert-TrustedRelease $run $jobs ($artifacts + $artifacts) 'owner/adopter' } 'exactly one' 'Ambiguous artifact is rejected'

$verificationJobs = @('OIDC (dev)', 'OIDC (production)', 'SQL (dev)', 'SQL (production)') |
    ForEach-Object { [pscustomobject]@{ name = $_; conclusion = 'success' } }
Assert-SetupVerificationJobs $verificationJobs
Assert-Test $true 'Both OIDC subjects and private SQL environments must pass readiness'
$verificationJobs[3].conclusion = 'skipped'
Assert-Throws { Assert-SetupVerificationJobs $verificationJobs } 'did not succeed' 'Skipped production readiness cannot enable deployments'
Assert-Throws { Assert-SetupVerificationJobs @() } 'did not succeed' 'Entirely skipped workflow cannot enable deployments'

$originalNative = ${function:Invoke-CheckedCommand}
$script:nativeCalls = @()
function Invoke-CheckedCommand {
    param([string] $Command, [string[]] $Arguments)
    $script:nativeCalls += ,$Arguments
    if ($Arguments[2] -eq 'create') { throw 'Simulated initialization failure' }
}
try {
    $configuration = [pscustomobject]@{ subscriptionId = 'test'; resourceGroup = 'rg-adopter'; runnerVm = 'vm-adopter'; location = 'eastus' }
    Assert-Throws { Invoke-PrivateRunCommand $configuration 'exit 1' @('Token=fake-test-value') } 'Simulated initialization failure' 'Run Command failure is surfaced'
    Assert-Test ($script:nativeCalls.Count -eq 2 -and $script:nativeCalls[1][2] -eq 'delete') 'Protected Run Command is cleaned up even when initialization fails'
    Assert-Test ($script:nativeCalls[0] -contains '--protected-parameters') 'Bootstrap values use protected Run Command parameters'
}
finally { Set-Item -Path function:Invoke-CheckedCommand -Value $originalNative }

Write-Host "$script:passed accelerator regression tests passed."
