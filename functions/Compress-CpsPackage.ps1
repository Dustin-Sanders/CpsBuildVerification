<#
.SYNOPSIS
  Step 2 — Package build (derive Octopus package ID/version and zip)

.DESCRIPTION
  Derives pkgId and pkgVer from the staged folder name, performs any layout adjustments
  (e.g., RTP appbin flatten), and compresses the staged content.

.PARAMETER artifactName
  Mandatory. Typically the name from Step 1: $ArtifactPath.Name.

.PARAMETER Workspace
  Optional. Defaults to Join-Path $Env:USERPROFILE 'BuildAutomation'.

.PARAMETER StagedPath
  Optional. If provided, will be used as the root folder to zip. If not provided,
  defaults to "$Workspace\$ArtifactName".

.OUTPUTS
  PSCustomObject with:
    - PkgId       : [string]
    - PkgVer      : [string]
    - ZipPath     : [string]
    - ArtifactName: [string]
    - ContentRoot : [string]
#>
function Compress-CpsPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ArtifactName,
        [Parameter(Mandatory=$true)][string]$Workspace,
        [string]$StagedPath
    )

    $ErrorActionPreference = 'Stop'

    $ContentRoot = if ($StagedPath) { $StagedPath } else { Join-Path $Workspace $ArtifactName }
    if (-not (Test-Path -LiteralPath $ContentRoot)) {
        throw "Content root not found: '$ContentRoot'."
    }

    # FIX: Parse the actual folder name (which includes the app prefix) instead of the raw ArtifactName
    $FolderName = Split-Path $ContentRoot -Leaf
    $Parts = $FolderName -split '_'
    $PkgId = $null
    $PkgVer = $null

    switch ($true) {
        { $Parts.Count -ge 5 -and $Parts[0] -eq 'MAIN' -and $Parts[3] -eq 'RTP' } {
            $PkgId  = 'SOA_FSCRTP'
            $PkgVer = $Parts[4]

            $Appbin = Join-Path $ContentRoot 'InstanceSource\appbin'
            if (Test-Path -LiteralPath $Appbin) {
                $SrcGlob = Join-Path $Appbin '*'
                $DestDir = Join-Path $ContentRoot 'InstanceSource'
                Move-Item -Path $SrcGlob -Destination $DestDir -Force -ErrorAction Stop
                Remove-Item -LiteralPath $Appbin -Recurse -Force -ErrorAction Stop
            }
        }

        { $Parts.Count -ge 2 -and $Parts[0] -eq 'CPIINIS' } {
            $PkgId  = 'SOA_INISCPI'
            $PkgVer = $Parts[1]
        }

        { $Parts.Count -ge 2 -and $Parts[0] -eq 'NJCINIS' } {
            $PkgId  = 'SOA_INISNJC'
            $PkgVer = $Parts[1]
        }

        { $Parts.Count -ge 2 -and $Parts[0] -eq 'JBGRPSCU' } {
            $PkgId  = 'SOA_CPS382WS'
            $PkgVer = $Parts[1]
        }

        { $Parts.Count -ge 3 -and $Parts[1] -eq 'VSOTP' } {
            $PkgId  = 'SOA_VSOTP'
            $PkgVer = $Parts[2]
        }

        { $Parts.Count -ge 3 -and $Parts[1] -eq 'MCOTP' } {
            $PkgId  = 'SOA_MCOTP'
            $PkgVer = $Parts[2]
        }

        { $Parts.Count -ge 3 -and $Parts[1] -eq 'DCOTP' } {
            $PkgId  = 'SOA_DCOTP'
            $PkgVer = $Parts[2]
        }

        { $Parts.Count -ge 3 -and $Parts[1] -eq 'CPSSG' } {
            $PkgId  = 'SOA_CPSSG'
            $PkgVer = $Parts[2]
        }

        { $Parts[0] -eq 'CPSIdentity' } {
            $PkgId  = 'SOA_IDN'
            $PkgVer = $Parts[1] -replace '^v', ''
        }
        
        { $Parts.Count -ge 3 -and $Parts[1] -eq 'ARMS' } {
            $PkgId  = 'SOA_RM'
            $PkgVer = $Parts[2]
        }

        { $Parts.Count -ge 3 -and $Parts[1] -eq 'CTS' } {
            $PkgId  = 'SOA_CTS'
            $PkgVer = $Parts[2]
        }

        { $Parts.Count -ge 2 -and $Parts[0] -eq 'CPSPortal' } {
            $PkgId = 'EAD_CPSPTL'
            $PortalParts = $Parts[1] -split '-'
            if ($PortalParts.Count -lt 3) {
                throw "Unable to parse CPSPortal version from '$FolderName'. Expected '<branch>-<something>-<version>'."
            }
            $PkgVer = $PortalParts[2]
        }

        { $Parts.Count -ge 3 -and $Parts[0] -eq 'FSC' -and $Parts[1] -match '^(Letters|Statements)$' } {
            $PkgId  = if ($Parts[1] -eq 'Letters') { 'ETL_FSCLTRS' } else { 'ETL_FSCSTMNT' }
            $PkgVer = $Parts[2]
        }
    }

    if (-not $PkgId -or -not $PkgVer) {
        throw "Could not derive pkgId/pkgVer from artifactName '$FolderName'. Parts: $($Parts -join ', ')"
    }

    $Zip = Join-Path $Workspace ("{0}.{1}.zip" -f $PkgId, $PkgVer)

    # Compress staged content
    if (Test-Path -LiteralPath $Zip) {
        Remove-Item -LiteralPath $Zip -Force
    }
    Compress-Archive -Path (Join-Path $ContentRoot '*') -DestinationPath $Zip -Force

    [PSCustomObject]@{
        pkgId        = $PkgId
        pkgVer       = $PkgVer
        ZipPath      = $Zip
        ArtifactName = $ArtifactName
        ContentRoot  = $ContentRoot
    }
}