function Compare-CpsBuilds {
    <#
      Compares two CPS build roots (folder or zip) using SHA256 checksums,
      recursing through all files, and performs content diffs on text files
      when checksums differ.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ReferencePath,
        [Parameter(Mandatory=$true)][string]$DifferencePath,
        [ValidateSet('SHA256','SHA1','SHA384','SHA512')]
        [string]$Algorithm = 'SHA256'
    )

    $ErrorActionPreference = 'Stop'

    # --------------------------------------------------------------------
    # Helper: Expand zip OR return folder unchanged
    # --------------------------------------------------------------------
    function Resolve-Root {
        param([Parameter(Mandatory=$true)][string]$InputPath)

        if (-not (Test-Path -LiteralPath $InputPath)) {
            throw "Path not found: $InputPath"
        }

        $ext = [IO.Path]::GetExtension($InputPath)

        if ($ext -and $ext.ToLower() -eq '.zip') {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $temp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $temp | Out-Null

            [System.IO.Compression.ZipFile]::ExtractToDirectory($InputPath, $temp)

            return [pscustomobject]@{
                Root = $temp
                Temp = $true
            }
        }
        else {
            return [pscustomobject]@{
                Root = (Resolve-Path -LiteralPath $InputPath).Path
                Temp = $false
            }
        }
    }

    # --------------------------------------------------------------------
    # Helper: Build file map (relative paths → metadata)
    # --------------------------------------------------------------------
    function Build-FileMap {
        param([string]$Root)

        $map = @{}

        # No pipelines with ambiguous parameters. Raw foreach-loop only.
        $files = Get-ChildItem -LiteralPath $Root -File -Recurse

        foreach ($file in $files) {

            # Construct RELATIVE PATH manually (NO Resolve-Path, NO ForEach-Object)
            $rel = $file.FullName.Substring($Root.Length)
            $rel = $rel.TrimStart('\','/')

            $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm $Algorithm

            $map[$rel] = @{
                FullPath = $file.FullName
                Hash     = $hash.Hash
                Length   = $file.Length
            }
        }

        return $map
    }

    # --------------------------------------------------------------------
    # Helper: Detect text/binary files (safe, no pipelines)
    # --------------------------------------------------------------------
    function Test-IsTextFile {
        param([string]$Path)

        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -eq 0) { return $true }

        if ($bytes -contains 0) { return $false }

        $printable = 0
        foreach ($b in $bytes) {
            if ($b -ge 9 -and $b -le 13) { $printable++ }
            elseif ($b -ge 32 -and $b -le 126) { $printable++ }
        }
        return (($printable / $bytes.Length) -ge 0.85)
    }

    # --------------------------------------------------------------------
    # Helper: Safe text reading (no pipelines)
    # --------------------------------------------------------------------
    function Read-Text {
        param([string]$Path)

        try { return Get-Content -LiteralPath $Path -Raw }
        catch {
            $bytes = [IO.File]::ReadAllBytes($Path)
            return [Text.Encoding]::UTF8.GetString($bytes)
        }
    }

    # --------------------------------------------------------------------
    # Helper: Compare text files line-by-line
    # --------------------------------------------------------------------
    function Compare-TextFiles {
        param(
            [string]$RefPath,
            [string]$DifPath,
            [string]$RelPath
        )

        $ref = Read-Text $RefPath
        $dif = Read-Text $DifPath

        $refLines = $ref -split "`r?`n", -1
        $difLines = $dif -split "`r?`n", -1

        $max = [Math]::Max($refLines.Count, $difLines.Count)
        $output = New-Object System.Collections.Generic.List[object]

        for ($i=0; $i -lt $max; $i++) {
            $lineNum = $i + 1
            $a = if ($i -lt $refLines.Count) { $refLines[$i] } else { $null }
            $b = if ($i -lt $difLines.Count) { $difLines[$i] } else { $null }

            if ($a -eq $b) { continue }

            $output.Add([pscustomobject]@{
                RelativePath     = $RelPath
                ReferencePath    = $RefPath
                DifferencePath   = $DifPath
                LineNumber       = $lineNum
                ReferenceText    = $a
                DifferenceText   = $b
                ChangeType       = if ($a -eq $null) { 'AddedInDifference' }
                                   elseif ($b -eq $null) { 'MissingInDifference' }
                                   else { 'Modified' }
            })
        }

        return $output
    }

    # ====================================================================
    # MAIN EXECUTION
    # ====================================================================

    $tempDirs = @()
    $ref = Resolve-Root $ReferencePath
    $dif = Resolve-Root $DifferencePath

    if ($ref.Temp) { $tempDirs += $ref.Root }
    if ($dif.Temp) { $tempDirs += $dif.Root }

    $refMap = Build-FileMap $ref.Root
    $difMap = Build-FileMap $dif.Root

    $allKeys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in $refMap.Keys) { $allKeys.Add($k) | Out-Null }
    foreach ($k in $difMap.Keys) { $allKeys.Add($k) | Out-Null }

    $differences = New-Object System.Collections.Generic.List[object]
    $filesCompared = 0
    $hashMatches = 0
    $hashMismatches = 0
    $missingRef = 0
    $missingDif = 0

    foreach ($rel in $allKeys) {

        $inRef = $refMap.ContainsKey($rel)
        $inDif = $difMap.ContainsKey($rel)

        if ($inRef -and $inDif) {
            $filesCompared++

            if ($refMap[$rel].Hash -eq $difMap[$rel].Hash) {
                $hashMatches++
                continue
            }

            $hashMismatches++

            $refPath = $refMap[$rel].FullPath
            $difPath = $difMap[$rel].FullPath

            if (Test-IsTextFile $refPath -and Test-IsTextFile $difPath) {
                $diffs = Compare-TextFiles $refPath $difPath $rel
                foreach ($d in $diffs) { $differences.Add($d) }
            }
            else {
                # Binary mismatch
                $differences.Add([pscustomobject]@{
                    RelativePath     = $rel
                    ReferencePath    = $refPath
                    DifferencePath   = $difPath
                    ChangeType       = 'BinaryDifferent'
                    LineNumber       = $null
                    ReferenceText    = $null
                    DifferenceText   = $null
                })
            }
        }
        elseif ($inRef -and -not $inDif) {
            $missingDif++

            $differences.Add([pscustomobject]@{
                RelativePath     = $rel
                ReferencePath    = $refMap[$rel].FullPath
                DifferencePath   = ''
                ChangeType       = 'MissingInDifference'
                LineNumber       = $null
            })
        }
        elseif ($inDif -and -not $inRef) {
            $missingRef++

            $differences.Add([pscustomobject]@{
                RelativePath     = $rel
                ReferencePath    = ''
                DifferencePath   = $difMap[$rel].FullPath
                ChangeType       = 'AddedInDifference'
                LineNumber       = $null
            })
        }
    }
Write-Host "Debug"
    # Clean up temporary extraction dirs
#    foreach ($t in $tempDirs) {
#        if (Test-Path -LiteralPath $t) {
#            Remove-Item -LiteralPath $t -Recurse -Force
#        }
#    }

    return [pscustomobject]@{
        ReferenceRoot       = $ref.Root
        DifferenceRoot      = $dif.Root
        FilesCompared       = $filesCompared
        HashMatches         = $hashMatches
        HashMismatches      = $hashMismatches
        MissingInReference  = $missingRef
        MissingInDifference = $missingDif
        Differences         = $differences
    }
}