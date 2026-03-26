<#
.SYNOPSIS
  Step 3.5 � Package full build for partial drops

.DESCRIPTION
  Takes a downloaded Octopus package (the base), unzips it, and then overlays 
  a staged partial drop (the patch) directly on top of it using Robocopy.
#>
function Package-FscBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$OctopusZipPath,
        [Parameter(Mandatory=$true)][string]$PartialDropPath,
        [Parameter(Mandatory=$true)][string]$Workspace,
        [Parameter(Mandatory=$true)][string]$PkgId,
        [Parameter(Mandatory=$true)][string]$PkgVer
    )

    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -LiteralPath $OctopusZipPath)) { throw "Octopus zip not found at '$OctopusZipPath'" }
    if (-not (Test-Path -LiteralPath $PartialDropPath)) { throw "Partial drop not found at '$PartialDropPath'" }

    $FscPackagedPath = Join-Path $Workspace ("Packaged_{0}_{1}" -f $PkgId, $PkgVer)

    if (Test-Path -LiteralPath $FscPackagedPath) {
        Remove-Item -LiteralPath $FscPackagedPath -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $FscPackagedPath | Out-Null

    Write-Host "    Extracting Octopus base to act as foundation..." -ForegroundColor DarkGray
    Expand-Archive -Path $OctopusZipPath -DestinationPath $FscPackagedPath -Force

    Write-Host "    Overlaying partial drop on top of base..." -ForegroundColor DarkGray
    $Arguements = @($PartialDropPath, $FscPackagedPath, '/E', '/ETA')
    
    # Hide the standard output but capture the exit code
    & robocopy @Arguements | Out-Null
    $Code = $LASTEXITCODE

    # Robocopy success codes: 0 (No changes), 1 (Files copied), 2 (Extra files), 3 (Both 1 and 2)
    if ($Code -ge 8) {
        throw "Robocopy failed (exit code $Code) during packaging from '$PartialDropPath' to '$FscPackagedPath'."
    }

    # Return the new path so the master script can feed it to the comparison engine
    return $FscPackagedPath
}