#Script v1.0.0

#$Source      = Get-ChildItem "C:\Users\DuSanders\documents\ArtifactDefintionScripts\" -Include "functions", "Get-CpsBuild.ps1" -Recurse
#$Destination = "C:\Users\DuSanders\OneDrive - Jack Henry\Documents\_CPS_2021\PowerShell\ArtifactDefinitionScripts"
#Copy-Item -Path $Source -Destination "$Destination" -Recurse -Force

#Configuration variables
$HomePath              = "$PSScriptRoot"
$Drops                 = "\\ATXCPSBLD01\Drops"
$SoaPath               = "\\ATXCPSBLD01\Drops\PPSSOA\MAIN\Applications"
$NetAppPath            = "\\ATXCPSBLD01\Drops\NET\NET_APP_SERVER\NET_APP_SERVER_V2.0.0_2021.09.10_B.1"
$OctopusUrl            = 'https://octopus.jhapps.com' #octopus.ecpr.com (Andrew's team)
$ApiKey                = 'API-7M1JODCCUSCO1PR1DKYFHFOB9EU8FKT'
$SpaceName             = 'CPS'
$ErrorActionPreference = 'Stop'

#Source functions
Get-ChildItem "$HomePath\functions\" -Filter "*.ps1" | ForEach-Object {. $_.FullName }

#Step 1 — Select a single CPS build and copy it to the local machine

Write-Host "`nStep 1 - Select a build " -ForegroundColor Cyan
$A = Copy-CpsPackage -Drops $Drops -SoaPath $SoaPath -NetAppPath $NetAppPath -Workspace "$HomePath\diffs"

Write-Host ("  Artifact: {0}"  -f $A.ArtifactName)
Write-Host ("  Staged to: {0}" -f $A.StagedPath)

# Step 2 — Compress the CPS build.

Write-Host "`nStep 2 - Compressing the build." -ForegroundColor Cyan
$B = Compress-CpsPackage -ArtifactName $A.ArtifactName -Workspace $A.Workspace -StagedPath $A.StagedPath

Write-Host ("  PkgId : {0}" -f $B.PkgId)
Write-Host ("  PkgVer: {0}" -f $B.PkgVer)
Write-Host ("  Zip   : {0}" -f $B.ZipPath)

#$B.pkgId = "SOA_DCOTP"

# Step 3 — Download the latest package from Octopus that matches the application from step one.

Write-Host "`nStep 3 - Downloading the latest package from Octopus." -ForegroundColor Cyan
$C = Get-OctoPackage -OctopusUrl $OctopusUrl -ApiKey $ApiKey -SpaceName $SpaceName -pkgId $B.pkgId -Workspace $A.Workspace

#$C.DownloadedPath = "C:\Users\DuSanders\Documents\ArtifactDefintionScripts\diffs\SOA_DCOTP.4.0.6-R1.zip"
#$C.DownloadedPath = "C:\Users\DuSanders\Documents\ArtifactDefintionScripts\wip\SOA_DCOTP.4.0.6-R1"
#$C.LatestVersion = "4.0.6-R1"

Write-Host ("  Downloaded: {0}" -f $C.DownloadedPath)
#Write-Host "  Downloaded:" $C.DownloadedPath

# ------------------------------------------
# Step 4 — Compare builds and generate reports
# ------------------------------------------
Write-Host "`n[Step 4] Compare builds and generate reports..." -ForegroundColor Cyan

# 1. Run the Comparison
$DiffResults = Compare-CpsBuilds -ReferencePath $A.StagedPath -DifferencePath $C.DownloadedPath

Write-Host ("  Found {0} differences." -f $DiffResults.Count) -ForegroundColor Yellow

# 2. Define the paths
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$baseName   = "Diff_{0}_{1}_vs_{2}_{3}_{4}" -f $B.pkgId, $B.pkgVer, $B.pkgId, $C.LatestVersion, $timestamp
$reportPath = Join-Path $A.Workspace (Join-Path 'ComparisonLogs' "$baseName.html")
$csvPath    = Join-Path $A.Workspace (Join-Path 'ComparisonLogs' "$baseName.csv")

# 3. Generate HTML Report (Your current working report)
#Get-ChildItem "$HomePath\functions\" -Filter "*.ps1" | ForEach-Object {. $_.FullName }
Get-CpsReport -DiffResults @($DiffResults) `
              -ReportPath $reportPath `
              -PkgId $B.pkgId `
              -PkgVer $B.pkgVer `
              -LatestVersion $C.LatestVersion

# 4. Generate the Temporary CSV for Baseline Profiling
if ($DiffResults.Count -gt 0) {
    Export-CpsDiffCsv -DiffResults @($DiffResults) -CsvPath $csvPath
}

# 5. Open the folder so you can grab the CSVs easily
Invoke-Item (Split-Path $csvPath)