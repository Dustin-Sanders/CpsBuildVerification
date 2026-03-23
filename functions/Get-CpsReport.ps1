#v1.0.2
function Get-CpsReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [array]$DiffResults,
        
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

    Write-Host "  Loading rules.json and evaluating Quality Gate..." -ForegroundColor DarkGray
    $rulesPath = Join-Path (Split-Path $PSScriptRoot -Parent) "config\rules.json"
    $rules = @()
    if (Test-Path -LiteralPath $rulesPath) {
        $rules = (Get-Content $rulesPath -Raw | ConvertFrom-Json).GlobalRules
    } else {
        Write-Warning "  rules.json not found at $rulesPath. All differences will be marked as Reject."
    }

    $approvedCount = 0
    $rejectedCount = 0

    $resultsArray = @($DiffResults)

    foreach ($diff in $resultsArray) {
        $diff | Add-Member -NotePropertyName "Status" -NotePropertyValue "Reject" -Force

        foreach ($rule in $rules) {
            $isMatch = $false
            
            $patterns = $rule.FileMatch -split '\|'
            foreach ($pattern in $patterns) {
                if ($diff.FileName -like $pattern) {
                    $isMatch = $true
                    break
                }
            }

            # --- Path Matching Logic ---
            if ($isMatch -and $null -ne $rule.PathMatch) {
                $pathMatch = $false
                $pathPatterns = $rule.PathMatch -split '\|'
                foreach ($pp in $pathPatterns) {
                    if ($diff.ReferenceFullPath -like $pp -or $diff.DifferenceFullPath -like $pp) {
                        $pathMatch = $true
                        break
                    }
                }
                $isMatch = $pathMatch
            }

            if ($isMatch) {
                $typeMatch = $false
                if ($rule.AllowedChangeTypes -contains '*') {
                    $typeMatch = $true
                } elseif ($rule.AllowedChangeTypes -contains $diff.ChangeType) {
                    $typeMatch = $true
                }

                if ($typeMatch) {
                    $diff.Status = $rule.Action
                    break
                }
            }
        }

        if ($diff.Status -eq "Reject") {
            $rejectedCount++
        } else {
            $approvedCount++
        }
    }

    $finalStatus = if ($rejectedCount -eq 0) { "Approved" } else { "Rejected" }

    Write-Host "  Building HTML report..." -ForegroundColor DarkGray

    # --- NEW: Filter out 'Hide' items before generating HTML ---
    $visibleResults = @($resultsArray | Where-Object { $_.Status -ne "Hide" })

    $HtmlHead = @"
<!DOCTYPE html>
<html>
<head>
    <title>CPS Build Comparison</title>
    <style>
        /* Base Light Theme */
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f4f4f9; transition: background-color 0.3s, color 0.3s; }
        h2 { color: #333; margin: 0 0 10px 0; }
        .header-container { margin-bottom: 15px; }
        
        .status-wrapper { display: flex; align-items: center; gap: 30px; margin-bottom: 15px; }
        .build-status { font-size: 18px; font-weight: bold; padding: 10px 15px; border-radius: 4px; display: inline-block; }
        .status-Approved { background-color: #dff0d8; color: #3c763d; border: 1px solid #d6e9c6; }
        .status-Rejected { background-color: #f2dede; color: #a94442; border: 1px solid #ebccd1; }
        
        #searchInput { padding: 10px; width: 350px; border: 1px solid #ccc; border-radius: 4px; font-size: 14px; box-shadow: inset 0 1px 3px rgba(0,0,0,0.1); display: block; }
        #searchInput:focus { outline: none; border-color: #005A9E; box-shadow: 0 0 5px rgba(0,90,158,0.5); }

        table { border-collapse: collapse; min-width: 100%; width: max-content; background-color: #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.2); transition: background-color 0.3s; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; vertical-align: top; max-width: 1024ch; overflow-wrap: break-word; }
        
        th { background-color: #005A9E; color: white; font-weight: bold; white-space: nowrap; cursor: pointer; user-select: none; position: relative; padding-right: 25px; transition: background-color 0.2s; }
        th:hover { background-color: #004578; }
        th::after { content: '\21D5'; position: absolute; right: 8px; color: rgba(255,255,255,0.4); }
        th.asc::after { content: '\2191'; color: white; }
        th.desc::after { content: '\2193'; color: white; }

        .RejectRow { background-color: #ffe6e6; border-left: 5px solid #d9534f; color: #333; }
        .InformationalRow { background-color: #fdfdfd; color: #777; border-left: 5px solid #17a2b8; }
        .error-text { color: #900; font-weight: bold; }
        pre { margin: 0; font-family: Consolas, monospace; white-space: pre-wrap; word-wrap: break-word; }

        /* Toggle Switch CSS */
        .toggle-container { display: flex; flex-direction: column; align-items: center; font-size: 12px; color: #777; font-weight: bold; }
        .toggle-switch { position: relative; width: 50px; height: 24px; margin-top: 4px; }
        .toggle-switch input { opacity: 0; width: 0; height: 0; }
        .slider { position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0; background-color: #ccc; border-radius: 24px; transition: .4s; }
        .slider:before { position: absolute; content: ""; height: 18px; width: 18px; left: 3px; bottom: 3px; background-color: white; border-radius: 50%; transition: .4s; }
        input:checked + .slider { background-color: #FFF; }
        input:checked + .slider:before { transform: translateX(26px); }

        /* Dark Theme Overrides */
        body.dark-theme { background-color: #121212; color: #e0e0e0; }
        body.dark-theme h2 { color: #e0e0e0; }
        body.dark-theme .toggle-container { color: #aaa; }
        body.dark-theme .status-Approved { background-color: #1b5e20; color: #a5d6a7; border-color: #2e7d32; }
        body.dark-theme .status-Rejected { background-color: #4a1414; color: #ffcdd2; border-color: #d32f2f; }
        body.dark-theme #searchInput { background-color: #2d2d2d; color: #e0e0e0; border-color: #007BFF; }
        body.dark-theme table { background-color: #1e1e1e; }
        body.dark-theme th, body.dark-theme td { border-color: #333; }
        body.dark-theme th { background-color: #0d3b66; color: #fff; }
        body.dark-theme th:hover { background-color: #155899; }
        body.dark-theme .RejectRow { background-color: #3e1515; border-left: 5px solid #d9534f; color: #e0e0e0; }
        body.dark-theme .InformationalRow { background-color: #1e1e1e; color: #aaa; border-left: 5px solid #17a2b8; }
        body.dark-theme .error-text { color: #ff6b6b; }
        body.dark-theme .slider { background-color: #007BFF; }
    </style>
</head>
<body>
    <div class="header-container">
        <h2>Build Comparison: $PkgId $PkgVer compared to $LatestVersion</h2>
        <div class="status-wrapper">
            <div class="build-status status-$finalStatus">Build status: $finalStatus</div>
            <div class="toggle-container">
                Dark Mode
                <label class="toggle-switch">
                    <input type="checkbox" id="darkModeToggle">
                    <span class="slider"></span>
                </label>
            </div>
        </div>
        <input type="text" id="searchInput" placeholder="Search all columns...">
    </div>
    <table id="diffTable">
        <thead>
            <tr>
                <th>Status</th>
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

    if ($visibleResults.Count -eq 0) {
        [void]$HtmlBody.AppendLine("<tr class='InformationalRow'>")
        [void]$HtmlBody.AppendLine("<td colspan='10' style='text-align: center; padding: 30px; font-size: 16px; color: inherit;'><strong>No differences found (or all differences have been successfully approved and hidden).</strong></td>")
        [void]$HtmlBody.AppendLine("</tr>")
    } else {
        foreach ($diff in $visibleResults) {
            $rowClass = if ($diff.Status -eq "Reject") { "RejectRow" } else { "InformationalRow" }

            $fName = if ($null -ne $diff.FileName) { $diff.FileName } else { $diff.File }
            $rPath = if ($null -ne $diff.ReferenceFullPath) { $diff.ReferenceFullPath } else { "Path Not Available" }
            $dPath = if ($null -ne $diff.DifferenceFullPath) { $diff.DifferenceFullPath } else { "Path Not Available" }
            
            $rValRaw = if ($null -ne $diff.ReferenceValue) { $diff.ReferenceValue } else { $diff.RefData }
            $dValRaw = if ($null -ne $diff.DifferenceValue) { $diff.DifferenceValue } else { $diff.DiffData }

            $refSafe = [string]$rValRaw
            $diffSafe = [string]$dValRaw
            
            if (![string]::IsNullOrEmpty($refSafe)) { $refSafe = $refSafe.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }
            if (![string]::IsNullOrEmpty($diffSafe)) { $diffSafe = $diffSafe.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }
            
            $cType = $diff.ChangeType
            if ($cType -match 'Error') {
                $cType = "<span class='error-text'>$cType</span>"
            }

            [void]$HtmlBody.AppendLine("<tr class='$rowClass'>")
            [void]$HtmlBody.AppendLine("<td><strong>$($diff.Status)</strong></td>")
            [void]$HtmlBody.AppendLine("<td>$rPath</td>")
            [void]$HtmlBody.AppendLine("<td>$dPath</td>")
            [void]$HtmlBody.AppendLine("<td><strong>$fName</strong></td>")
            [void]$HtmlBody.AppendLine("<td>$cType</td>")
            [void]$HtmlBody.AppendLine("<td>$($diff.Location)</td>")
            [void]$HtmlBody.AppendLine("<td>$($diff.ItemName)</td>")
            [void]$HtmlBody.AppendLine("<td>$($diff.ItemProperty)</td>")
            [void]$HtmlBody.AppendLine("<td><pre style='margin:0'>$refSafe</pre></td>")
            [void]$HtmlBody.AppendLine("<td><pre style='margin:0'>$diffSafe</pre></td>")
            [void]$HtmlBody.AppendLine("</tr>")
        }
    }

    $HtmlFoot = @"
        </tbody>
    </table>

    <script>
        // --- Dark Mode Logic ---
        const toggle = document.getElementById('darkModeToggle');
        const currentTheme = localStorage.getItem('theme');
        if (currentTheme === 'dark') {
            document.body.classList.add('dark-theme');
            toggle.checked = true;
        }

        toggle.addEventListener('change', function() {
            if (this.checked) {
                document.body.classList.add('dark-theme');
                localStorage.setItem('theme', 'dark');
            } else {
                document.body.classList.remove('dark-theme');
                localStorage.setItem('theme', 'light');
            }
        });

        // --- Instant Search Logic ---
        document.getElementById('searchInput').addEventListener('input', function() {
            const filterText = this.value.toLowerCase();
            const rows = document.querySelectorAll('#diffTable tbody tr');
            
            rows.forEach(row => {
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

        // --- Default Sort (Status Descending) ---
        const statusHeader = document.querySelector('th');
        if (statusHeader) {
            statusHeader.classList.add('asc'); 
            statusHeader.click();
        }
    </script>
</body>
</html>
"@

    Set-Content -Path $ReportPath -Value ($HtmlHead + $HtmlBody.ToString() + $HtmlFoot) -Encoding UTF8
    
    if ($finalStatus -eq "Approved") {
        Write-Host "  Build status: Approved" -ForegroundColor Green
    } else {
        Write-Host "  Build status: Rejected ($rejectedCount blockers found)" -ForegroundColor Red
    }
    Write-Host ("  HTML Report generated: {0}" -f $ReportPath) -ForegroundColor Green
}