#Version 1.0.0

function Copy-CpsPackage {
	
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Drops,
        [Parameter(Mandatory=$true)][string]$SoaPath,
        [Parameter(Mandatory=$true)][string]$NetAppPath,
        [Parameter(Mandatory=$true)][string]$Workspace
    )

    $ErrorActionPreference = 'Stop'

    function Select-Folder {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$Path
        )
        Get-ChildItem -Path $Path -Directory |
            Out-GridView -Title "Select a folder under: $Path" -OutputMode Single
    }

    function Copy-App {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$Source,
            [Parameter(Mandatory=$true)][string]$Destination,
            [string[]]$Exclude = @()
        )

        # Ensure destination exists
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null

        $args = @($Source, $Destination, '/MIR', '/ETA')
        if ($Exclude -and $Exclude.Count) {
            $args += '/XD'
            $args += $Exclude
        }

        & robocopy @args | Out-Host
        $Code = $LASTEXITCODE
        # Robocopy success/warning codes: 0..7. Failures: >= 8
        if ($Code -ge 8) {
            throw "Robocopy failed (exit code $Code) from '$Source' to '$Destination'."
        }
    }

    # --------------------------
    # Workspace prep
    # --------------------------
    $LogsPath = Join-Path $Workspace 'ComparisonLogs'
    if (-not (Test-Path -LiteralPath $LogsPath)) {
        New-Item -ItemType Directory -Force -Path $LogsPath | Out-Null
    }

    # --------------------------
    # STEP 1 — Select Application
    # --------------------------
    $AppPath = Select-Folder -Path $Drops
    if (-not $AppPath) { throw "No application family selected from '$Drops'." }

    $ArtifactPath = $null
    $StagedPath   = $null
    $AppFamily    = $AppPath.Name
    $Exclude      = @("Database*", "Document*")

    # --------------------------
    # PPSSOA Logic
    # --------------------------
    if ($AppPath.Name -eq 'PPSSOA') {
        $AppFamily = 'PPSSOA'

        $AppPath = Select-Folder -Path $SoaPath
        if (-not $AppPath) { throw "No PPS SOA application selected from '$SoaPath'." }

        switch -Regex ($AppPath.Name) {

            # --- NetApp group ---
            '^(MAIN_SOA_FSC|CPS_JBRIDGE_PSCUDX_SVC|MAIN_SOA_NJCINIS|MAIN_SOA_CPIINIS)$' {
                $Artifact = Select-Folder -Path $AppPath.FullName
                if (-not $Artifact) { throw "No artifact selected under '$($AppPath.FullName)'." }

                $Root = Join-Path $Workspace $Artifact.Name
                Copy-App -Source $Artifact.FullName -Destination (Join-Path $Root 'InstanceSource') -Exclude $Exclude
                Copy-App -Source $NetAppPath        -Destination (Join-Path $Root 'Service')

                $ArtifactPath = $Artifact
                $StagedPath   = $Root
            }

            # --- OTP ---
            '^MAIN_SOA_OTP$' {
                $Card = Select-Folder -Path $AppPath.FullName
                if (-not $Card) { throw "No card type selected under '$($AppPath.FullName)'." }

                $Artifact = Select-Folder -Path $Card.FullName
                if (-not $Artifact) { throw "No artifact selected under '$($Card.FullName)'." }

                $Dest = Join-Path $Workspace $Artifact.Name
                if ($Card.Name -match 'MasterCard|Visa|Discover') {
                    Copy-App -Source (Join-Path $Artifact.FullName 'Code') -Destination $Dest -Exclude $Exclude
                }
                else {
                    Copy-App -Source $Artifact.FullName -Destination $Dest -Exclude $Exclude
                }

                $ArtifactPath = $Artifact
                $StagedPath   = $Dest
            }

            # --- Letters/Statements ---
            '^(FSC_Letters|FSC_Statements)$' {
                $Artifact = Select-Folder -Path $AppPath.FullName
                if (-not $Artifact) { throw "No artifact selected under '$($AppPath.FullName)'." }

                $Dest = Join-Path $Workspace ("{0}_{1}" -f $AppPath.Name, $Artifact.Name)
                Copy-App -Source $Artifact.FullName -Destination $Dest

                $ArtifactPath = $Artifact
                $StagedPath   = $Dest
            }

            # --- Other SOA ---
            '^(MAIN_SOA_CPSServicesGateway|CPSIdentity|MAIN_SOA_CTS|MAIN_SOA_ARMS)$' {
                $Artifact = Select-Folder -Path $AppPath.FullName
                if (-not $Artifact) { throw "No artifact selected under '$($AppPath.FullName)'." }

                $Dest = Join-Path $Workspace $Artifact.Name
                Copy-App -Source $Artifact.FullName -Destination $Dest -Exclude $Exclude

                $ArtifactPath = $Artifact
                $StagedPath   = $Dest
            }

            default {
                throw "Unsupported PPSSOA application: '$($AppPath.Name)'."
            }
        }
    }
    # --------------------------
    # CPSPortal Logic
    # --------------------------
    elseif ($AppPath.Name -eq 'CPSPortal') {
        $AppFamily = 'CPSPortal'

        $Artifact = Select-Folder -Path $AppPath.FullName
        if (-not $Artifact) { throw "No artifact selected under '$($AppPath.FullName)'." }

        $Dest = Join-Path $Workspace ("CPSPortal_{0}" -f $Artifact.Name)
        Copy-App -Source $Artifact.FullName -Destination $Dest -Exclude $Exclude

        $ArtifactPath = $Artifact
        $StagedPath   = $Dest
    }
    else {
        throw "Unsupported application family: '$($AppPath.Name)'."
    }

    if (-not $ArtifactPath -or -not $StagedPath) {
        throw "Staging failed to produce valid outputs."
    }
    
    # Return a structured object for downstream steps
    [pscustomobject]@{
        ArtifactPath = $ArtifactPath
        ArtifactName = $ArtifactPath.Name
        StagedPath   = $StagedPath
        Workspace    = $Workspace
        AppFamily    = $AppFamily
    }
}