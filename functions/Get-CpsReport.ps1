function Get-CpsReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][array]$DiffResults,
        [Parameter(Mandatory=$true)][string]$ReportPath,
        [Parameter(Mandatory=$true)][string]$PkgId,
        [Parameter(Mandatory=$true)][string]$PkgVer,
        [Parameter(Mandatory=$true)][string]$LatestVersion
    )

    $ErrorActionPreference = 'Stop'

    $LogsDir = Split-Path $ReportPath
    if (-not (Test-Path -LiteralPath $LogsDir)) { 
        New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null 
    }

    Write-Host "  Building HTML report..." -ForegroundColor DarkGray

    $HtmlHead = @"
<!DOCTYPE html>
<html>
<head>
    <title>CPS Build Comparison</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f4f4f9; }
        
        /* Header and Search Bar Layout - Stacked and Left Justified */
        .header-container { margin-bottom: 15px; }
        h2 { color: #333; margin: 0 0 10px 0; }
        #searchInput { padding: 10px; width: 350px; border: 1px solid #ccc; border-radius: 4px; font-size: 14px; box-shadow: inset 0 1px 3px rgba(0,0,0,0.1); }
        #searchInput:focus { outline: none; border-color: #005A9E; box-shadow: 0 0 5px rgba(0,90,158,0.5); }

        /* Table Styles */
        table { border-collapse: collapse; min-width: 100%; width: max-content; background-color: #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.2); }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; vertical-align: top; max-width: 1024ch; overflow-wrap: break-word; }
        
        /* Sortable Header Styles */
        th { background-color: #005A9E; color: white; font-weight: bold; white-space: nowrap; cursor: pointer; user-select: none; position: relative; padding-right: 25px; transition: background-color 0.2s; }
        th:hover { background-color: #004578; }
        th::after { content: '\21D5'; position: absolute; right: 8px; color: rgba(255,255,255,0.4); }
        th.asc::after { content: '\2191'; color: white; }
        th.desc::after { content: '\2193'; color: white; }

        /* Row Color Coding */
        .Missing { background-color: #ffe6e6; } 
        .Added { background-color: #e6ffe6; }   
        .Modified { background-color: #fff3cd; }
        .Error { background-color: #ffcccc; color: #900; font-weight: bold;}

        pre { margin: 0; font-family: Consolas, monospace; white-space: pre-wrap; word-wrap: break-word; }
    </style>
</head>
<body>
    <div class="header-container">
        <h2>Build Comparison: $PkgId $PkgVer vs Octopus Latest $LatestVersion</h2>
        <input type="text" id="searchInput" placeholder="Search all columns instantly...">
    </div>
    <table id="diffTable">
        <thead>
            <tr>
                <th>Reference Path</th>
                <th>Difference Path</th>
                <th>File Name</th>
                <th>Change Type</th>
                <th>Location</th>
                <th>Item Name</th>
                <th>Item Property</th>
                <th>Reference Value</th>
                <th>Difference Value</th>
            </tr>
        </thead>
        <tbody>
"@

    $HtmlBody = New-Object System.Text.StringBuilder

    foreach ($diff in $DiffResults) {
        $rowClass = "Modified"
        if ($diff.ChangeType -match 'Missing') { $rowClass = "Missing" }
        elseif ($diff.ChangeType -match 'Added') { $rowClass = "Added" }
        elseif ($diff.ChangeType -match 'Error') { $rowClass = "Error" }

        $fName = if ($null -ne $diff.FileName) { $diff.FileName } else { $diff.File }
        $rPath = if ($null -ne $diff.ReferenceFullPath) { $diff.ReferenceFullPath } else { "Path Not Available" }
        $dPath = if ($null -ne $diff.DifferenceFullPath) { $diff.DifferenceFullPath } else { "Path Not Available" }
        
        $rValRaw = if ($null -ne $diff.ReferenceValue) { $diff.ReferenceValue } else { $diff.RefData }
        $dValRaw = if ($null -ne $diff.DifferenceValue) { $diff.DifferenceValue } else { $diff.DiffData }

        $refSafe = [string]$rValRaw
        $diffSafe = [string]$dValRaw
        
        if (![string]::IsNullOrEmpty($refSafe)) { $refSafe = $refSafe.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }
        if (![string]::IsNullOrEmpty($diffSafe)) { $diffSafe = $diffSafe.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }
        
        [void]$HtmlBody.AppendLine("<tr class='$rowClass'>")
        [void]$HtmlBody.AppendLine("<td>$rPath</td>")
        [void]$HtmlBody.AppendLine("<td>$dPath</td>")
        [void]$HtmlBody.AppendLine("<td>$fName</td>")
        [void]$HtmlBody.AppendLine("<td>$($diff.ChangeType)</td>")
        [void]$HtmlBody.AppendLine("<td>$($diff.Location)</td>")
        [void]$HtmlBody.AppendLine("<td>$($diff.ItemName)</td>")
        [void]$HtmlBody.AppendLine("<td>$($diff.ItemProperty)</td>")
        [void]$HtmlBody.AppendLine("<td><pre style='margin:0'>$refSafe</pre></td>")
        [void]$HtmlBody.AppendLine("<td><pre style='margin:0'>$diffSafe</pre></td>")
        [void]$HtmlBody.AppendLine("</tr>")
    }

    $HtmlFoot = @"
        </tbody>
    </table>

    <script>
        // --- Instant Search Logic ---
        document.getElementById('searchInput').addEventListener('input', function() {
            const filterText = this.value.toLowerCase();
            const rows = document.querySelectorAll('#diffTable tbody tr');
            
            rows.forEach(row => {
                // Check if the row's inner text contains the search string
                const rowText = row.innerText.toLowerCase();
                row.style.display = rowText.includes(filterText) ? '' : 'none';
            });
        });

        // --- Column Sorting Logic ---
        const getCellValue = (tr, idx) => tr.children[idx].innerText || tr.children[idx].textContent;

        const comparer = (idx, asc) => (a, b) => ((v1, v2) => 
            v1 !== '' && v2 !== '' && !isNaN(v1) && !isNaN(v2) ? v1 - v2 : v1.toString().localeCompare(v2)
        )(getCellValue(asc ? a : b, idx), getCellValue(asc ? b : a, idx));

        document.querySelectorAll('th').forEach(th => th.addEventListener('click', function() {
            const table = th.closest('table');
            const tbody = table.querySelector('tbody');
            const idx = Array.from(th.parentNode.children).indexOf(th);
            
            const isAsc = this.classList.contains('asc');
            document.querySelectorAll('th').forEach(h => h.classList.remove('asc', 'desc'));
            this.classList.add(isAsc ? 'desc' : 'asc');
            
            Array.from(tbody.querySelectorAll('tr'))
                .sort(comparer(idx, !isAsc))
                .forEach(tr => tbody.appendChild(tr));
        }));
    </script>
</body>
</html>
"@

    Set-Content -Path $ReportPath -Value ($HtmlHead + $HtmlBody.ToString() + $HtmlFoot) -Encoding UTF8
    Write-Host ("  HTML Report generated: {0}" -f $ReportPath) -ForegroundColor Green
}