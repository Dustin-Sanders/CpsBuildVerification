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
Get-ChildItem "$HomePath\functions\" -Filter "*.ps1" | ForEach-Object {. $_.FullName}


#Step 1 — Select a single CPS build and copy it to the local machine

Write-Host "`nStep 1 - Select a build " -ForegroundColor Cyan
$A = Copy-CpsPackage -Drops $Drops -SoaPath $SoaPath -NetAppPath $NetAppPath -Workspace $HomePath

Write-Host ("  Artifact: {0}" -f $A.ArtifactName)
Write-Host ("  Staged to: {0}" -f $A.StagedPath)


# Step 2 — Compress the CPS build.

Write-Host "`nStep 2 - Compressing the build." -ForegroundColor Cyan
$B = Compress-CpsPackage -artifactName $A.ArtifactName -Workspace $A.Workspace -StagedPath $A.StagedPath

Write-Host ("  PkgId : {0}" -f $B.PkgId)
Write-Host ("  PkgVer: {0}" -f $B.PkgVer)
Write-Host ("  Zip   : {0}" -f $B.ZipPath)


# Step 3 — Download the latest package from Octopus that matches the application from step one.

Write-Host "`nStep 3 - Downloading the latest package from Octopus." -ForegroundColor Cyan
$C = Get-OctoPackage -OctopusUrl $OctopusUrl -ApiKey $ApiKey -SpaceName $SpaceName -pkgId $B.pkgId -Workspace $A.Workspace

$C.DownloadedPath = "C:\Users\DuSanders\Documents\ArtifactDefintionScripts\SOA_DCOTP.4.0.6-R1.zip"
$C.LatestVersion = "4.0.6-R1"

Write-Host ("  Downloaded: {0}" -f $C.DownloadedPath)
#Write-Host "  Downloaded:" $C.DownloadedPath

#Write-Host "`nDone!" -ForegroundColor Green

#Trace-Command -Name ParameterBinding -PSHost -Expression {
#    Compare-CpsBuilds -ReferencePath $A.StagedPath -DifferencePath $C.DownloadedPath
#}

######$result = Compare-CpsBuilds -ReferencePath $A.StagedPath -DifferencePath $C.DownloadedPath

# See summary:
######$result | Select * #ReferenceRoot, DifferenceRoot, FilesCompared, HashMismatches, MissingInReference, MissingInDifference

# Inspect detailed differences:
######$result.Differences | Format-Table ChangeType, ReferencePath, DifferencePath, RelativePath, LineNumber, DifferenceDetail, ReferenceText, DifferenceText -Wrap -AutoSize | Out-String | Set-Clipboard

                                                                                                   
# Export differences to JSON:
######$result.Differences | ConvertTo-Json -Depth 5 | Out-File "$($A.Workspace)\ComparisonLogs\diffs.json" -Encoding UTF8



#--------------------------------------------------------------------------
#--------------------------------------------------------------------------
#--------------------------------------------------------------------------



# ------------------------------------------
# Step 4 — Compare (staged vs downloaded) & HTML report
# ------------------------------------------
#Write-Host "`n[Step 4] Compare builds and generate HTML report..." -ForegroundColor Cyan
#
## Compose a deterministic report file name in ComparisonLogs
#$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
#$reportName = "Diff_{0}_{1}_vs_{2}_{3}.html" -f $B.pkgId, $B.pkgVer, $B.pkgId, $C.LatestVersion
#$reportPath = Join-Path $A.Workspace (Join-Path 'ComparisonLogs' $reportName)
#
#$D = Compare-CpsBuildsHTML `
#        -ReferencePath   $A.StagedPath `
#        -DifferencePath  $C.DownloadedPath `
#        -HtmlReportPath  $reportPath `
#        -ReportTitle     ("CPS Build Diff: {0} {1} vs Latest {2}" -f $B.pkgId, $B.pkgVer, $C.LatestVersion) `
#        -SortFileNames   $true `
#        -SortContent     $true `
#        -CaseInsensitive $true `
#        -IgnoreWhitespace $true `
#        -IgnoreBlankLines $true `
#        -CanonicalizeJson $true `
#        -CanonicalizeXml  $true
#
#Write-Host ("  Files Compared       : {0}" -f $D.FilesCompared)
#Write-Host ("  Hash Mismatches      : {0}" -f $D.HashMismatches)
#Write-Host ("  Missing In Reference : {0}" -f $D.MissingInReference)
#Write-Host ("  Missing In Difference: {0}" -f $D.MissingInDifference)
#Write-Host ("  HTML Report          : {0}" -f $D.HtmlReportPath) -ForegroundColor Yellow

#----------------------------------
#----------------------------------
#----------------------------------
#----------------------------------
#----------------------------------
#----------------------------------
#----------------------------------
#----------------------------------
#----------------------------------
#----------------------------------
#----------------------------------



# Step 4 — Semantic compare (XML/JSON/ASPX) + HTML report
# ------------------------------------------
#Write-Host "`n[Step 4] Compare builds and generate HTML report..." -ForegroundColor Cyan
#
#$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
#$reportName = "Diff_{0}_{1}_vs_{2}_{3}_{4}.html" -f $B.pkgId, $B.pkgVer, $B.pkgId, $C.LatestVersion, $timestamp
#$reportPath = Join-Path $A.Workspace (Join-Path 'ComparisonLogs' $reportName)
#
#$D = Compare-CpsBuildsHTMLv2 `
#        -ReferencePath   $A.StagedPath `
#        -DifferencePath  $C.DownloadedPath `
#        -HtmlReportPath  $reportPath `
#        -ReportTitle     ("CPS Build Diff: {0} {1} vs Latest {2}" -f $B.pkgId, $B.pkgVer, $C.LatestVersion) `
#        -IgnoreWhitespace $true `
#        -IgnoreBlankLines $true
#
#Write-Host ("  Hash Mismatches      : {0}" -f $D.HashMismatches)
#Write-Host ("  Missing In Reference : {0}" -f $D.MissingInReference)
#Write-Host ("  Missing In Difference: {0}" -f $D.MissingInDifference)
#Write-Host ("  HTML Report          : {0}" -f $D.HtmlReportPath) -ForegroundColor Yellow
#
## Optional: open report
#if ($D.HtmlReportPath -and (Test-Path -LiteralPath $D.HtmlReportPath)) {
#    Start-Process $D.HtmlReportPath
#}


# ------------------------------------------
# Step 4 — Compare builds and generate HTML report
# ------------------------------------------
Write-Host "`n[Step 4] Compare builds and generate HTML report..." -ForegroundColor Cyan

$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$reportName = "Diff_{0}_{1}_vs_{2}_{3}_{4}.html" -f $B.pkgId, $B.pkgVer, $B.pkgId, $C.LatestVersion, $timestamp
$reportPath = Join-Path $A.Workspace (Join-Path 'ComparisonLogs' $reportName)

$C.DownloadedPath = "C:\Users\DuSanders\Documents\ArtifactDefintionScripts\SOA_DCOTP.4.0.6-R1.zip"
$C.LatestVersion = "4.0.6-R1"

$D = Compare-CpsBuildsHTMLv3 `
        -ReferencePath   $A.StagedPath `
        -DifferencePath  $C.DownloadedPath `
        -HtmlReportPath  $reportPath `
        -ReportTitle     ("CPS Build Diff: {0} {1} vs Latest {2}" -f $B.pkgId, $B.pkgVer, $C.LatestVersion) `
        -IgnoreWhitespace $true `
        -IgnoreBlankLines $true

Write-Host ("  Hash Mismatches      : {0}" -f $D.HashMismatches)
Write-Host ("  Missing In Reference : {0}" -f $D.MissingInReference)
Write-Host ("  Missing In Difference: {0}" -f $D.MissingInDifference)
Write-Host ("  HTML Report          : {0}" -f $D.HtmlReportPath) -ForegroundColor Yellow

if ($D.HtmlReportPath -and (Test-Path -LiteralPath $D.HtmlReportPath)) {
    Start-Process $D.HtmlReportPath
}