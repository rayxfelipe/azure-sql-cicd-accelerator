[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'Common.ps1')
$root = Split-Path $PSScriptRoot
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'scripts'), (Join-Path $root 'tests') -Filter '*.ps1' -File) {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "PowerShell syntax errors in $($file.Name): $($errors.Message -join '; ')" }
}
foreach ($path in @('config/setup.example.json', '.vscode/tasks.json', 'Azure SQL CI-CD Accelerator.code-workspace')) {
    $null = Get-Content -LiteralPath (Join-Path $root $path) -Raw | ConvertFrom-Json
}
& (Join-Path $root 'tests/Run-Tests.ps1')
Invoke-CheckedCommand dotnet @('build', (Join-Path $root 'database/Database.sqlproj'), '--configuration', 'Release')
$packages = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES } else { Join-Path $HOME '.nuget/packages' }
$sdk = ([xml](Get-Content -LiteralPath (Join-Path $root 'database/Database.sqlproj') -Raw)).Project.Sdk -split '/'
$parserAssembly = Join-Path $packages "$($sdk[0].ToLowerInvariant())/$($sdk[1])/tools/net8.0/Microsoft.SqlServer.TransactSql.ScriptDom.dll"
$null = [System.Reflection.Assembly]::LoadFrom($parserAssembly)
$parser = [Microsoft.SqlServer.TransactSql.ScriptDom.TSql170Parser]::new($true)
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'tests') -Filter '*.sql' -File) {
    $reader = [IO.StringReader]::new((Get-Content -LiteralPath $file.FullName -Raw))
    try {
        $errors = $null
        $null = $parser.Parse($reader, [ref]$errors)
        if ($errors.Count -gt 0) { throw "SQL syntax errors in $($file.Name): $($errors.Message -join '; ')" }
    }
    finally { $reader.Dispose() }
}
$buildDirectory = Join-Path $root '.azure'
$null = New-Item -ItemType Directory -Path $buildDirectory -Force
Invoke-CheckedCommand az @('bicep', 'build', '--file', (Join-Path $root 'infra/main.bicep'), '--outfile', (Join-Path $buildDirectory 'main.json'))
$compiled = Get-Content -LiteralPath (Join-Path $buildDirectory 'main.json') -Raw | ConvertFrom-Json
$sql = ($compiled.resources | Where-Object name -eq 'accelerator-sql').properties.template
$network = ($compiled.resources | Where-Object name -eq 'accelerator-private-runner').properties.template
$server = $sql.resources | Where-Object type -eq 'Microsoft.Sql/servers'
if ($server.properties.publicNetworkAccess -ne 'Disabled' -or $server.properties.minimalTlsVersion -ne '1.2' -or
    -not $server.properties.administrators.azureADOnlyAuthentication) { throw 'Compiled SQL template must enforce private-only Entra authentication and TLS 1.2.' }
if ($sql.variables.environments.Count -ne 2 -or $sql.outputs.configuration.value.environments.Count -ne 2) {
    throw 'Compiled template must emit exactly two distinct deployment environments.'
}
$vm = $network.resources | Where-Object type -eq 'Microsoft.Compute/virtualMachines'
$nic = $network.resources | Where-Object type -eq 'Microsoft.Network/networkInterfaces'
if ($vm.PSObject.Properties['identity'] -or $nic.properties.ipConfigurations[0].properties.PSObject.Properties['publicIPAddress']) {
    throw 'Runner VM must have no managed identity and no public NIC address.'
}
$nsg = $network.resources | Where-Object type -eq 'Microsoft.Network/networkSecurityGroups'
$deny = @($nsg.properties.securityRules | Where-Object { $_.properties.direction -eq 'Inbound' -and $_.properties.access -eq 'Deny' -and $_.properties.sourceAddressPrefix -eq '*' })
if ($deny.Count -ne 1) { throw 'Runner NSG must deny all inbound traffic.' }
$endpoint = $network.resources | Where-Object type -eq 'Microsoft.Network/privateEndpoints'
$dnsGroup = $network.resources | Where-Object type -eq 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups'
$dnsLink = $network.resources | Where-Object type -eq 'Microsoft.Network/privateDnsZones/virtualNetworkLinks'
if (-not $endpoint -or -not $dnsGroup -or -not $dnsLink) { throw 'Private SQL endpoint must be wired to private DNS and the runner VNet.' }
Write-Host 'PASS: PowerShell and SQL syntax, JSON configuration, regression tests, DACPAC build, Bicep compilation and private-network topology invariants.'
