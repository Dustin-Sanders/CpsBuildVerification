#Script v1.0.5

#Configuration variables
$HomePath              = "$PSScriptRoot"
$ParametersPath        = Join-Path $HomePath "config\parameters.json"

if (-not (Test-Path -Path $ParametersPath)) {
    throw "Configuration file not found: $ParametersPath"
}

$Config                = Get-Content $ParametersPath -Raw | ConvertFrom-Json
$Drops                 = $Config.Drops
$SoaPath               = $Config.SoaPath
$NetAppPath            = $Config.NetAppPath
$OctopusUrl            = $Config.OctopusUrl
$ApiKey                = $Config.ApiKey
$SpaceName             = $Config.SpaceName
$ErrorActionPreference = 'Stop'

#Source functions
Get-ChildItem "$HomePath\functions\" -Filter "*.ps1" | ForEach-Object {. $_.FullName }

#Step 1 — Select a single CPS build and copy it to the local machine

Write-Host "`nStep 1 - Select a build " -ForegroundColor Cyan
$A = Copy-CpsPackage -Drops $Drops -SoaPath $SoaPath -NetAppPath $NetAppPath -Workspace "$HomePath\diffs"

Write-Host ("  Artifact: {0}"  -f $A.ArtifactName)
Write-Host ("  Staged to: {0}" -f $A.StagedPath)

#Step 2 — Compress the CPS build.

Write-Host "`nStep 2 - Compressing the build." -ForegroundColor Cyan
$B = Compress-CpsPackage -ArtifactName $A.ArtifactName -Workspace $A.Workspace -StagedPath $A.StagedPath

Write-Host ("  PkgId : {0}" -f $B.PkgId)
Write-Host ("  PkgVer: {0}" -f $B.PkgVer)
Write-Host ("  Zip   : {0}" -f $B.ZipPath)

#Step 3 — Download the latest package from Octopus that matches the application from step one.

Write-Host "`nStep 3 - Downloading the latest package from Octopus." -ForegroundColor Cyan
$C = Get-OctoPackage -OctopusUrl $OctopusUrl -ApiKey $ApiKey -SpaceName $SpaceName -pkgId $B.pkgId -Workspace $A.Workspace

Write-Host ("  Downloaded: {0}" -f $C.DownloadedPath)

#Set the default comparison paths
$ReferencePath = $A.StagedPath
$DifferencePath = $C.DownloadedPath

# ------------------------------------------
# Step 3.5 — Package FSC Full Build
# ------------------------------------------
if ($B.pkgId -match '^ETL_FSC') {
    Write-Host "`nStep 3.5 - Packaging full build for FSC." -ForegroundColor Cyan
    
    # Call the new function and overwrite the ReferencePath with the returned folder
    $ReferencePath = Package-FscBuild -OctopusZipPath $C.DownloadedPath -PartialDropPath $A.StagedPath -Workspace $A.Workspace -PkgId $B.pkgId -PkgVer $B.pkgVer
}

#Step 4 — Compare builds and generate reports
Write-Host "`n[Step 4] Compare builds and generate reports..." -ForegroundColor Cyan

#Run the comparison
$DiffResults = Compare-CpsBuilds -ReferencePath $ReferencePath -DifferencePath $DifferencePath

Write-Host ("  Found {0} differences." -f $DiffResults.Count) -ForegroundColor Yellow

#Define paths
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$baseName   = "Diff_{0}_{1}_vs_{2}_{3}_{4}" -f $B.pkgId, $B.pkgVer, $B.pkgId, $C.LatestVersion, $timestamp
$reportPath = Join-Path $A.Workspace (Join-Path 'ComparisonLogs' "$baseName.html")
$csvPath    = Join-Path $A.Workspace (Join-Path 'ComparisonLogs' "$baseName.csv")

#Generate the HTML Report
Get-CpsReport -DiffResults @($DiffResults) -ReportPath $reportPath -PkgId $B.pkgId -PkgVer $B.pkgVer -LatestVersion $C.LatestVersion

# 4. Generate the Temporary CSV for Baseline Profiling
if ($DiffResults.Count -gt 0) {
    Export-CpsDiffCsv -DiffResults @($DiffResults) -CsvPath $csvPath
}

# 5. Open the folder so you can grab the CSVs easily
Invoke-Item (Split-Path $csvPath)