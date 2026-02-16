<#
.SYNOPSIS
Exports a settings report for selected Intune Administrative Templates (Group Policy Configurations).
.DESCRIPTION
When the Administrative Template Report button is clicked, this handler:
  - Validates policy selection
  - Deduplicates selected policies by ID
  - Retrieves raw definitionValues for each unique policy
  - Flattens settings via Flatten-AdminTemplateSettings function
  - Fetches friendly names from Group Policy Definitions via Graph API
  - Outputs Markdown, CSV, or HTML report with setting names, descriptions, and configured values
#>
$AdminTemplateReportButton.Add_Click({
    try {
        Write-IntuneToolkitLog "AdminTemplateReportButton clicked" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"

        # Validate UI selection
        if (-not $PolicyDataGrid.SelectedItems -or $PolicyDataGrid.SelectedItems.Count -eq 0) {
            Write-IntuneToolkitLog "No policies selected." -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"
            [System.Windows.MessageBox]::Show("Select one or more Administrative Template policies.", "Information")
            return
        }

        # Deduplicate selected policies by ID
        $uniquePolicies = $PolicyDataGrid.SelectedItems |
            Group-Object -Property { if ($_.PSObject.Properties['PolicyId']) { $_.PolicyId } else { $_.id } } |
            ForEach-Object { $_.Group[0] }
        Write-IntuneToolkitLog "Unique policies count: $($uniquePolicies.Count)" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"

        # Fetch & merge raw definitionValues
        $mergedSettings = @()
        foreach ($policy in $uniquePolicies) {
            $policyId = if ($policy.PSObject.Properties['PolicyId']) { $policy.PolicyId } else { $policy.id }
            Write-IntuneToolkitLog "Fetching details for policy: $($policyId)" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"
            
            # Fetch policy details
            $policyUrl = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations/$($policyId)"
            try {
                $detail = Invoke-MgGraphRequest -Uri $policyUrl -Method GET
            } catch {
                Write-IntuneToolkitLog "Error fetching policy $($policyId): $($_.Exception.Message)" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"
                continue
            }
            
            # Fetch definitionValues with expanded definition object
            $definitionValuesUrl = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations/$($policyId)/definitionValues?`$expand=definition"
            try {
                $definitionValuesResponse = Invoke-MgGraphRequest -Uri $definitionValuesUrl -Method GET
                $detail.definitionValues = if ($definitionValuesResponse.value) { $definitionValuesResponse.value } else { @() }
            } catch {
                Write-IntuneToolkitLog "Error fetching definitionValues for policy $($policyId): $($_.Exception.Message)" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"
                $detail.definitionValues = @()
            }
            
            if ($detail.definitionValues -and $detail.definitionValues.Count -gt 0) {
                $settingsArray = if ($detail.definitionValues -is [System.Array]) { $detail.definitionValues } else { @($detail.definitionValues) }
                Write-IntuneToolkitLog "Policy '$($detail.displayName)' returned $($settingsArray.Count) definitionValues" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"
                
                # Fetch presentationValues for each definitionValue
                foreach ($s in $settingsArray) {
                    if (-not $s.definition) {
                        Write-IntuneToolkitLog "Skipping entry without definition object" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"
                        continue
                    }
                    
                    # Fetch presentationValues for this definitionValue
                    $defValueId = if ($s.id) { $s.id } elseif ($s['id']) { $s['id'] } else { $null }
                    if ($defValueId) {
                        try {
                            $presValuesUrl = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations/$($policyId)/definitionValues('$defValueId')/presentationValues"
                            $presValuesResponse = Invoke-MgGraphRequest -Uri $presValuesUrl -Method GET
                            if ($presValuesResponse.value) {
                                $s.presentationValues = $presValuesResponse.value
                                Write-IntuneToolkitLog "Fetched $($presValuesResponse.value.Count) presentationValues for definitionValue $defValueId" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"
                            }
                        } catch {
                            Write-IntuneToolkitLog "Error fetching presentationValues for definitionValue $($defValueId): $($_.Exception.Message)" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"
                        }
                    }
                    
                    $mergedSettings += [PSCustomObject]@{
                        PolicyName = $detail.displayName
                        Setting    = $s
                    }
                }
            } else {
                Write-IntuneToolkitLog "Policy $($detail.displayName) has no definitionValues to merge." -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"
            }
        }
        Write-IntuneToolkitLog "Total merged settings: $($mergedSettings.Count)" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"

        if ($mergedSettings.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No configurable settings found.", "Information")
            return
        }

        # Flatten settings
        $definitionCache = @{}
        $flattened = Flatten-AdminTemplateSettings -MergedPolicy $mergedSettings -DefinitionCache $definitionCache
        Write-IntuneToolkitLog "Flattened entries count: $($flattened.Count)" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"

        # Group by definition GUID to combine duplicates
        $grouped = $flattened | Group-Object -Property DefinitionGuid

        # Prepare report items
        $reportItems = @()
        foreach ($group in $grouped) {
            $guid = $group.Name
            if (-not $guid) { continue }
            $policiesList = ($group.Group | ForEach-Object { $_.PolicyName }) -join "; "
            $settingName = ($group.Group | Select-Object -First 1).SettingName
            $description = ($group.Group | Select-Object -First 1).Description
            $categoryPath = ($group.Group | Select-Object -First 1).CategoryPath
            $uniqueVals = ($group.Group | ForEach-Object { $_.ConfiguredValue }) | Select-Object -Unique
            $valueDisplay = ($uniqueVals -join "; ").Trim()
            
            $reportItems += [PSCustomObject]@{
                PolicyName      = $policiesList
                Setting         = $settingName
                CategoryPath    = $categoryPath
                Description     = $description
                ConfiguredValue = $valueDisplay
                Duplicates      = [bool]($group.Count -gt 1)
                DefinitionGuid  = $guid
            }
        }
        Write-IntuneToolkitLog "Report items prepared: $($reportItems.Count)" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"

        # Show export options
        $formats = Show-ExportOptionsDialog
        if (-not $formats -or $formats.Count -eq 0) { return }
        Add-Type -AssemblyName System.Windows.Forms
        $baseName = "AdminTemplateReport_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"

        foreach ($fmt in $formats) {
            switch ($fmt) {
                'Markdown' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter = 'Markdown (*.md)|*.md|All (*.*)|*.*'
                    $dlg.Title = 'Save Administrative Template Report'
                    $dlg.FileName = "$baseName.md"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        # Overview of shared settings
                        $overview = foreach ($g in $grouped | Where-Object { $_.Count -gt 1 }) {
                            $name = ($g.Group | Select-Object -First 1).SettingName
                            $pols = ($g.Group | ForEach-Object { $_.PolicyName }) -join "; "
                            "- **$name** configured in policies: $pols"
                        }
                        $md = @('# Administrative Template Report', '', '## Overview: Shared Settings', '')
                        if ($overview) { $md += $overview } else { $md += '- No settings shared across multiple policies.' }
                        $md += @('', '| Policy Name | Setting | Category | Description | Value |', '|-------------|---------|----------|-------------|-------|')
                        foreach ($r in $reportItems) {
                            $md += "| $($r.PolicyName) | $($r.Setting) | $($r.CategoryPath) | $($r.Description) | $($r.ConfiguredValue) |"
                        }
                        $md -join "`r`n" | Out-File -FilePath $dlg.FileName -Encoding UTF8
                        Write-IntuneToolkitLog "Markdown report saved to: $($dlg.FileName)" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"
                    }
                }
                'CSV' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter = 'CSV (*.csv)|*.csv|All (*.*)|*.*'
                    $dlg.Title = 'Save Administrative Template Report CSV'
                    $dlg.FileName = "$baseName.csv"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        $reportItems | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8 -Delimiter ';'
                        Write-IntuneToolkitLog "CSV report saved to: $($dlg.FileName)" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"
                    }
                }
                'HTML' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter = 'HTML (*.html)|*.html|All (*.*)|*.*'
                    $dlg.Title = 'Save Administrative Template Report HTML'
                    $dlg.FileName = "$baseName.html"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        try {
                            Add-Type -AssemblyName System.Web
                        } catch {}
                        
                        # Build category metadata
                        $allCategories = @()
                        $categoryCounts = @{}
                        foreach ($ri in $reportItems) {
                            if ($ri.CategoryPath) {
                                $allCategories += $ri.CategoryPath
                                $c = $ri.CategoryPath
                                if (-not $categoryCounts.ContainsKey($c)) { $categoryCounts[$c] = 0 }
                                $categoryCounts[$c]++
                            }
                        }
                        $allCategories = $allCategories | Where-Object { $_ -and $_.Trim() -ne '' } | Sort-Object -Unique
                        $categoryOptionsHtml = ($allCategories | ForEach-Object { 
                            $catEsc = [System.Web.HttpUtility]::HtmlEncode($_)
                            $count = $categoryCounts[$_]
                            $idSafe = ($catEsc -replace "[^a-zA-Z0-9_-]", "_")
                            "<div class='form-check form-check-sm'><input class='form-check-input category-filter-cb' type='checkbox' value='$catEsc' id='cat_$idSafe'><label class='form-check-label small' for='cat_$idSafe'>$catEsc <span class='text-muted'>($count)</span></label></div>"
                        }) -join "`n"

                        $totalPolicies = $uniquePolicies.Count
                        $totalSettings = $reportItems.Count
                        $duplicateCount = ($reportItems | Where-Object { $_.Duplicates }).Count
                        $uniqueCount = $totalSettings - $duplicateCount
                        function _pct($n, $d) { if ($d) { [math]::Round(($n / $d) * 100, 1) } else { 0 } }
                        $dupPct = _pct $duplicateCount $totalSettings
                        $uniqPct = _pct $uniqueCount $totalSettings

                        $rowsHtml = foreach ($r in $reportItems) {
                            $policyEsc = [System.Web.HttpUtility]::HtmlEncode($r.PolicyName)
                            $settingEsc = [System.Web.HttpUtility]::HtmlEncode($r.Setting)
                            $categoryEsc = [System.Web.HttpUtility]::HtmlEncode($r.CategoryPath)
                            $descRaw = if ($r.Description) { $r.Description } else { '' }
                            $descEsc = [System.Web.HttpUtility]::HtmlEncode(($descRaw -replace "`r?`n", " "))
                            $valEsc = [System.Web.HttpUtility]::HtmlEncode($r.ConfiguredValue)
                            $dupAttr = if ($r.Duplicates) { '1' } else { '0' }
                            $dupBadge = if ($r.Duplicates) { "<span class='cmp-badge badge-diff'>Duplicate</span>" } else { "<span class='cmp-badge badge-match'>Unique</span>" }
                            $catLower = if ($r.CategoryPath) { $r.CategoryPath.ToLower() } else { '' }
                            "<tr data-dup='$dupAttr' data-category='$catLower'><td data-colkey='PolicyName'>$policyEsc</td><td data-colkey='Setting'>$settingEsc</td><td data-colkey='Category'>$categoryEsc</td><td data-colkey='Description' class='text-muted small desc-cell'><div class='desc-text clamp'>$descEsc</div><button type='button' class='btn btn-link p-0 small more-btn' onclick='toggleDesc(this)'>More</button></td><td data-colkey='ConfiguredValue'>$valEsc</td><td data-colkey='DuplicateStatus'>$dupBadge</td></tr>"
                        }

                        # Icon (optional)
                        $iconBase64 = ''
                        $headerLogoBase64 = ''
                        $headerLogoMime = 'image/png'
                        $iconPathIco = Join-Path -Path (Get-Location) -ChildPath 'Intune-toolkit.ico'
                        if (Test-Path $iconPathIco) { $bytesIco = [System.IO.File]::ReadAllBytes($iconPathIco); $iconBase64 = [Convert]::ToBase64String($bytesIco) }
                        $logoPathPng = Join-Path -Path (Get-Location) -ChildPath 'Intune-toolkit.png'
                        if (Test-Path $logoPathPng) { $logoBytes = [System.IO.File]::ReadAllBytes($logoPathPng); $headerLogoBase64 = [Convert]::ToBase64String($logoBytes) } elseif ($iconBase64) { $headerLogoBase64 = $iconBase64; $headerLogoMime = 'image/x-icon' }
                        $iconImg = if ($headerLogoBase64) { "<img src='data:$headerLogoMime;base64,$headerLogoBase64' class='header-logo' alt='Intune Toolkit Logo'>" } else { '' }

                        $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        $tenant = try { (Invoke-MgGraphRequest -Uri 'https://graph.microsoft.com/v1.0/organization' -Method GET).value[0].displayName } catch { 'Unknown Tenant' }

                        $html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='utf-8'/>
<title>Administrative Template Report</title>
<meta name='viewport' content='width=device-width,initial-scale=1'/>
<link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css' rel='stylesheet'/>
<link rel='icon' type='image/x-icon' href='data:image/x-icon;base64,$iconBase64'>
<style>
:root { --primary:#007ACC; --primary-dark:#005A9E; --muted:#888888; }
body{padding:24px;background:#f5f7fa;font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;}
.header-logo{width:64px;height:64px;border-radius:12px;box-shadow:0 3px 8px rgba(0,0,0,.18);background:#fff;padding:6px;object-fit:contain;}
.header-bar{background:linear-gradient(135deg,var(--primary-dark),var(--primary));color:#fff;border-radius:12px;padding:18px 24px;box-shadow:0 4px 12px rgba(0,0,0,.15);}
table{font-size:.9rem;}
thead.sticky-top th{background:linear-gradient(135deg,var(--primary-dark),var(--primary));color:#fff;white-space:nowrap;position:sticky;top:0;z-index:20;}
.summary-badge{font-size:.75rem;padding:.45em .65em;border-radius:8px;font-weight:600;}
.badge-match{background:#198754;color:#fff;}
.badge-diff{background:#ffc107;color:#212529;}
.cmp-badge{font-size:.70rem;padding:.30em .65em;border-radius:6px;font-weight:600;letter-spacing:.03em;white-space:nowrap;}
.cmp-badge.badge-match{background:#198754;color:#fff;}
.cmp-badge.badge-diff{background:#0d6efd;color:#fff;}
.search-box{max-width:340px;}
.card{border-radius:14px;box-shadow:0 2px 6px rgba(0,0,0,.08);}
.desc-text.clamp{display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden;max-height:4.5em;}
.desc-text.expanded{overflow:visible;max-height:none;}
.more-btn{display:block;margin-top:2px;}
thead th{position:relative;}
.col-resizer{position:absolute;top:0;right:0;width:6px;cursor:col-resize;user-select:none;height:100%;}
html.resizing, html.resizing * {cursor:col-resize !important;}
table#settingsTable { table-layout:auto; }
#settingsTable th,#settingsTable td{word-break:break-word;vertical-align:top;}
.desc-cell{max-width:420px;}
.offcanvas-categories{width:320px;}
.filter-active-indicator{width:10px;height:10px;border-radius:50%;background:#198754;display:inline-block;margin-left:6px;box-shadow:0 0 0 3px rgba(25,135,84,.25);}
.scroll-top-btn{position:fixed;bottom:24px;right:24px;display:none;z-index:999;box-shadow:0 3px 10px rgba(0,0,0,.25);}
</style>
</head>
<body>
<div class='container-fluid'>
    <div class='header-bar mb-4 d-flex flex-wrap justify-content-between align-items-center gap-4'>
    <div class='d-flex align-items-center gap-3'>$iconImg<div><h1 class='h4 mb-1'>Administrative Template Report</h1><div class='small opacity-75'>Tenant: $tenant | Generated: $generated</div><div class='small opacity-75'>Policies: $totalPolicies</div></div></div>
    <div class='search-box'><input id='blSearch' onkeyup='filterBaselineTbl()' class='form-control form-control-sm' placeholder='Search report...'></div>
    </div>
    <div class='row g-3 mb-4 align-items-stretch'>
        <div class='col-12 col-md-6 col-xl-3'>
            <div class='card h-100'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Total Settings</h6><div class='h4 mb-0'><span id='totalSettingsCount'>$totalSettings</span></div></div></div>
        </div>
        <div class='col-12 col-md-6 col-xl-3'>
            <div class='card h-100'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Duplicates</h6><div class='h4 mb-0'><span id='duplicatesCount'>$duplicateCount</span> <span class='summary-badge badge-diff ms-1'><span id='duplicatesPct'>$dupPct</span>%</span></div></div></div>
        </div>
        <div class='col-12 col-md-6 col-xl-3'>
            <div class='card h-100'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Unique</h6><div class='h4 mb-0'><span id='uniqueCount'>$uniqueCount</span> <span class='summary-badge badge-match ms-1'><span id='uniquePct'>$uniqPct</span>%</span></div></div></div>
        </div>
        <div class='col-12 col-md-6 col-xl-3 d-flex'>
            <div class='card h-100 w-100 advanced-filter-toggle' data-bs-toggle='offcanvas' data-bs-target='#offcanvasFilters' aria-controls='offcanvasFilters'>
                <div class='card-body d-flex flex-column justify-content-center'>
                    <h6 class='text-uppercase small text-muted mb-2'>Filters</h6>
                    <div class='h6 mb-0'>Categories & Columns <span id='activeFilterDot' style='display:none;' class='filter-active-indicator'></span></div>
                    <div class='small text-muted mt-1'>Click to refine</div>
                </div>
            </div>
        </div>
    </div>
    <div class='offcanvas offcanvas-end offcanvas-categories' tabindex='-1' id='offcanvasFilters' aria-labelledby='offcanvasFiltersLabel'>
        <div class='offcanvas-header'>
            <h5 class='offcanvas-title' id='offcanvasFiltersLabel'>Filter & Refine</h5>
            <button type='button' class='btn-close text-reset' data-bs-dismiss='offcanvas' aria-label='Close'></button>
        </div>
        <div class='offcanvas-body d-flex flex-column'>
            <div class='mb-3'>
                <h6 class='text-muted text-uppercase small mb-2'>Column Visibility</h6>
                <div id='columnVisibilityContainer' class='d-flex flex-wrap gap-2 mb-3'></div>
                <h6 class='text-muted text-uppercase small mb-2 mt-2'>Categories</h6>
                <input type='text' id='categorySearchInput' class='form-control form-control-sm mb-2' placeholder='Search categories...'>
                <div class='overflow-auto border rounded p-2' style='max-height:180px' id='categoryCheckboxContainer'>$categoryOptionsHtml</div>
                <div class='mt-2 d-flex gap-2 flex-wrap'>
                    <button class='btn btn-sm btn-primary' type='button' onclick='applyCategoryFilters()'>Apply</button>
                    <button class='btn btn-sm btn-outline-secondary' type='button' onclick='clearCategoryFilters()'>Clear</button>
                    <button class='btn btn-sm btn-outline-primary' type='button' onclick='selectAllCategoryFilters()'>Select All</button>
                </div>
            </div>
            <hr/>
            <div class='mb-2'>
                <h6 class='text-muted text-uppercase small mb-2'>Duplicates Filter</h6>
                <div class='btn-group btn-group-sm' role='group'>
                    <button type='button' class='btn btn-outline-primary active' data-dup-filter='all'>All</button>
                    <button type='button' class='btn btn-outline-primary' data-dup-filter='dup'>Duplicates</button>
                    <button type='button' class='btn btn-outline-primary' data-dup-filter='unique'>Unique</button>
                </div>
            </div>
        </div>
    </div>
    <div class='card mb-4'>
        <div class='card-body'>
            <h2 class='h5 text-primary mb-3'>Policy Settings</h2>
            <div class='table-responsive'>
                <table id='settingsTable' class='table table-sm table-hover align-middle'>
                    <thead class='sticky-top'><tr>
                        <th data-colkey='PolicyName'>Policy Name(s)</th>
                        <th data-colkey='Setting'>Setting</th>
                        <th data-colkey='Category'>Category</th>
                        <th data-colkey='Description'>Description</th>
                        <th data-colkey='ConfiguredValue'>Configured Value</th>
                        <th data-colkey='DuplicateStatus'>Duplicates</th>
                    </tr></thead>
                    <tbody>
$($rowsHtml -join "`n")
                    </tbody>
                </table>
            </div>
        </div>
    </div>
    <div class='text-center small text-muted mt-4 mb-3'>Generated by Intune Toolkit • Administrative Template Report</div>
</div>
<button id='scrollTopBtn' class='scroll-top-btn btn btn-primary btn-sm'>Top</button>
<script>
function toggleDesc(btn){ const wrapper=btn.previousElementSibling; if(wrapper.classList.contains('expanded')){ wrapper.classList.remove('expanded'); wrapper.classList.add('clamp'); btn.textContent='More'; } else { wrapper.classList.remove('clamp'); wrapper.classList.add('expanded'); btn.textContent='Less'; } }
function makeColsResizable(tableId){ const table=document.getElementById(tableId); if(!table) return; const ths=[...table.querySelectorAll('thead th')]; ths.forEach((th,idx)=>{ if(th.querySelector('.col-resizer')) return; th.style.position='relative'; const grip=document.createElement('span'); grip.className='col-resizer'; grip.title='Drag to resize'; th.appendChild(grip); let startX,startWidth; grip.addEventListener('mousedown',e=>{ startX=e.pageX; startWidth=th.offsetWidth; document.documentElement.classList.add('resizing'); function onMove(ev){ let w=startWidth+(ev.pageX-startX); if(w<60) w=60; th.style.width=w+'px'; table.querySelectorAll('tbody tr').forEach(r=>{ if(r.children[idx]) r.children[idx].style.width=w+'px'; }); } function onUp(){ document.removeEventListener('mousemove',onMove); document.removeEventListener('mouseup',onUp); document.documentElement.classList.remove('resizing'); } document.addEventListener('mousemove',onMove); document.addEventListener('mouseup',onUp); e.preventDefault(); e.stopPropagation(); }); }); }
function handleScrollTopBtn(){ const btn=document.getElementById('scrollTopBtn'); if(!btn) return; btn.style.display= window.scrollY>300 ? 'block':'none'; } window.addEventListener('scroll',handleScrollTopBtn);
let currentSelectedCategories=[];
function applyCategoryFilters(){ const cbs=document.querySelectorAll('.category-filter-cb'); currentSelectedCategories=[...cbs].filter(cb=>cb.checked).map(cb=>cb.value.toLowerCase()); filterByCategory(); const dot=document.getElementById('activeFilterDot'); if(dot){ dot.style.display=currentSelectedCategories.length>0?'inline-block':'none'; } }
function filterByCategory(){ const rows=document.querySelectorAll('#settingsTable tbody tr'); rows.forEach(r=>{ if(currentSelectedCategories.length===0){ r.dataset.categoryfiltered='0'; } else { const cat=(r.getAttribute('data-category')||'').toLowerCase(); r.dataset.categoryfiltered= currentSelectedCategories.includes(cat)?'0':'1'; } }); applyCombinedVisibility(); }
function clearCategoryFilters(){ document.querySelectorAll('.category-filter-cb').forEach(cb=> cb.checked=false); currentSelectedCategories=[]; filterByCategory(); const dot=document.getElementById('activeFilterDot'); if(dot){ dot.style.display='none'; } }
function selectAllCategoryFilters(){ document.querySelectorAll('.category-filter-cb').forEach(cb=> cb.checked=true); }
function filterBaselineTbl(){ const searchEl=document.getElementById('blSearch'); const q=(searchEl ? searchEl.value : '').toLowerCase(); document.querySelectorAll('#settingsTable tbody tr').forEach(r=>{ const match=[...r.children].some(td=> td.textContent.toLowerCase().includes(q)); r.dataset.searchHidden = match ? '0' : '1'; }); applyCombinedVisibility(); }
function applyCombinedVisibility(){ const dupMode=(document.querySelector('[data-dup-filter].active')||{getAttribute:()=> 'all'}).getAttribute('data-dup-filter'); const rows=document.querySelectorAll('#settingsTable tbody tr'); rows.forEach(r=>{ let hide = (r.dataset.searchHidden==='1' || r.dataset.categoryfiltered==='1'); if(!hide){ const dup = r.getAttribute('data-dup')==='1'; if(dupMode==='dup' && !dup) hide=true; if(dupMode==='unique' && dup) hide=true; } r.style.display = hide ? 'none' : ''; }); updateSummaryStats(); }
function updateSummaryStats(){ const rows=[...document.querySelectorAll('#settingsTable tbody tr')]; const visible=rows.filter(r=> r.style.display!=='none'); const totalVisible=visible.length; const dup=visible.filter(r=> r.getAttribute('data-dup')==='1').length; const uniq=totalVisible-dup; const pct=(n)=> totalVisible? ((n/totalVisible)*100).toFixed(1).replace(/\.0$/,''):'0'; function setTxt(id,v){ const el=document.getElementById(id); if(el) el.textContent=v; } setTxt('totalSettingsCount', totalVisible); setTxt('duplicatesCount', dup); setTxt('uniqueCount', uniq); setTxt('duplicatesPct', pct(dup)); setTxt('uniquePct', pct(uniq)); }
document.addEventListener('input',function(e){ if(e.target && e.target.id==='categorySearchInput'){ const q=e.target.value.toLowerCase(); document.querySelectorAll('#categoryCheckboxContainer .form-check').forEach(div=>{ const txt=div.textContent.toLowerCase(); div.style.display = txt.includes(q)?'':'none'; }); } });
document.addEventListener('input', e=>{ if(e.target && e.target.id==='blSearch'){ filterBaselineTbl(); } });
document.addEventListener('change', e=>{ if(e.target && e.target.classList.contains('category-filter-cb')){ applyCategoryFilters(); } });
document.addEventListener('DOMContentLoaded',()=>{ makeColsResizable('settingsTable'); handleScrollTopBtn(); const t=document.getElementById('scrollTopBtn'); if(t){ t.addEventListener('click',()=>window.scrollTo({top:0,behavior:'smooth'})); }
    const colContainer=document.getElementById('columnVisibilityContainer'); if(colContainer){ const headers=document.querySelectorAll('#settingsTable thead th[data-colkey]'); headers.forEach(h=>{ const key=h.getAttribute('data-colkey'); const label=h.textContent.trim(); const id='colvis_'+key; const div=document.createElement('div'); div.className='form-check form-check-sm me-2'; div.innerHTML='<input class="form-check-input col-vis-cb" type="checkbox" id="'+id+'" data-colkey="'+key+'" checked><label class="form-check-label small" for="'+id+'">'+label+'</label>'; colContainer.appendChild(div); }); colContainer.addEventListener('change', e=>{ const cb=e.target.closest('.col-vis-cb'); if(!cb) return; const key=cb.getAttribute('data-colkey'); document.querySelectorAll('#settingsTable [data-colkey="'+key+'"]').forEach(cell=>{ cell.style.display = cb.checked? '' : 'none'; }); }); }
    document.querySelectorAll('[data-dup-filter]').forEach(btn=>{ btn.addEventListener('click',()=>{ document.querySelectorAll('[data-dup-filter]').forEach(b=>b.classList.remove('active')); btn.classList.add('active'); applyCombinedVisibility(); }); });
    document.querySelectorAll('#settingsTable tbody tr').forEach(r=>{ r.dataset.searchHidden='0'; r.dataset.categoryfiltered='0'; });
    filterBaselineTbl(); updateSummaryStats();
});
</script>
<script src='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js'></script>
</body>
</html>
"@
                        $html | Out-File -FilePath $dlg.FileName -Encoding UTF8
                        Write-IntuneToolkitLog "HTML report saved to: $($dlg.FileName)" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"
                        try { Start-Process -FilePath $dlg.FileName } catch {}
                    }
                }
            }
        }

        [System.Windows.MessageBox]::Show("Export complete.", "Success")
    } catch {
        Write-IntuneToolkitLog "Error: $($_.Exception.Message)" -component "AdminTemplateReport-Button" -file "AdminTemplateReportButton.ps1"
        [System.Windows.MessageBox]::Show("Failed to generate administrative template report: $($_.Exception.Message)", "Error")
    }
})
