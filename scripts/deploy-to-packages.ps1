<#
.SYNOPSIS
    Copies the UTCIntegration D365 F&O metadata from this repository into PackagesLocalDirectory.

.DESCRIPTION
    Mirrors Metadata\UTCIntegration\Descriptor and Metadata\UTCIntegration\UTCIntegration
    into <PackagesLocalDirectory>\UTCIntegration without touching compiled bin\ or XppMetadata\ folders.

.PARAMETER PackagesLocalDirectory
    Optional override for the AosService PackagesLocalDirectory path.
    Defaults to K:\AosService\PackagesLocalDirectory (falls back to C:\AosService\PackagesLocalDirectory).

.EXAMPLE
    .\scripts\deploy-to-packages.ps1

.EXAMPLE
    .\scripts\deploy-to-packages.ps1 -PackagesLocalDirectory "K:\AosService\PackagesLocalDirectory"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$PackagesLocalDirectory
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'Metadata\UTCIntegration'

if (-not (Test-Path (Join-Path $sourceRoot 'Descriptor\UTCIntegration.xml'))) {
    throw "Source metadata not found at '$sourceRoot'. Run this script from within the UTCSFCustomerSync repository."
}

if ([string]::IsNullOrWhiteSpace($PackagesLocalDirectory)) {
    if (Test-Path 'K:\AosService\PackagesLocalDirectory') {
        $PackagesLocalDirectory = 'K:\AosService\PackagesLocalDirectory'
    }
    elseif (Test-Path 'C:\AosService\PackagesLocalDirectory') {
        $PackagesLocalDirectory = 'C:\AosService\PackagesLocalDirectory'
    }
    else {
        throw "Could not auto-detect PackagesLocalDirectory (checked K:\ and C:\). Pass -PackagesLocalDirectory explicitly."
    }
}

$destRoot = Join-Path $PackagesLocalDirectory 'UTCIntegration'

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "Deploying UTCIntegration metadata to PackagesLocalDirectory"        -ForegroundColor Cyan
Write-Host "  Source : $sourceRoot"                                             -ForegroundColor Gray
Write-Host "  Target : $destRoot"                                               -ForegroundColor Gray
Write-Host "==================================================================" -ForegroundColor Cyan

# Mirror only Descriptor and UTCIntegration subfolders so compiled bin\, XppMetadata\, and build logs are preserved
$subfolders = @('Descriptor', 'UTCIntegration')

foreach ($folder in $subfolders) {
    $src = Join-Path $sourceRoot $folder
    $dst = Join-Path $destRoot   $folder

    if (-not (Test-Path $src)) {
        throw "Expected source folder missing: $src"
    }

    New-Item -ItemType Directory -Path $dst -Force | Out-Null

    Write-Host "`nSyncing $folder..." -ForegroundColor Yellow
    & robocopy $src $dst /MIR /R:2 /W:2 /NP /NFL /NDL

    # Robocopy exit codes 0-7 indicate success; >= 8 indicates an error
    if ($LASTEXITCODE -ge 8) {
        throw "Robocopy failed for '$folder' with exit code $LASTEXITCODE."
    }
}

Write-Host "`nDeployment complete!" -ForegroundColor Green
Write-Host "Next steps in Visual Studio 2022 (Run as Administrator):" -ForegroundColor Cyan
Write-Host "  1. Extensions -> Dynamics 365 -> Model Management -> Refresh Models"
Write-Host "  2. Extensions -> Dynamics 365 -> Build Models -> check 'UTCIntegration' + 'Synchronize Database'"
