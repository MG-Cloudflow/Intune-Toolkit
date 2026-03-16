<#
.SYNOPSIS
Exports a settings report for selected Device Configuration policies.

.DESCRIPTION
When the Device Config Report button is clicked, this handler:
  - Validates policy selection
  - Retrieves Device Configuration policies from Graph API
  - Flattens settings including nested objects
  - Generates HTML/CSV/Markdown reports with expandable nested object sections
  - Includes "Show Not Configured" toggle to filter null/empty properties
#>
$DeviceConfigReportButton.Add_Click({
    try {
        Write-IntuneToolkitLog "DeviceConfigReportButton clicked" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"

        # Validate UI selection
        if (-not $PolicyDataGrid.SelectedItems -or $PolicyDataGrid.SelectedItems.Count -eq 0) {
            Write-IntuneToolkitLog "No policies selected." -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"
            [System.Windows.MessageBox]::Show("Select one or more Device Configuration policies.", "Information")
            return
        }

        # Deduplicate selected policies by ID
        $uniquePolicies = $PolicyDataGrid.SelectedItems |
            Group-Object -Property PolicyId |
            ForEach-Object { $_.Group[0] }
        Write-IntuneToolkitLog "Unique policies count: $($uniquePolicies.Count)" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"

        # Fetch full policy details
        $mergedSettings = [System.Collections.ArrayList]@()
        foreach ($policy in $uniquePolicies) {
            $policyId = $policy.PolicyId
            Write-IntuneToolkitLog "Fetching details for policy: $($policyId)" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"
            $url = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($policyId)"
            try {
                $detail = Invoke-MgGraphRequest -Method GET -Uri $url
                $null = $mergedSettings.Add(@{
                    PolicyName = $detail.displayName
                    Policy     = $detail
                })
            } catch {
                Write-IntuneToolkitLog "Failed to fetch policy $($policyId): $($_.Exception.Message)" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"
            }
        }
        Write-IntuneToolkitLog "Total merged policies: $($mergedSettings.Count)" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"

        if ($mergedSettings.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No policies could be retrieved.", "Information")
            return
        }

        # Flatten settings
        $flattened = Flatten-DeviceConfiguration -MergedPolicy $mergedSettings
        Write-IntuneToolkitLog "Flattened entries count: $($flattened.Count)" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"

        # Filter out not configured settings
        $flattened = $flattened | Where-Object { $_.IsConfigured -eq $true }
        Write-IntuneToolkitLog "Configured entries count: $($flattened.Count)" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"

        if ($flattened.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No configurable settings found.", "Information")
            return
        }

        # Prepare report items - show each policy-property combination separately
        $reportItems = [System.Collections.ArrayList]@()
        foreach ($item in $flattened) {
            $propertyPath = $item.PropertyPath
            if (-not $propertyPath) { continue }
            
            # Get @odata.type from the policy for categorization
            $policyData = ($mergedSettings | Where-Object { $_.PolicyName -eq $item.PolicyName }).Policy
            $odataType = if ($policyData -is [hashtable]) {
                $policyData['@odata.type']
            } else {
                $policyData.'@odata.type'
            }
            
            # Extract friendly type name
            $configType = if ($odataType -match '#microsoft\.graph\.(.+)$') {
                $Matches[1]
            } else {
                "Unknown"
            }
            
            $null = $reportItems.Add([PSCustomObject]@{
                PolicyName      = $item.PolicyName
                PropertyPath    = $propertyPath
                PropertyType    = $item.PropertyType
                ConfiguredValue = $item.Value
                IsConfigured    = $item.IsConfigured
                IsNested        = $item.IsNested
                NestingLevel    = $item.NestingLevel
                ConfigType      = $configType
                ODataType       = $odataType
            })
        }

        Write-IntuneToolkitLog "Report items prepared: $($reportItems.Count)" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"

        # Detect duplicates - properties that appear in multiple policies
        $propertyGroups = $reportItems | Group-Object -Property PropertyPath
        foreach ($group in $propertyGroups) {
            $isDuplicate = $group.Count -gt 1
            foreach ($item in $group.Group) {
                $item | Add-Member -NotePropertyName "IsDuplicate" -NotePropertyValue $isDuplicate -Force
            }
        }

        # Count unique property names and duplicates
        $uniqueProperties = ($reportItems | Select-Object -Property PropertyPath -Unique).Count
        $duplicateCount = ($reportItems | Where-Object { $_.IsDuplicate }).Count

        # Summary stats
        $totalConfigured = $reportItems.Count
        Write-IntuneToolkitLog "Total configured: $totalConfigured, Unique properties: $uniqueProperties, Duplicates: $duplicateCount" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"

        # Show export options dialog
        $exportChoice = Show-ExportOptionsDialog
        if (-not $exportChoice) {
            Write-IntuneToolkitLog "User cancelled export" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"
            return
        }

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $baseName = "DeviceConfigReport_$timestamp"

        # === MARKDOWN EXPORT ===
        if ($exportChoice -eq "Markdown") {
            $saveFileDialog = New-Object Microsoft.Win32.SaveFileDialog
            $saveFileDialog.Filter = "Markdown files (*.md)|*.md"
            $saveFileDialog.FileName = "$baseName.md"
            if ($saveFileDialog.ShowDialog()) {
                $mdLines = @()
                $mdLines += "# Device Configuration Report"
                $mdLines += ""
                $mdLines += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $mdLines += "**Policies:** $($uniquePolicies.Count)"
                $mdLines += "**Total Settings:** $totalConfigured"
                $mdLines += "**Unique Properties:** $uniqueProperties"
                $mdLines += "**Duplicates:** $duplicateCount"
                $mdLines += ""
                $mdLines += "*Note: Only configured settings are shown. Not configured properties are excluded. Each policy-property combination is listed separately. Duplicates are properties configured in multiple policies.*"
                $mdLines += ""
                $mdLines += "## Settings"
                $mdLines += ""
                $mdLines += "| Policy Name | Property Path | Type | Configured Value | Status | Duplicate | Config Type |"
                $mdLines += "|-------------|---------------|------|------------------|--------|-----------|-------------|"
                
                foreach ($item in $reportItems) {
                    $status = if ($item.IsConfigured) { "Configured" } else { "Not Configured" }
                    $dupStatus = if ($item.IsDuplicate) { "Yes" } else { "No" }
                    $value = if ($item.ConfiguredValue) { $item.ConfiguredValue } else { "(null)" }
                    $indent = "  " * $item.NestingLevel
                    $propertyDisplay = "$indent$($item.PropertyPath)"
                    $mdLines += "| $($item.PolicyName) | $propertyDisplay | $($item.PropertyType) | $value | $status | $dupStatus | $($item.ConfigType) |"
                }
                
                $mdContent = $mdLines -join "`r`n"
                Set-Content -Path $saveFileDialog.FileName -Value $mdContent -Encoding UTF8
                Write-IntuneToolkitLog "Markdown report saved: $($saveFileDialog.FileName)" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"
                [System.Windows.MessageBox]::Show("Markdown report saved to:`n$($saveFileDialog.FileName)", "Success")
            }
        }

        # === CSV EXPORT ===
        elseif ($exportChoice -eq "CSV") {
            $saveFileDialog = New-Object Microsoft.Win32.SaveFileDialog
            $saveFileDialog.Filter = "CSV files (*.csv)|*.csv"
            $saveFileDialog.FileName = "$baseName.csv"
            if ($saveFileDialog.ShowDialog()) {
                $csvData = $reportItems | Select-Object PolicyName, PropertyPath, PropertyType, ConfiguredValue, IsConfigured, IsNested, NestingLevel, IsDuplicate, ConfigType, ODataType
                $csvData | Export-Csv -Path $saveFileDialog.FileName -Delimiter ';' -NoTypeInformation -Encoding UTF8
                Write-IntuneToolkitLog "CSV report saved: $($saveFileDialog.FileName)" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"
                [System.Windows.MessageBox]::Show("CSV report saved to:`n$($saveFileDialog.FileName)", "Success")
            }
        }

        # === HTML EXPORT ===
        elseif ($exportChoice -eq "HTML") {
            try {
                Add-Type -AssemblyName System.Web
            } catch {}
            
            # Generate HTML report
            $totalPolicies = $uniquePolicies.Count
            $totalSettings = $reportItems.Count
            $duplicateCount = ($reportItems | Where-Object { $_.IsDuplicate }).Count
            $uniqueCount = $totalSettings - $duplicateCount
            
            function _pct($n,$d){ if($d){ [math]::Round(($n/$d)*100,1) } else { 0 } }
            $dupPct = _pct $duplicateCount $totalSettings
            $uniqPct = _pct $uniqueCount $totalSettings
            
            # Get unique config types for filter
            $configTypes = $reportItems | Select-Object -ExpandProperty ConfigType -Unique | Sort-Object
            $configTypeFilterOptions = ($configTypes | ForEach-Object { 
                $typeEsc = [System.Web.HttpUtility]::HtmlEncode($_)
                $idSafe = ($typeEsc -replace "[^a-zA-Z0-9_-]","_")
                "<div class='form-check form-check-sm'><input class='form-check-input configtype-filter-cb' type='checkbox' value='$typeEsc' id='type_$idSafe' checked><label class='form-check-label small' for='type_$idSafe'>$typeEsc</label></div>"
            }) -join "`n"
            
            # Build table rows
            $rowsHtml = foreach ($item in $reportItems) {
                $indent = "&nbsp;&nbsp;" * $item.NestingLevel
                $propertyEsc = [System.Web.HttpUtility]::HtmlEncode("$indent$($item.PropertyPath)")
                $policyEsc = [System.Web.HttpUtility]::HtmlEncode($item.PolicyName)
                $typeEsc = [System.Web.HttpUtility]::HtmlEncode($item.PropertyType)
                $valueEsc = [System.Web.HttpUtility]::HtmlEncode($item.ConfiguredValue)
                $configTypeEsc = [System.Web.HttpUtility]::HtmlEncode($item.ConfigType)
                
                $dupAttr = if ($item.IsDuplicate) { '1' } else { '0' }
                
                $dupBadge = if ($item.IsDuplicate) {
                    "<span class='cmp-badge badge-diff'>Duplicate</span>"
                } else {
                    "<span class='cmp-badge badge-match'>Unique</span>"
                }
                
                "<tr data-dup='$dupAttr' data-configtype='$configTypeEsc'><td data-colkey='PolicyName'>$policyEsc</td><td data-colkey='PropertyPath'>$propertyEsc</td><td data-colkey='PropertyType'>$typeEsc</td><td data-colkey='ConfiguredValue'>$valueEsc</td><td data-colkey='DuplicateStatus'>$dupBadge</td><td data-colkey='ConfigType'>$configTypeEsc</td></tr>"
            }
            
            # Icon (optional)
            $iconBase64 = ''
            $headerLogoBase64 = ''
            $headerLogoMime = 'image/png'
            $iconPathIco = Join-Path -Path (Get-Location) -ChildPath 'Intune-toolkit.ico'
            if (Test-Path $iconPathIco) { $bytesIco = [System.IO.File]::ReadAllBytes($iconPathIco); $iconBase64 = [Convert]::ToBase64String($bytesIco) }
            $logoPathPng = Join-Path -Path (Get-Location) -ChildPath 'Intune-toolkit.png'
            if (Test-Path $logoPathPng) { $logoBytes = [System.IO.File]::ReadAllBytes($logoPathPng); $headerLogoBase64 = [Convert]::ToBase64String($logoBytes) } elseif ($iconBase64) { $headerLogoBase64 = $iconBase64; $headerLogoMime='image/x-icon' }
            $iconImg = if ($headerLogoBase64) { "<img src='data:$headerLogoMime;base64,$headerLogoBase64' class='header-logo' alt='Intune Toolkit Logo'>" } else { '' }

            $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            $tenant = try { (Invoke-MgGraphRequest -Uri 'https://graph.microsoft.com/v1.0/organization' -Method GET).value[0].displayName } catch { 'Unknown Tenant' }

            $htmlContent = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='utf-8'/>
<title>Device Configuration Report</title>
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
thead th{position:relative;}
.col-resizer{position:absolute;top:0;right:0;width:6px;cursor:col-resize;user-select:none;height:100%;}
html.resizing, html.resizing * {cursor:col-resize !important;}
table#configTable { table-layout:auto; }
#configTable th,#configTable td{word-break:break-word;vertical-align:top;}
.offcanvas-filters{width:320px;}
.filter-active-indicator{width:10px;height:10px;border-radius:50%;background:#198754;display:inline-block;margin-left:6px;box-shadow:0 0 0 3px rgba(25,135,84,.25);}
.scroll-top-btn{position:fixed;bottom:24px;right:24px;display:none;z-index:999;box-shadow:0 3px 10px rgba(0,0,0,.25);}
.advanced-filter-toggle{cursor:pointer;}
.advanced-filter-toggle:hover{background:#f8f9fa;}
</style>
</head>
<body>
<div class='container-fluid'>
    <div class='header-bar mb-4 d-flex flex-wrap justify-content-between align-items-center gap-4'>
    <div class='d-flex align-items-center gap-3'>$iconImg<div><h1 class='h4 mb-1'>Device Configuration Report</h1><div class='small opacity-75'>Tenant: $tenant | Generated: $generated</div><div class='small opacity-75'>Policies: $totalPolicies</div></div></div>
    <div class='search-box'><input id='blSearch' class='form-control form-control-sm' placeholder='Search report...'></div>
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
                    <div class='h6 mb-0'>Config Type <span id='activeFilterDot' style='display:none;' class='filter-active-indicator'></span></div>
                    <div class='small text-muted mt-1'>Click to refine</div>
                </div>
            </div>
        </div>
    </div>
    <div class='offcanvas offcanvas-end offcanvas-filters' tabindex='-1' id='offcanvasFilters' aria-labelledby='offcanvasFiltersLabel'>
        <div class='offcanvas-header'>
            <h5 class='offcanvas-title' id='offcanvasFiltersLabel'>Filter & Refine</h5>
            <button type='button' class='btn-close text-reset' data-bs-dismiss='offcanvas' aria-label='Close'></button>
        </div>
        <div class='offcanvas-body d-flex flex-column'>
            <div class='mb-3'>
                <h6 class='text-muted text-uppercase small mb-2'>Column Visibility</h6>
                <div id='columnVisibilityContainer' class='d-flex flex-wrap gap-2 mb-3'></div>
                <h6 class='text-muted text-uppercase small mb-2 mt-2'>Configuration Type</h6>
                <div class='overflow-auto border rounded p-2' style='max-height:200px' id='configTypeContainer'>$configTypeFilterOptions</div>
                <div class='mt-2 d-flex gap-2 flex-wrap'>
                    <button class='btn btn-sm btn-primary' type='button' onclick='applyConfigTypeFilters()'>Apply</button>
                    <button class='btn btn-sm btn-outline-secondary' type='button' onclick='clearConfigTypeFilters()'>Clear</button>
                    <button class='btn btn-sm btn-outline-primary' type='button' onclick='selectAllConfigTypeFilters()'>Select All</button>
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
            <h2 class='h5 text-primary mb-3'>Device Configuration Settings</h2>
            <div class='table-responsive'>
                <table id='configTable' class='table table-sm table-hover align-middle'>
                    <thead class='sticky-top'><tr>
                        <th data-colkey='PolicyName'>Policy Name</th>
                        <th data-colkey='PropertyPath'>Property Path</th>
                        <th data-colkey='PropertyType'>Type</th>
                        <th data-colkey='ConfiguredValue'>Configured Value</th>
                        <th data-colkey='DuplicateStatus'>Duplicates</th>
                        <th data-colkey='ConfigType'>Config Type</th>
                    </tr></thead>
                    <tbody>
$($rowsHtml -join "`n")
                    </tbody>
                </table>
            </div>
        </div>
    </div>
    <div class='text-center small text-muted mt-4 mb-3'>Generated by Intune Toolkit • Device Configuration Report</div>
</div>
<button id='scrollTopBtn' class='scroll-top-btn btn btn-primary btn-sm'>Top</button>
<script>
function makeColsResizable(tableId){ const table=document.getElementById(tableId); if(!table) return; const ths=[...table.querySelectorAll('thead th')]; ths.forEach((th,idx)=>{ if(th.querySelector('.col-resizer')) return; th.style.position='relative'; const grip=document.createElement('span'); grip.className='col-resizer'; grip.title='Drag to resize'; th.appendChild(grip); let startX,startWidth; grip.addEventListener('mousedown',e=>{ startX=e.pageX; startWidth=th.offsetWidth; document.documentElement.classList.add('resizing'); function onMove(ev){ let w=startWidth+(ev.pageX-startX); if(w<60) w=60; th.style.width=w+'px'; table.querySelectorAll('tbody tr').forEach(r=>{ if(r.children[idx]) r.children[idx].style.width=w+'px'; }); } function onUp(){ document.removeEventListener('mousemove',onMove); document.removeEventListener('mouseup',onUp); document.documentElement.classList.remove('resizing'); } document.addEventListener('mousemove',onMove); document.addEventListener('mouseup',onUp); e.preventDefault(); e.stopPropagation(); }); }); }
function handleScrollTopBtn(){ const btn=document.getElementById('scrollTopBtn'); if(!btn) return; btn.style.display= window.scrollY>300 ? 'block':'none'; } window.addEventListener('scroll',handleScrollTopBtn);
let currentSelectedConfigTypes=[];
function applyConfigTypeFilters(){ const cbs=document.querySelectorAll('.configtype-filter-cb'); currentSelectedConfigTypes=[...cbs].filter(cb=>cb.checked).map(cb=>cb.value.toLowerCase()); filterByConfigType(); const dot=document.getElementById('activeFilterDot'); if(dot){ dot.style.display=currentSelectedConfigTypes.length<cbs.length?'inline-block':'none'; } }
function filterByConfigType(){ const rows=document.querySelectorAll('#configTable tbody tr'); rows.forEach(r=>{ if(currentSelectedConfigTypes.length===0){ r.dataset.configfiltered='0'; } else { const type=(r.getAttribute('data-configtype')||'').toLowerCase(); r.dataset.configfiltered= currentSelectedConfigTypes.includes(type)?'0':'1'; } }); applyCombinedVisibility(); }
function clearConfigTypeFilters(){ document.querySelectorAll('.configtype-filter-cb').forEach(cb=> cb.checked=false); currentSelectedConfigTypes=[]; filterByConfigType(); }
function selectAllConfigTypeFilters(){ document.querySelectorAll('.configtype-filter-cb').forEach(cb=> cb.checked=true); }
function filterConfigTbl(){
    const searchEl = document.getElementById('blSearch');
    const q = (searchEl ? searchEl.value : '').toLowerCase();
    document.querySelectorAll('#configTable tbody tr').forEach(r=>{
        const match=[...r.children].some(td=> td.textContent.toLowerCase().includes(q));
        r.dataset.searchHidden = match ? '0' : '1';
    });
    applyCombinedVisibility();
}
function applyCombinedVisibility(){
    const dupMode=(document.querySelector('[data-dup-filter].active')||{getAttribute:()=> 'all'}).getAttribute('data-dup-filter');
    const rows=document.querySelectorAll('#configTable tbody tr');
    rows.forEach(r=>{
        let hide = (r.dataset.searchHidden==='1' || r.dataset.configfiltered==='1');
        if(!hide){
            const dup = r.getAttribute('data-dup')==='1';
            if(dupMode==='dup' && !dup) hide=true;
            if(dupMode==='unique' && dup) hide=true;
        }
        r.style.display = hide ? 'none' : '';
    });
    updateSummaryStats();
}
function updateSummaryStats(){ const rows=[...document.querySelectorAll('#configTable tbody tr')]; const visible=rows.filter(r=> r.style.display!=='none'); const totalVisible=visible.length; const dup=visible.filter(r=> r.getAttribute('data-dup')==='1').length; const uniq=totalVisible-dup; const pct=(n)=> totalVisible? ((n/totalVisible)*100).toFixed(1).replace(/\.0$/,''):'0'; function setTxt(id,v){ const el=document.getElementById(id); if(el) el.textContent=v; } setTxt('totalSettingsCount', totalVisible); setTxt('duplicatesCount', dup); setTxt('uniqueCount', uniq); setTxt('duplicatesPct', pct(dup)); setTxt('uniquePct', pct(uniq)); }
document.addEventListener('input', e=>{ if(e.target && e.target.id==='blSearch'){ filterConfigTbl(); } });
document.addEventListener('change', e=>{
    if(e.target && e.target.classList.contains('configtype-filter-cb')){ applyConfigTypeFilters(); }
});
document.addEventListener('DOMContentLoaded',()=>{ makeColsResizable('configTable'); handleScrollTopBtn(); const t=document.getElementById('scrollTopBtn'); if(t){ t.addEventListener('click',()=>window.scrollTo({top:0,behavior:'smooth'})); }
    const colContainer=document.getElementById('columnVisibilityContainer'); if(colContainer){ const headers=document.querySelectorAll('#configTable thead th[data-colkey]'); headers.forEach(h=>{ const key=h.getAttribute('data-colkey'); const label=h.textContent.trim(); const id='colvis_'+key; const div=document.createElement('div'); div.className='form-check form-check-sm me-2'; div.innerHTML='<input class="form-check-input col-vis-cb" type="checkbox" id="'+id+'" data-colkey="'+key+'" checked><label class="form-check-label small" for="'+id+'">'+label+'</label>'; colContainer.appendChild(div); }); colContainer.addEventListener('change', e=>{ const cb=e.target.closest('.col-vis-cb'); if(!cb) return; const key=cb.getAttribute('data-colkey'); document.querySelectorAll('#configTable [data-colkey="'+key+'"]').forEach(cell=>{ cell.style.display = cb.checked? '' : 'none'; }); }); }
    document.querySelectorAll('[data-dup-filter]').forEach(btn=>{ btn.addEventListener('click',()=>{ document.querySelectorAll('[data-dup-filter]').forEach(b=>b.classList.remove('active')); btn.classList.add('active'); applyCombinedVisibility(); }); });
    document.querySelectorAll('#configTable tbody tr').forEach(r=>{ r.dataset.searchHidden='0'; r.dataset.configfiltered='0'; });
    filterConfigTbl();
    updateSummaryStats();
});
</script>
<script src='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js'></script>
</body>
</html>
"@
            
            $saveFileDialog = New-Object Microsoft.Win32.SaveFileDialog
            $saveFileDialog.Filter = "HTML files (*.html)|*.html"
            $saveFileDialog.FileName = "$baseName.html"
            if ($saveFileDialog.ShowDialog()) {
                Set-Content -Path $saveFileDialog.FileName -Value $htmlContent -Encoding UTF8
                Write-IntuneToolkitLog "HTML report saved: $($saveFileDialog.FileName)" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"
                [System.Windows.MessageBox]::Show("HTML report saved to:`n$($saveFileDialog.FileName)`n`nOpening in browser...", "Success")
                Start-Process $saveFileDialog.FileName
            }
        }

    } catch {
        Write-IntuneToolkitLog "Error in DeviceConfigReportButton: $($_.Exception.Message)" -component "DeviceConfigReport-Button" -file "DeviceConfigurationReportButton.ps1"
        [System.Windows.MessageBox]::Show("An error occurred: $($_.Exception.Message)", "Error")
    }
})
