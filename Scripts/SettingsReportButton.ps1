<#
.SYNOPSIS
Exports a settings-only report for selected Intune configuration policies with debug logging.
.DESCRIPTION
When the Settings Report button is clicked, this handler:
  - Validates policy selection
  - Deduplicates selected policies by ID
  - Retrieves raw settings for each unique policy
  - Flattens settings via existing Flatten-PolicySettings function
  - Outputs debug logs capturing flattened entries
  - Builds a Markdown or CSV report listing each setting’s friendly name, description, configured value, and the policy it belongs to
#>
$SettingsReportButton.Add_Click({
    try {
        Write-IntuneToolkitLog "SettingsReportButton clicked" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"

        # Validate UI selection
        if (-not $PolicyDataGrid.SelectedItems -or $PolicyDataGrid.SelectedItems.Count -eq 0) {
            Write-IntuneToolkitLog "No policies selected." -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
            [System.Windows.MessageBox]::Show("Select one or more configuration policies.", "Information")
            return
        }

        # Deduplicate selected policies by ID
        $uniquePolicies = $PolicyDataGrid.SelectedItems |
            Group-Object -Property { if ($_.PSObject.Properties['PolicyId']) { $_.PolicyId } else { $_.id } } |
            ForEach-Object { $_.Group[0] }
        Write-IntuneToolkitLog "Unique policies count: $($uniquePolicies.Count)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"

        # Fetch & merge raw settings
        $mergedSettings = @()
        foreach ($policy in $uniquePolicies) {
            $policyId   = if ($policy.PSObject.Properties['PolicyId']) { $policy.PolicyId } else { $policy.id }
            Write-IntuneToolkitLog "Fetching details for policy: $($policyId)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
            $url = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policyId)?`$expand=settings"
            try {
                $detail = Invoke-MgGraphRequest -Uri $url -Method GET
            } catch {
                Write-IntuneToolkitLog "Error fetching policy $($policyId): $($_.Exception.Message)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
                continue
            }
            if ($detail.settings) {
                $settingsArray = if ($detail.settings -is [System.Array]) { $detail.settings } else { @($detail.settings) }
                Write-IntuneToolkitLog "Policy '$($detail.name)' returned $($settingsArray.Count) settings" -component "SettingsReport-Debug" -file "SettingsReportHandler.ps1"
                foreach ($s in $settingsArray) {
                    if (-not ($s.settingDefinitionId -or ($s.settingInstance -and $s.settingInstance.settingDefinitionId))) {
                        Write-IntuneToolkitLog "Skipping entry without DefinitionId" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
                        continue
                    }
                    $mergedSettings += [PSCustomObject]@{
                        PolicyName = $detail.name
                        Setting    = $s
                    }
                }
            } else {
                Write-IntuneToolkitLog "Policy $($detail.name) has no settings to merge." -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
            }
        }
        Write-IntuneToolkitLog "Total merged settings: $($mergedSettings.Count)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"

        if ($mergedSettings.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No configurable settings found.", "Information")
            return
        }

        # Flatten settings
        $flattened = Flatten-PolicySettings -MergedPolicy $mergedSettings
        Write-IntuneToolkitLog "Flattened entries count: $($flattened.Count)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"

        # Ensure catalog
        $catalogPath = ".\SupportFiles\SettingsCatalog.json"
        if (-not (Test-Path $catalogPath)) {
            Write-IntuneToolkitLog "Missing catalog at $($catalogPath)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
            [System.Windows.MessageBox]::Show("Settings catalog not found.", "Error")
            return
        }
        $catalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json
        $CatalogDictionary = Build-CatalogDictionary -Catalog $catalog

        # Group by setting ID to combine duplicates
        $grouped = $flattened | Group-Object -Property PolicySettingId

        # Prepare report items (include Platform, Keywords/Tags, Duplicate indicator)
        $reportItems = @()
        foreach ($group in $grouped) {
            $id           = $group.Name
            if (-not $id) { continue }
            $policiesList = ($group.Group | ForEach-Object { $_.PolicyName }) -join "; "
            $catalogEntry = Find-CatalogEntry -CatalogDictionary $CatalogDictionary -Key $id
            $dispName     = ((Get-SettingDisplayValue -settingValueId $id -CatalogDictionary $CatalogDictionary) | Where-Object { $_ })
            if (-not $dispName) { $dispName = $id }
            $desc         = Get-SettingDescription -settingId $id -CatalogDictionary $CatalogDictionary
            $uniqueVals   = ($group.Group | ForEach-Object { $_.ActualValue }) | Select-Object -Unique
            $dispVals     = foreach ($val in $uniqueVals) {
                if ($val) { (Get-SettingDisplayValue -settingValueId $val -CatalogDictionary $CatalogDictionary) || $val }
            }
            $valueDisplay = ($dispVals -join "; ").Trim()
            # Aggregate platform (prefer setting catalog entry, fallback to value entries)
            $platformNorm = $null
            if ($catalogEntry -and $catalogEntry.Platform) { $platformNorm = ($catalogEntry.Platform -replace '\s+','') }
            if (-not $platformNorm) {
                foreach($val in $uniqueVals){
                    $valEntry = Find-CatalogEntry -CatalogDictionary $CatalogDictionary -Key $val
                    if ($valEntry -and $valEntry.Platform) { $platformNorm = ($valEntry.Platform -replace '\s+',''); break }
                }
            }
            if ($platformNorm -match '^(?i)windows10$'){ $platformNorm='Windows' }
            # Aggregate keywords from the setting id plus any value entries
            $kwSet = [System.Collections.Generic.HashSet[string]]::new()
            if ($catalogEntry -and $catalogEntry.Keywords) { ($catalogEntry.Keywords -split '\s*,\s*' | Where-Object { $_ }) | ForEach-Object { [void]$kwSet.Add($_) } }
            foreach($val in $uniqueVals){
                $valEntry = Find-CatalogEntry -CatalogDictionary $CatalogDictionary -Key $val
                if ($valEntry -and $valEntry.Keywords) { ($valEntry.Keywords -split '\s*,\s*' | Where-Object { $_ }) | ForEach-Object { [void]$kwSet.Add($_) } }
            }
            $keywords = if ($kwSet.Count -gt 0) { (@($kwSet) | Sort-Object -Unique) -join ', ' } else { $null }
            $reportItems += [PSCustomObject]@{
                PolicyName       = $policiesList
                Setting          = $dispName
                Description      = $desc
                ConfiguredValue  = $valueDisplay
                Duplicates       = [bool]($group.Count -gt 1)
                Platform         = $platformNorm
                KeywordsRaw      = $keywords
                PolicySettingId  = $id
            }
        }
        Write-IntuneToolkitLog "Report items prepared: $($reportItems.Count)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"

        # Show export options
        $formats  = Show-ExportOptionsDialog
        if (-not $formats -or $formats.Count -eq 0) { return }
        Add-Type -AssemblyName System.Windows.Forms
        $baseName = "SettingsReport_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"

        foreach ($fmt in $formats) {
            switch ($fmt) {
                'Markdown' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter   = 'Markdown (*.md)|*.md|All (*.*)|*.*'
                    $dlg.Title    = 'Save Settings Report'
                    $dlg.FileName = "$baseName.md"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        # Overview of shared settings
                        $overview = foreach ($g in $grouped | Where-Object { $_.Count -gt 1 }) {
                            $name = (Get-SettingDisplayValue -settingValueId $g.Name -CatalogDictionary $CatalogDictionary) || $g.Name
                            $pols = ($g.Group | ForEach-Object { $_.PolicyName }) -join "; "
                            "- **$name** configured in policies: $pols"
                        }
                        $md = @('# Settings Report', '', '## Overview: Shared Settings', '')
                        if ($overview) { $md += $overview } else { $md += '- No settings shared across multiple policies.' }
                        $md += @('', '| Policy Name | Setting | Description | Value |', '|-------------|---------|-------------|-------|')
                        foreach ($r in $reportItems) {
                            $md += "| $($r.PolicyName) | $($r.Setting) | $($r.Description) | $($r.ConfiguredValue) |"
                        }
                        $md -join "`r`n" | Out-File -FilePath $dlg.FileName -Encoding UTF8
                    }
                }
                                'CSV' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter   = 'CSV (*.csv)|*.csv|All (*.*)|*.*'
                    $dlg.Title    = 'Save Settings Report CSV'
                    $dlg.FileName = "$baseName.csv"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        $reportItems | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8 -Delimiter ';'
                    }
                }
                                                                'HTML' {
                                        $dlg = New-Object System.Windows.Forms.SaveFileDialog
                                        $dlg.Filter   = 'HTML (*.html)|*.html|All (*.*)|*.*'
                                        $dlg.Title    = 'Save Settings Report HTML'
                                        $dlg.FileName = "$baseName.html"
                                        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                                                try {
                                                        Add-Type -AssemblyName System.Web
                                                } catch {}
                                                                                                # Build tag & platform metadata
                                                                                                $allTags = @()
                                                                                                $platformCounts = @{}
                                                                                                foreach($ri in $reportItems){
                                                                                                        if($ri.KeywordsRaw){ $allTags += ($ri.KeywordsRaw -split '\s*,\s*') }
                                                                                                        if($ri.Platform){ $p = $ri.Platform; if(-not $platformCounts.ContainsKey($p)){ $platformCounts[$p]=0 }; $platformCounts[$p]++ }
                                                                                                }
                                                                                                $allTags = $allTags | Where-Object { $_ -and $_.Trim() -ne '' } | Sort-Object -Unique
                                                                                                $tagOptionsHtml = ($allTags | ForEach-Object { $tEsc=[System.Web.HttpUtility]::HtmlEncode($_); $idSafe=($tEsc -replace "[^a-zA-Z0-9_-]","_"); "<div class='form-check form-check-sm'><input class='form-check-input tag-filter-cb' type='checkbox' value='$tEsc' id='tag_$idSafe'><label class='form-check-label small' for='tag_$idSafe'>$tEsc</label></div>" }) -join "`n"
                                                                                                $platformFilterOptions = ($platformCounts.Keys | Sort-Object | ForEach-Object { $p=$_; $count=$platformCounts[$_]; $pEsc=[System.Web.HttpUtility]::HtmlEncode($p); $idSafe=($pEsc -replace "[^a-zA-Z0-9_-]","_"); "<div class='form-check form-check-sm'><input class='form-check-input platform-filter-cb' type='checkbox' value='$pEsc' id='plat_$idSafe'><label class='form-check-label small' for='plat_$idSafe'>$pEsc <span class='text-muted'>($count)</span></label></div>" }) -join "`n"

                                                                                                $totalPolicies   = $uniquePolicies.Count
                                                                                                $totalSettings   = $reportItems.Count
                                                                                                $duplicateCount  = ($reportItems | Where-Object { $_.Duplicates }).Count
                                                                                                $uniqueCount     = $totalSettings - $duplicateCount
                                                                                                function _pct($n,$d){ if($d){ [math]::Round(($n/$d)*100,1) } else { 0 } }
                                                                                                $dupPct = _pct $duplicateCount $totalSettings
                                                                                                $uniqPct = _pct $uniqueCount $totalSettings

                                                                                                $rowsHtml = foreach($r in $reportItems){
                                                                                                        $policyEsc  = [System.Web.HttpUtility]::HtmlEncode($r.PolicyName)
                                                                                                        $settingEsc = [System.Web.HttpUtility]::HtmlEncode($r.Setting)
                                                                                                        $descRaw    = if($r.Description){ $r.Description } else { '' }
                                                                                                        $descEsc    = [System.Web.HttpUtility]::HtmlEncode(($descRaw -replace "`r?`n"," "))
                                                                                                        $valEsc     = [System.Web.HttpUtility]::HtmlEncode($r.ConfiguredValue)
                                                                                                        $platEsc    = [System.Web.HttpUtility]::HtmlEncode($r.Platform)
                                                                                                        $tagsHtml   = ''
                                                                                                        $dataTags   = ''
                                                                                                        if($r.KeywordsRaw){
                                                                                                                $tags = $r.KeywordsRaw -split '\s*,\s*' | Where-Object { $_ -and $_.Trim() -ne '' } | Sort-Object -Unique
                                                                                                                $dataTags = ($tags | ForEach-Object { $_.ToLower() }) -join ','
                                                                                                                $tagsHtml = ($tags | ForEach-Object { $t=[System.Web.HttpUtility]::HtmlEncode($_); "<span class='badge me-1 tag-badge' data-tag='$t'>$t</span>" }) -join ''
                                                                                                        }
                                                                                                        $dupAttr = if($r.Duplicates){ '1' } else { '0' }
                                                                                                        # Duplicate badge yellow (warning) consistent with summary badge
                                                                                                        $dupBadge = if($r.Duplicates){ "<span class='cmp-badge badge-diff'>Duplicate</span>" } else { "<span class='cmp-badge badge-match'>Unique</span>" }
                                                                                                        "<tr data-dup='$dupAttr' data-tags='$dataTags' data-platform='$platEsc'><td data-colkey='PolicyName'>$policyEsc</td><td data-colkey='Setting'>$settingEsc</td><td data-colkey='Platform'>$platEsc</td><td data-colkey='Description' class='text-muted small desc-cell'><div class='desc-text clamp'>$descEsc</div><button type='button' class='btn btn-link p-0 small more-btn' onclick='toggleDesc(this)'>More</button></td><td data-colkey='ConfiguredValue'>$valEsc</td><td data-colkey='DuplicateStatus'>$dupBadge</td><td data-colkey='Tags' class='tags-col'>$tagsHtml</td></tr>"
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

                                                                                                $html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='utf-8'/>
<title>Settings Report</title>
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
.tags-col{min-width:200px;max-width:380px;white-space:normal !important;display:flex;flex-wrap:wrap;}
.tag-badge{font-size:.65rem;background:var(--primary)!important;color:#fff!important;padding:.35em .55em;border-radius:10px;margin:0 4px 4px 0;line-height:1.2;}
.tag-badge:hover{background:var(--primary-dark);color:#fff;}
.offcanvas-tags{width:320px;}
.filter-active-indicator{width:10px;height:10px;border-radius:50%;background:#198754;display:inline-block;margin-left:6px;box-shadow:0 0 0 3px rgba(25,135,84,.25);}
.scroll-top-btn{position:fixed;bottom:24px;right:24px;display:none;z-index:999;box-shadow:0 3px 10px rgba(0,0,0,.25);} 
</style>
</head>
<body>
<div class='container-fluid'>
    <div class='header-bar mb-4 d-flex flex-wrap justify-content-between align-items-center gap-4'>
    <div class='d-flex align-items-center gap-3'>$iconImg<div><h1 class='h4 mb-1'>Settings Report</h1><div class='small opacity-75'>Tenant: $tenant | Generated: $generated</div><div class='small opacity-75'>Policies: $totalPolicies</div></div></div>
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
                    <div class='h6 mb-0'>Tags & Platform <span id='activeFilterDot' style='display:none;' class='filter-active-indicator'></span></div>
                    <div class='small text-muted mt-1'>Click to refine</div>
                </div>
            </div>
        </div>
    </div>
    <div class='offcanvas offcanvas-end offcanvas-tags' tabindex='-1' id='offcanvasFilters' aria-labelledby='offcanvasFiltersLabel'>
        <div class='offcanvas-header'>
            <h5 class='offcanvas-title' id='offcanvasFiltersLabel'>Filter & Refine</h5>
            <button type='button' class='btn-close text-reset' data-bs-dismiss='offcanvas' aria-label='Close'></button>
        </div>
        <div class='offcanvas-body d-flex flex-column'>
            <div class='mb-3'>
                <h6 class='text-muted text-uppercase small mb-2'>Column Visibility</h6>
                <div id='columnVisibilityContainer' class='d-flex flex-wrap gap-2 mb-3'></div>
                <h6 class='text-muted text-uppercase small mb-2 mt-2'>Tags</h6>
                <input type='text' id='tagSearchInput' class='form-control form-control-sm mb-2' placeholder='Search tags...'>
                <div class='overflow-auto border rounded p-2' style='max-height:180px' id='tagCheckboxContainer'>$tagOptionsHtml</div>
                <div class='mt-2 d-flex gap-2 flex-wrap'>
                    <button class='btn btn-sm btn-primary' type='button' onclick='applyTagFilters()'>Apply</button>
                    <button class='btn btn-sm btn-outline-secondary' type='button' onclick='clearTagFilters()'>Clear</button>
                    <button class='btn btn-sm btn-outline-primary' type='button' onclick='selectAllTagFilters()'>Select All</button>
                </div>
            </div>
            <hr/>
            <div class='mb-2'>
                <h6 class='text-muted text-uppercase small mb-2'>Platforms</h6>
                <div class='overflow-auto border rounded p-2' style='max-height:160px' id='platformCheckboxContainer'>$platformFilterOptions</div>
                <div class='mt-2 d-flex gap-2 flex-wrap'>
                    <button class='btn btn-sm btn-primary' type='button' onclick='applyPlatformFilters()'>Apply</button>
                    <button class='btn btn-sm btn-outline-secondary' type='button' onclick='clearPlatformFilters()'>Clear</button>
                    <button class='btn btn-sm btn-outline-primary' type='button' onclick='selectAllPlatformFilters()'>Select All</button>
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
                        <th data-colkey='Platform'>Platform</th>
                        <th data-colkey='Description'>Description</th>
                        <th data-colkey='ConfiguredValue'>Configured Value</th>
                        <th data-colkey='DuplicateStatus'>Duplicates</th>
                        <th data-colkey='Tags'>Tags</th>
                    </tr></thead>
                    <tbody>
$($rowsHtml -join "`n")
                    </tbody>
                </table>
            </div>
        </div>
    </div>
    <div class='text-center small text-muted mt-4 mb-3'>Generated by Intune Toolkit • Settings Report</div>
</div>
<button id='scrollTopBtn' class='scroll-top-btn btn btn-primary btn-sm'>Top</button>
<script>
function toggleDesc(btn){ const wrapper=btn.previousElementSibling; if(wrapper.classList.contains('expanded')){ wrapper.classList.remove('expanded'); wrapper.classList.add('clamp'); btn.textContent='More'; } else { wrapper.classList.remove('clamp'); wrapper.classList.add('expanded'); btn.textContent='Less'; } }
function makeColsResizable(tableId){ const table=document.getElementById(tableId); if(!table) return; const ths=[...table.querySelectorAll('thead th')]; ths.forEach((th,idx)=>{ if(th.querySelector('.col-resizer')) return; th.style.position='relative'; const grip=document.createElement('span'); grip.className='col-resizer'; grip.title='Drag to resize'; th.appendChild(grip); let startX,startWidth; grip.addEventListener('mousedown',e=>{ startX=e.pageX; startWidth=th.offsetWidth; document.documentElement.classList.add('resizing'); function onMove(ev){ let w=startWidth+(ev.pageX-startX); if(w<60) w=60; th.style.width=w+'px'; table.querySelectorAll('tbody tr').forEach(r=>{ if(r.children[idx]) r.children[idx].style.width=w+'px'; }); } function onUp(){ document.removeEventListener('mousemove',onMove); document.removeEventListener('mouseup',onUp); document.documentElement.classList.remove('resizing'); } document.addEventListener('mousemove',onMove); document.addEventListener('mouseup',onUp); e.preventDefault(); e.stopPropagation(); }); }); }
function handleScrollTopBtn(){ const btn=document.getElementById('scrollTopBtn'); if(!btn) return; btn.style.display= window.scrollY>300 ? 'block':'none'; } window.addEventListener('scroll',handleScrollTopBtn);
let currentSelectedTags=[]; let currentSelectedPlatforms=[];
function applyTagFilters(){ const cbs=document.querySelectorAll('.tag-filter-cb'); currentSelectedTags=[...cbs].filter(cb=>cb.checked).map(cb=>cb.value.toLowerCase()); filterByTags(); const dot=document.getElementById('activeFilterDot'); if(dot){ dot.style.display=currentSelectedTags.length>0?'inline-block':'none'; } }
function filterByTags(){ const rows=document.querySelectorAll('#settingsTable tbody tr'); rows.forEach(r=>{ if(currentSelectedTags.length===0){ r.dataset.tagfiltered='0'; } else { const tags=(r.getAttribute('data-tags')||'').split(',').filter(x=>x); const hasAll=currentSelectedTags.every(t=> tags.includes(t)); r.dataset.tagfiltered= hasAll?'0':'1'; } }); applyCombinedVisibility(); }
function applyPlatformFilters(){ const cbs=document.querySelectorAll('.platform-filter-cb'); currentSelectedPlatforms=[...cbs].filter(cb=>cb.checked).map(cb=>cb.value.toLowerCase()); filterByPlatform(); }
function filterByPlatform(){ const rows=document.querySelectorAll('#settingsTable tbody tr'); rows.forEach(r=>{ if(currentSelectedPlatforms.length===0){ r.dataset.platformfiltered='0'; } else { const plat=(r.getAttribute('data-platform')||'').toLowerCase(); r.dataset.platformfiltered= currentSelectedPlatforms.includes(plat)?'0':'1'; } }); applyCombinedVisibility(); }
function clearPlatformFilters(){ document.querySelectorAll('.platform-filter-cb').forEach(cb=> cb.checked=false); currentSelectedPlatforms=[]; filterByPlatform(); }
function selectAllPlatformFilters(){ document.querySelectorAll('.platform-filter-cb').forEach(cb=> cb.checked=true); }
function clearTagFilters(){ document.querySelectorAll('.tag-filter-cb').forEach(cb=> cb.checked=false); currentSelectedTags=[]; filterByTags(); const dot=document.getElementById('activeFilterDot'); if(dot){ dot.style.display='none'; } }
function selectAllTagFilters(){ document.querySelectorAll('.tag-filter-cb').forEach(cb=> cb.checked=true); }
// --- Begin Baseline-equivalent filtering logic (override pattern) ---
const originalFilterBaselineTbl = window.filterBaselineTbl || function(){};
function filterBaselineTbl(){
    const searchEl = document.getElementById('blSearch');
    const q = (searchEl ? searchEl.value : '').toLowerCase();
    document.querySelectorAll('#settingsTable tbody tr').forEach(r=>{
        const match=[...r.children].some(td=> td.textContent.toLowerCase().includes(q));
        r.dataset.searchHidden = match ? '0' : '1';
    });
    applyCombinedVisibility();
}
function applyCombinedVisibility(){
    const dupMode=(document.querySelector('[data-dup-filter].active')||{getAttribute:()=> 'all'}).getAttribute('data-dup-filter');
    const rows=document.querySelectorAll('#settingsTable tbody tr');
    rows.forEach(r=>{
        let hide = (r.dataset.searchHidden==='1' || r.dataset.tagfiltered==='1' || r.dataset.platformfiltered==='1');
        if(!hide){
            const dup = r.getAttribute('data-dup')==='1';
            if(dupMode==='dup' && !dup) hide=true;
            if(dupMode==='unique' && dup) hide=true;
        }
        r.style.display = hide ? 'none' : '';
    });
    updateSummaryStats();
}
// --- End Baseline-equivalent filtering logic ---
// Provide backward-compatible alias (if older HTML calls filterSettingsTbl)
function filterSettingsTbl(){ filterBaselineTbl(); }
function updateSummaryStats(){ const rows=[...document.querySelectorAll('#settingsTable tbody tr')]; const visible=rows.filter(r=> r.style.display!=='none'); const totalVisible=visible.length; const dup=visible.filter(r=> r.getAttribute('data-dup')==='1').length; const uniq=totalVisible-dup; const pct=(n)=> totalVisible? ((n/totalVisible)*100).toFixed(1).replace(/\.0$/,''):'0'; function setTxt(id,v){ const el=document.getElementById(id); if(el) el.textContent=v; } setTxt('totalSettingsCount', totalVisible); setTxt('duplicatesCount', dup); setTxt('uniqueCount', uniq); setTxt('duplicatesPct', pct(dup)); setTxt('uniquePct', pct(uniq)); }
// Tag search filter
document.addEventListener('input',function(e){ if(e.target && e.target.id==='tagSearchInput'){ const q=e.target.value.toLowerCase(); document.querySelectorAll('#tagCheckboxContainer .form-check').forEach(div=>{ const txt=div.textContent.toLowerCase(); div.style.display = txt.includes(q)?'':'none'; }); } });
// Live search listener (in addition to inline onkeyup for robustness)
document.addEventListener('input', e=>{ if(e.target && e.target.id==='blSearch'){ filterBaselineTbl(); } });
// Auto-apply tag/platform filters on checkbox change for immediate feedback
document.addEventListener('change', e=>{
    if(e.target && e.target.classList.contains('tag-filter-cb')){ applyTagFilters(); }
    if(e.target && e.target.classList.contains('platform-filter-cb')){ applyPlatformFilters(); }
});
// Click tag badge quick filter
document.addEventListener('click', function(e){ const badge=e.target.closest('.tag-badge'); if(!badge) return; const tag=badge.getAttribute('data-tag'); if(!tag) return; const cb=[...document.querySelectorAll('.tag-filter-cb')].find(c=> c.value.toLowerCase()===tag.toLowerCase()); if(cb){ const selected=[...document.querySelectorAll('.tag-filter-cb')].filter(c=>c.checked).map(c=>c.value.toLowerCase()); if(selected.length===1 && selected[0]===tag.toLowerCase()){ cb.checked=false; } else { document.querySelectorAll('.tag-filter-cb').forEach(c=> c.checked=false); cb.checked=true; } } applyTagFilters(); });
document.addEventListener('DOMContentLoaded',()=>{ makeColsResizable('settingsTable'); handleScrollTopBtn(); const t=document.getElementById('scrollTopBtn'); if(t){ t.addEventListener('click',()=>window.scrollTo({top:0,behavior:'smooth'})); } // build column visibility
    const colContainer=document.getElementById('columnVisibilityContainer'); if(colContainer){ const headers=document.querySelectorAll('#settingsTable thead th[data-colkey]'); headers.forEach(h=>{ const key=h.getAttribute('data-colkey'); const label=h.textContent.trim(); const id='colvis_'+key; const div=document.createElement('div'); div.className='form-check form-check-sm me-2'; div.innerHTML='<input class="form-check-input col-vis-cb" type="checkbox" id="'+id+'" data-colkey="'+key+'" checked><label class="form-check-label small" for="'+id+'">'+label+'</label>'; colContainer.appendChild(div); }); colContainer.addEventListener('change', e=>{ const cb=e.target.closest('.col-vis-cb'); if(!cb) return; const key=cb.getAttribute('data-colkey'); document.querySelectorAll('#settingsTable [data-colkey="'+key+'"]').forEach(cell=>{ cell.style.display = cb.checked? '' : 'none'; }); }); }
    document.querySelectorAll('[data-dup-filter]').forEach(btn=>{ btn.addEventListener('click',()=>{ document.querySelectorAll('[data-dup-filter]').forEach(b=>b.classList.remove('active')); btn.classList.add('active'); applyCombinedVisibility(); }); });
    // Initialize dataset flags for baseline logic
    document.querySelectorAll('#settingsTable tbody tr').forEach(r=>{ r.dataset.searchHidden='0'; r.dataset.tagfiltered='0'; r.dataset.platformfiltered='0'; });
    // Initial pass ensures consistency with baseline behavior
    filterBaselineTbl();
    updateSummaryStats();
});
</script>
<script src='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js'></script>
</body>
</html>
"@
                                                                                                $html | Out-File -FilePath $dlg.FileName -Encoding UTF8
                                                                                                try { Start-Process -FilePath $dlg.FileName } catch {}
                                        }
                                }
            }
        }

        [System.Windows.MessageBox]::Show("Export complete.", "Success")
    } catch {
        Write-IntuneToolkitLog "Error: $($_.Exception.Message)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
        [System.Windows.MessageBox]::Show("Failed to generate settings report: $($_.Exception.Message)", "Error")
    }
})
