function Compare-CpsBuilds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ReferencePath,
        [Parameter(Mandatory=$true)][string]$DifferencePath
    )

    $ErrorActionPreference = 'Stop'

    # Updated to include ItemName and ItemProperty
    function New-DiffObject {
        param($fName, $refPath, $diffPath, $cType, $loc, $iName, $iProp, $rVal, $dVal)
        return [pscustomobject]@{
            FileName           = $fName
            ReferenceFullPath  = $refPath
            DifferenceFullPath = $diffPath
            ChangeType         = $cType
            Location           = $loc
            ItemName           = $iName
            ItemProperty       = $iProp
            ReferenceValue     = $rVal
            DifferenceValue    = $dVal
        }
    }

    function Resolve-RootPath {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found: $Path" }
        $extension = [System.IO.Path]::GetExtension($Path).ToLower()
        if ($extension -eq '.zip') {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $tempDir | Out-Null
            [System.IO.Compression.ZipFile]::ExtractToDirectory($Path, $tempDir)
            return @{ Path = $tempDir; IsTemp = $true }
        }
        return @{ Path = (Resolve-Path -LiteralPath $Path).Path; IsTemp = $false }
    }

    function Compare-JsonObjects {
        param($RefObj, $DiffObj, [string]$CurrentPath, [string]$CurrentItemName, [System.Collections.Generic.List[object]]$DiffList)
        if ($null -eq $RefObj -and $null -eq $DiffObj) { return }

        if (($null -eq $RefObj) -or ($null -eq $DiffObj) -or ($RefObj.GetType() -ne $DiffObj.GetType())) {
            $DiffList.Add(@{ Location = $CurrentPath; ItemName = $CurrentItemName; ItemProperty = 'Type'; ChangeType = 'TypeOrNullMismatch'; RefValue = [string]$RefObj; DiffValue = [string]$DiffObj })
            return
        }

        if ($RefObj -is [array]) {
            $max = [Math]::Max($RefObj.Count, $DiffObj.Count)
            for ($i = 0; $i -lt $max; $i++) {
                $arrayPath = "$CurrentPath`[$i]"
                $iName = "Index $i"
                if ($i -ge $RefObj.Count) { $DiffList.Add(@{ Location = $arrayPath; ItemName = $iName; ItemProperty = 'ArrayItem'; ChangeType = 'AddedInDifference'; RefValue = ''; DiffValue = [string]$DiffObj[$i] }) }
                elseif ($i -ge $DiffObj.Count) { $DiffList.Add(@{ Location = $arrayPath; ItemName = $iName; ItemProperty = 'ArrayItem'; ChangeType = 'MissingInDifference'; RefValue = [string]$RefObj[$i]; DiffValue = '' }) }
                else { Compare-JsonObjects -RefObj $RefObj[$i] -DiffObj $DiffObj[$i] -CurrentPath $arrayPath -CurrentItemName $iName -DiffList $DiffList }
            }
            return
        }

        if ($RefObj -is [System.Management.Automation.PSCustomObject]) {
            $refProps = $RefObj.psobject.properties.name
            $diffProps = $DiffObj.psobject.properties.name
            $allProps = $refProps + $diffProps | Select-Object -Unique

            foreach ($prop in $allProps) {
                $propPath = if ($CurrentPath) { "$CurrentPath.$prop" } else { $prop }
                $inRef = $refProps -contains $prop
                $inDiff = $diffProps -contains $prop

                if ($inRef -and -not $inDiff) { $DiffList.Add(@{ Location = $CurrentPath; ItemName = $prop; ItemProperty = 'Property'; ChangeType = 'MissingInDifference'; RefValue = [string]$RefObj.$prop; DiffValue = '' }) }
                elseif ($inDiff -and -not $inRef) { $DiffList.Add(@{ Location = $CurrentPath; ItemName = $prop; ItemProperty = 'Property'; ChangeType = 'AddedInDifference'; RefValue = ''; DiffValue = [string]$DiffObj.$prop }) }
                else { Compare-JsonObjects -RefObj $RefObj.$prop -DiffObj $DiffObj.$prop -CurrentPath $propPath -CurrentItemName $prop -DiffList $DiffList }
            }
            return
        }

        $rComp = [string]$RefObj -replace '\s+', ''
        $dComp = [string]$DiffObj -replace '\s+', ''
        if ($rComp -ne $dComp) {
            $DiffList.Add(@{ Location = $CurrentPath; ItemName = $CurrentItemName; ItemProperty = 'Value'; ChangeType = 'ValueChanged'; RefValue = [string]$RefObj; DiffValue = [string]$DiffObj })
        }
    }

    function Compare-XmlNodes {
        param([System.Xml.XmlNode]$RefNode, [System.Xml.XmlNode]$DiffNode, [string]$CurrentPath, [string]$CurrentItemName, [System.Collections.Generic.List[object]]$DiffList)

        if ($RefNode.Name -ne $DiffNode.Name) {
            $DiffList.Add(@{ Location = $CurrentPath; ItemName = $CurrentItemName; ItemProperty = 'NodeName'; ChangeType = 'NodeNameMismatch'; RefValue = [string]$RefNode.Name; DiffValue = [string]$DiffNode.Name })
            return
        }

        # Compare Attributes
        $allAttrs = @()
        if ($RefNode.Attributes) { $allAttrs += $RefNode.Attributes | Select-Object -ExpandProperty Name }
        if ($DiffNode.Attributes) { $allAttrs += $DiffNode.Attributes | Select-Object -ExpandProperty Name }
        $allAttrs = $allAttrs | Select-Object -Unique

        foreach ($attr in $allAttrs) {
            $refVal = if ($RefNode.HasAttribute($attr)) { [string]$RefNode.GetAttribute($attr) } else { '' }
            $diffVal = if ($DiffNode.HasAttribute($attr)) { [string]$DiffNode.GetAttribute($attr) } else { '' }

            $rComp = $refVal -replace '\s+', ''
            $dComp = $diffVal -replace '\s+', ''

            if ($rComp -ne $dComp) {
                if ($dComp -eq '') { $DiffList.Add(@{ Location = $CurrentPath; ItemName = $CurrentItemName; ItemProperty = "@$attr"; ChangeType = 'AttributeMissingInDifference'; RefValue = $refVal; DiffValue = '' }) }
                elseif ($rComp -eq '') { $DiffList.Add(@{ Location = $CurrentPath; ItemName = $CurrentItemName; ItemProperty = "@$attr"; ChangeType = 'AttributeAddedInDifference'; RefValue = ''; DiffValue = $diffVal }) }
                else { $DiffList.Add(@{ Location = $CurrentPath; ItemName = $CurrentItemName; ItemProperty = "@$attr"; ChangeType = 'AttributeValueChanged'; RefValue = $refVal; DiffValue = $diffVal }) }
            }
        }

        # Compare Inner Text
        if (-not $RefNode.HasChildNodes -and -not $DiffNode.HasChildNodes) {
            $rComp = [string]$RefNode.InnerText -replace '\s+', ''
            $dComp = [string]$DiffNode.InnerText -replace '\s+', ''
            if ($rComp -ne $dComp) {
                $DiffList.Add(@{ Location = $CurrentPath; ItemName = $CurrentItemName; ItemProperty = 'InnerText'; ChangeType = 'InnerTextChanged'; RefValue = [string]$RefNode.InnerText; DiffValue = [string]$DiffNode.InnerText })
            }
            return
        }

        # Smart Signature Matching for Child Nodes
        $refChildren = @{}
        $diffChildren = @{}

        # Helper to identify nodes by their key, name, or id attribute
        function Get-NodeSignature($n) {
            if ($n.HasAttribute('key')) { return "$($n.Name)[@key='$($n.GetAttribute('key'))']" }
            if ($n.HasAttribute('name')) { return "$($n.Name)[@name='$($n.GetAttribute('name'))']" }
            if ($n.HasAttribute('id')) { return "$($n.Name)[@id='$($n.GetAttribute('id'))']" }
            return $n.Name
        }

        $idxT = @{}
        foreach ($c in $RefNode.ChildNodes) {
            $sig = Get-NodeSignature $c
            if (-not $idxT.ContainsKey($sig)) { $idxT[$sig] = 0 }
            $refChildren["$sig|__|$($idxT[$sig])"] = $c
            $idxT[$sig]++
        }

        $idxT = @{}
        foreach ($c in $DiffNode.ChildNodes) {
            $sig = Get-NodeSignature $c
            if (-not $idxT.ContainsKey($sig)) { $idxT[$sig] = 0 }
            $diffChildren["$sig|__|$($idxT[$sig])"] = $c
            $idxT[$sig]++
        }

        $allSigs = ($refChildren.Keys + $diffChildren.Keys) | Select-Object -Unique

        foreach ($sigKey in $allSigs) {
            $rChild = $refChildren[$sigKey]
            $dChild = $diffChildren[$sigKey]
            $baseSig = ($sigKey -split '\|__\|')[0]
            
            # Split the ItemName (e.g., 'BypassJXServiceLocalTestPANFile') from the pure Path (/configuration/appSettings/add)
            $iName = $baseSig
            $cPath = "$CurrentPath/$baseSig"
            if ($baseSig -match "\[@(key|name|id)='([^']+)'\]") {
                $iName = $matches[2]
                # PS 5.1 Fix: Perform the replace on a separate line to avoid nested quote parsing errors
                $cleanSig = $baseSig -replace "\[@(key|name|id)='[^']+'\]", ""
                $cPath = "$CurrentPath/$cleanSig"
            }

            if ($null -eq $dChild) { 
                $DiffList.Add(@{ Location = $cPath; ItemName = $iName; ItemProperty = 'Node'; ChangeType = 'NodeMissingInDifference'; RefValue = [string]$rChild.Name; DiffValue = '' }) 
            }
            elseif ($null -eq $rChild) { 
                $DiffList.Add(@{ Location = $cPath; ItemName = $iName; ItemProperty = 'Node'; ChangeType = 'NodeAddedInDifference'; RefValue = ''; DiffValue = [string]$dChild.Name }) 
            }
            else { 
                Compare-XmlNodes -RefNode $rChild -DiffNode $dChild -CurrentPath $cPath -CurrentItemName $iName -DiffList $DiffList 
            }
        }
    }

    $refInfo = Resolve-RootPath $ReferencePath
    $diffInfo = Resolve-RootPath $DifferencePath
    $refRoot = $refInfo.Path
    $diffRoot = $diffInfo.Path

    $refFiles = Get-ChildItem -Path $refRoot -File -Recurse
    $diffFiles = Get-ChildItem -Path $diffRoot -File -Recurse

    $refMap = @{}
    $diffMap = @{}
    $allRelativePaths = New-Object System.Collections.Generic.HashSet[string]

    foreach ($f in $refFiles) {
        $rel = $f.FullName.Substring($refRoot.Length).TrimStart('\', '/')
        $refMap[$rel] = @{ FullPath = $f.FullName; Hash = (Get-FileHash $f.FullName -Algorithm SHA256).Hash }
        $allRelativePaths.Add($rel) | Out-Null
    }

    foreach ($f in $diffFiles) {
        $rel = $f.FullName.Substring($diffRoot.Length).TrimStart('\', '/')
        $diffMap[$rel] = @{ FullPath = $f.FullName; Hash = (Get-FileHash $f.FullName -Algorithm SHA256).Hash }
        $allRelativePaths.Add($rel) | Out-Null
    }

    $masterDiffList = New-Object System.Collections.Generic.List[object]

    # Extract just the root folder/zip name (e.g., "SOA_DCOTP_4.1.0.1_2026.02.04_R.1")
    $refRootName = Split-Path -Path $ReferencePath -Leaf
    $diffRootName = Split-Path -Path $DifferencePath -Leaf

    foreach ($relPath in $allRelativePaths) {
        $inRef = $refMap.ContainsKey($relPath)
        $inDiff = $diffMap.ContainsKey($relPath)

        $fileName = [System.IO.Path]::GetFileName($relPath)
        $relDir = [System.IO.Path]::GetDirectoryName($relPath)

        # Build the clean path: RootName + \ + SubDirectory (if it exists). The file name is stripped.
        $rPath = "MISSING"
        if ($inRef) {
            $rPath = if ([string]::IsNullOrEmpty($relDir)) { $refRootName } else { "$refRootName\$relDir" }
        }

        $dPath = "MISSING"
        if ($inDiff) {
            $dPath = if ([string]::IsNullOrEmpty($relDir)) { $diffRootName } else { "$diffRootName\$relDir" }
        }

        if ($inRef -and -not $inDiff) { 
            $masterDiffList.Add((New-DiffObject $fileName $rPath $dPath 'FileMissingInDifference' 'Entire File' 'N/A' 'File' 'Exists' 'Missing'))
            continue 
        }
        if ($inDiff -and -not $inRef) { 
            $masterDiffList.Add((New-DiffObject $fileName $rPath $dPath 'FileAddedInDifference' 'Entire File' 'N/A' 'File' 'Missing' 'Exists'))
            continue 
        }
        
        if ($refMap[$relPath].Hash -eq $diffMap[$relPath].Hash) { continue }

        $refFile = $refMap[$relPath].FullPath
        $diffFile = $diffMap[$relPath].FullPath
        $ext = [System.IO.Path]::GetExtension($relPath).ToLower()

        switch ($ext) {
            { $_ -match '\.json$' } {
                try {
                    $rJson = Get-Content -Raw $refFile | ConvertFrom-Json
                    $dJson = Get-Content -Raw $diffFile | ConvertFrom-Json
                    $fileDiffs = New-Object System.Collections.Generic.List[object]
                    Compare-JsonObjects -RefObj $rJson -DiffObj $dJson -CurrentPath "$" -CurrentItemName "Root" -DiffList $fileDiffs
                    foreach ($d in $fileDiffs) { 
                        $masterDiffList.Add((New-DiffObject $fileName $rPath $dPath $d.ChangeType $d.Location $d.ItemName $d.ItemProperty $d.RefValue $d.DiffValue))
                    }
                } catch { $masterDiffList.Add((New-DiffObject $fileName $rPath $dPath 'ParseError' 'Entire File' 'JSON' 'Error' 'Error' 'Error')) }
            }
            { $_ -match '\.(xml|config)$' } {
                try {
                    [xml]$rXml = Get-Content -Raw $refFile -ErrorAction Stop
                    [xml]$dXml = Get-Content -Raw $diffFile -ErrorAction Stop
                    
                    $rXml.SelectNodes("//comment()") | ForEach-Object { $_.ParentNode.RemoveChild($_) | Out-Null }
                    $dXml.SelectNodes("//comment()") | ForEach-Object { $_.ParentNode.RemoveChild($_) | Out-Null }
                    
                    $fileDiffs = New-Object System.Collections.Generic.List[object]
                    Compare-XmlNodes -RefNode $rXml.DocumentElement -DiffNode $dXml.DocumentElement -CurrentPath "/$($rXml.DocumentElement.Name)" -CurrentItemName $($rXml.DocumentElement.Name) -DiffList $fileDiffs
                    foreach ($d in $fileDiffs) { 
                        $masterDiffList.Add((New-DiffObject $fileName $rPath $dPath $d.ChangeType $d.Location $d.ItemName $d.ItemProperty $d.RefValue $d.DiffValue))
                    }
                } catch { $masterDiffList.Add((New-DiffObject $fileName $rPath $dPath 'ParseError' 'Entire File' 'XML' 'Error' 'Error' 'Error')) }
            }
            { $_ -match '\.(dll|pdb|jar|exe|zip|png|jpg)$' } {
                $masterDiffList.Add((New-DiffObject $fileName $rPath $dPath 'BinaryChecksumMismatch' 'Entire File' 'Binary' 'Hash' $refMap[$relPath].Hash $diffMap[$relPath].Hash))
            }
            default {
                $rLinesRaw = Get-Content $refFile
                $dLinesRaw = Get-Content $diffFile
                
                $rLines = @()
                for ($i = 0; $i -lt $rLinesRaw.Count; $i++) {
                    if ($rLinesRaw[$i] -match '\S') { $rLines += [pscustomobject]@{ Text = [string]$rLinesRaw[$i]; Line = ($i + 1) } }
                }

                $dLines = @()
                for ($i = 0; $i -lt $dLinesRaw.Count; $i++) {
                    if ($dLinesRaw[$i] -match '\S') { $dLines += [pscustomobject]@{ Text = [string]$dLinesRaw[$i]; Line = ($i + 1) } }
                }

                $maxLines = [Math]::Max($rLines.Count, $dLines.Count)

                for ($i = 0; $i -lt $maxLines; $i++) {
                    $rObj = if ($i -lt $rLines.Count) { $rLines[$i] } else { $null }
                    $dObj = if ($i -lt $dLines.Count) { $dLines[$i] } else { $null }

                    $rStr = if ($rObj) { $rObj.Text } else { '' }
                    $dStr = if ($dObj) { $dObj.Text } else { '' }

                    $rComp = $rStr -replace '\s+', ''
                    $dComp = $dStr -replace '\s+', ''

                    if ($rComp -ne $dComp) {
                        $cType = if ($rComp -eq '') { 'LineAddedInDifference' } elseif ($dComp -eq '') { 'LineMissingInDifference' } else { 'LineModified' }
                        $locNum = if ($rObj) { $rObj.Line } else { $dObj.Line }
                        
                        # Populate new object schema for text files
                        $masterDiffList.Add((New-DiffObject $fileName $rPath $dPath $cType 'Entire File' "Line $locNum" 'Text' $rStr $dStr))
                    }
                }
            }
        }
    }

    if ($refInfo.IsTemp) { Remove-Item -Path $refInfo.Path -Recurse -Force }
    if ($diffInfo.IsTemp) { Remove-Item -Path $diffInfo.Path -Recurse -Force }

    return $masterDiffList
}