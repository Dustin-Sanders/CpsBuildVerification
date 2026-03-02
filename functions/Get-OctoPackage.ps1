<#
.SYNOPSIS
  Step 3 — Download latest package from Octopus

.DESCRIPTION
  Resolves the Space by name, finds the latest version for pkgId on the built-in feed,
  and downloads the package to the Workspace.

.PARAMETER OctopusUrl
  Octopus Server URL (e.g., https://octopus.jhapps.com)

.PARAMETER ApiKey
  Octopus API key (supply securely).

.PARAMETER SpaceName
  Name of the Space (e.g., CPS)

.PARAMETER pkgId
  The package ID (from Step 2).

.PARAMETER Workspace
  Optional. Destination folder for the downloaded .zip.
  Defaults to Join-Path $env:USERPROFILE 'BuildAutomation'.

.OUTPUTS
  PSCustomObject with:
    - DownloadedPath : [string]
    - LatestVersion  : [string]
    - pkgId          : [string]
    - SpaceId        : [string]
#>

function Get-OctoPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$OctopusUrl,
        [Parameter(Mandatory=$true)][string]$ApiKey,
        [Parameter(Mandatory=$true)][string]$SpaceName,
        [Parameter(Mandatory=$true)][string]$pkgId,
        [Parameter(Mandatory=$true)][string]$Workspace
    )

    $ErrorActionPreference = 'Stop'

    $Headers = @{ "X-Octopus-ApiKey" = $ApiKey }

    # Resolve space
    $spaces = Invoke-RestMethod -Uri "$OctopusUrl/api/spaces/all" -Headers $Headers -Method Get
    $space  = $spaces | Where-Object { $_.Name -eq $SpaceName } | Select-Object -First 1
    if (-not $space) {
        throw "Space '$SpaceName' not found at '$OctopusUrl'."
    }

    # Get latest version for pkgId from built-in feed
    $versionsUrl = "$OctopusUrl/api/$($space.Id)/feeds/feeds-builtin/packages/versions?packageId=$pkgId&take=1"
    $latest = Invoke-RestMethod -Uri $versionsUrl -Headers $Headers -Method Get

    if (-not $latest.Items -or -not $latest.Items[0] -or -not $latest.Items[0].Version) {
        throw "No versions found for package '$pkgId' in space '$($space.Name)'."
    }
    $latestVer = $latest.Items[0].Version

    # Download the latest package
    $dest = Join-Path $Workspace ("{0}.{1}.zip" -f $pkgId, $latestVer)
    $downloadUrl = "$OctopusUrl/api/$($space.Id)/packages/$pkgId.$latestVer/raw"

    Invoke-RestMethod -Uri $downloadUrl -Headers $Headers -Method Get -OutFile $dest

    Write-Host "  Downloaded: $pkgId $latestVer --> $dest"

    [pscustomobject]@{
        DownloadedPath = $dest
        LatestVersion  = $latestVer
        pkgId          = $pkgId
    }
}