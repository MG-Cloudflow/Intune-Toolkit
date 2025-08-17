<#
.SYNOPSIS
Handles unified AssignmentReportButton click: choose export formats and perform CSV/Markdown exports.
.DESCRIPTION
Opens dialog to select export formats, then runs inline export logic without needing separate scripts.
#>

# Utility: get selected or all policies
function Get-PoliciesToExport {
    param(
        [PSObject]$AllPolicies,
        [System.Windows.Controls.DataGrid]$DataGrid
    )
    $selected = $DataGrid.SelectedItems
    if ($selected.Count -gt 0) {
        $ids = $selected | Select-Object -ExpandProperty PolicyId -Unique
        return $AllPolicies | Where-Object { $ids -contains $_.PolicyId }
    }
    return $AllPolicies
}

# Markdown export function with detailed formatting
function Export-ToMarkdown {
    param(
        [Parameter(Mandatory=$true)][string]$OutputPath,
        [Parameter(Mandatory=$true)][PSObject]$PolicyDataGrid,
        [Parameter(Mandatory=$true)][string]$CurrentPolicyType
    )
    try {
        # Retrieve tenant info and current date
        $tenant = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET
        $tenantInfo = "Tenant: $($tenant.value[0].displayName)"
        $dateString = Get-Date -Format "dddd, MMMM dd, yyyy HH:mm:ss"
        # Build header
        $header = "# $CurrentPolicyType`n`n$tenantInfo`n`nDocumentation Date: $dateString`n`n"
        # Table of contents
        $toc = "## Table of Contents`n`n"
        # Main content
        $content = ""
        $groups = $PolicyDataGrid | Group-Object PolicyId | Sort-Object { $_.Group[0].Platform }, { $_.Group[0].PolicyName }
        $currentPlatform = ""
        foreach ($policyGroup in $groups) {
            $first = $policyGroup.Group[0]
            if ($currentPlatform -ne $first.Platform) {
                $currentPlatform = $first.Platform
                $content += "## Platform: $currentPlatform`n`n"
                $toc += "- [$currentPlatform](#$(($currentPlatform -replace ' ','-').ToLower()))`n"
            }
            $policyName = $first.PolicyName
            $toc += "  - [$policyName](#$(($policyName -replace ' ','-').ToLower()))`n"
            $content += "### $policyName`n`n"
            $content += "#### Description`n`n$($first.PolicyDescription)`n`n"
            $content += "#### Assignments`n`n"
            # Table header
            if ($CurrentPolicyType -eq 'mobileApps') {
                $content += "| GroupDisplayname | GroupId | Platform | AssignmentType | FilterDisplayname | FilterType | InstallIntent |`n"
                $content += "| --------------- | ------- | -------- | -------------- | ----------------- | ---------- | ------------- |`n"
            } elseif ($CurrentPolicyType -in @('deviceCustomAttributeShellScripts','intents','deviceShellScripts','deviceManagementScripts')) {
                $content += "| GroupDisplayname | GroupId | Platform | AssignmentType |`n"
                $content += "| --------------- | ------- | -------- | -------------- |`n"
            } else {
                $content += "| GroupDisplayname | GroupId | Platform | AssignmentType | FilterDisplayname | FilterType |`n"
                $content += "| --------------- | ------- | -------- | -------------- | ----------------- | ---------- |`n"
            }
            foreach ($item in $policyGroup.Group) {
                if ($CurrentPolicyType -eq 'mobileApps') {
                    $content += "| $($item.GroupDisplayname) | $($item.GroupId) | $($item.Platform) | $($item.AssignmentType) | $($item.FilterDisplayname) | $($item.FilterType) | $($item.InstallIntent) |`n"
                } elseif ($CurrentPolicyType -in @('deviceCustomAttributeShellScripts','intents','deviceShellScripts','deviceManagementScripts')) {
                    $content += "| $($item.GroupDisplayname) | $($item.GroupId) | $($item.Platform) | $($item.AssignmentType) |`n"
                } else {
                    $content += "| $($item.GroupDisplayname) | $($item.GroupId) | $($item.Platform) | $($item.AssignmentType) | $($item.FilterDisplayname) | $($item.FilterType) |`n"
                }
            }
            $content += "`n"
        }
        # Combine and write
        $final = "$header`n$toc`n$content"
        $final | Out-File -FilePath $OutputPath -Encoding utf8
        Write-IntuneToolkitLog -Message "Exported policy data to Markdown file at $OutputPath" -Component "ExportToMarkdown"
        [System.Windows.MessageBox]::Show('Markdown export completed successfully.','Export Completed',[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information)
    } catch {
        Write-IntuneToolkitLog -Message "An error occurred during Markdown export: $_" -Component "ExportToMarkdown" -Severity "Error"
        [System.Windows.MessageBox]::Show("An error occurred during Markdown export: $_","Export Failed",[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error)
    }
}

# CSV export function
function Export-ToCsv {
    param(
        [string]$OutputPath,
        [PSObject]$PolicyItems
    )
    try {
        $PolicyItems | Export-Csv -Path $OutputPath -NoTypeInformation
        [System.Windows.MessageBox]::Show('CSV export succeeded','Success',[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information)
    } catch {
        [System.Windows.MessageBox]::Show("CSV export failed: $_","Error",[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error)
    }
}

function Export-ToHtml {
    param(
        [Parameter(Mandatory=$true)][string]$OutputPath,
        [Parameter(Mandatory=$true)][PSObject]$PolicyDataGrid,
        [Parameter(Mandatory=$true)][string]$CurrentPolicyType
    )
    try {
        # Tenant & branding
        $tenant    = Invoke-MgGraphRequest -Uri 'https://graph.microsoft.com/v1.0/organization' -Method GET
        $tenantName = $tenant.value[0].displayName
        $generated  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        
        # Load favicon (ICO) and header logo (PNG) separately so header can be larger
        $iconBase64 = ''
        $iconPathIco = Join-Path -Path (Get-Location) -ChildPath 'Intune-toolkit.ico'
        if (Test-Path $iconPathIco) { $bytesIco = [System.IO.File]::ReadAllBytes($iconPathIco); $iconBase64 = [Convert]::ToBase64String($bytesIco) }

        $headerLogoBase64 = ''
        $headerLogoMime = 'image/png'
        $logoPathPng = Join-Path -Path (Get-Location) -ChildPath 'Intune-toolkit.png'
        if (Test-Path $logoPathPng) {
            $logoBytes = [System.IO.File]::ReadAllBytes($logoPathPng)
            $headerLogoBase64 = [Convert]::ToBase64String($logoBytes)
        } elseif (-not $iconBase64 -and (Test-Path $iconPathIco)) {
            # Fallback: use ICO also as header image if PNG missing
            $headerLogoBase64 = $iconBase64
            $headerLogoMime = 'image/x-icon'
        }
        $iconImg = if ($headerLogoBase64) { "<img src='data:$headerLogoMime;base64,$headerLogoBase64' class='header-logo' alt='Intune Toolkit Logo'>" } else { '' }

        # Group policies
        $groups = $PolicyDataGrid | Group-Object PolicyId | Sort-Object { $_.Group[0].Platform }, { $_.Group[0].PolicyName }
        $platformSections = @()
        foreach ($policyGroup in $groups) {
            $first      = $policyGroup.Group[0]
            $policyName = $first.PolicyName
            $platform   = $first.Platform
            $descRaw    = $first.PolicyDescription
            $descHtml   = [System.Web.HttpUtility]::HtmlEncode($descRaw)
            $descPlain  = ($descHtml -replace '\s+',' ').Trim()
            $needsToggle = ($descPlain.Length -gt 220)
            $descShort = if ($needsToggle) { $descPlain.Substring(0,200) + '...' } else { $descPlain }
            $descFullAttr  = [System.Web.HttpUtility]::HtmlAttributeEncode($descPlain)
            $descShortAttr = [System.Web.HttpUtility]::HtmlAttributeEncode($descShort)

            $assignments  = $policyGroup.Group
            $isUnassigned = ($assignments.Count -eq 1 -and [string]::IsNullOrWhiteSpace($assignments[0].GroupDisplayname))
            $rows = @()
            $hasFilterForPolicy = $false
            $intentsForPolicy = @()
            if (-not $isUnassigned) {
                foreach ($item in $assignments) {
                    if (-not [string]::IsNullOrWhiteSpace($item.GroupDisplayname)) {
                        if ($item.FilterDisplayname) { $hasFilterForPolicy = $true }
                        if ($CurrentPolicyType -eq 'mobileApps' -and $item.InstallIntent -and ($intentsForPolicy -notcontains $item.InstallIntent)) { $intentsForPolicy += $item.InstallIntent }

                        # Build rows with modern styling
                        $assignmentTypeVal = [string]$item.AssignmentType
                        $assignmentTypeClass = switch -Regex ($assignmentTypeVal.ToLower()) {
                            'required'   { 'badge-required'; break }
                            'available'  { 'badge-available'; break }
                            'uninstall'  { 'badge-uninstall'; break }
                            'include'    { 'badge-include'; break }
                            'exclude'    { 'badge-exclude'; break }
                            default      { 'badge-generic' }
                        }
                        $assignmentTypeCell = "<td><span class='badge assignment-badge $assignmentTypeClass' title='Assignment Type'>$([System.Web.HttpUtility]::HtmlEncode($assignmentTypeVal))</span></td>"

                        $filterDisplay = [System.Web.HttpUtility]::HtmlEncode($item.FilterDisplayname)
                        $filterType    = [System.Web.HttpUtility]::HtmlEncode($item.FilterType)
                        $filterDisplayCell = if ($filterDisplay) { "<td><span class='badge filter-badge' title='Filter'>$filterDisplay</span></td>" } else { '<td class="text-muted small">-</td>' }
                        $filterTypeCell    = if ($filterType)    { "<td><span class='badge filtertype-badge' title='Filter Type'>$filterType</span></td>" } else { '<td class="text-muted small">-</td>' }

                        $installIntentVal = [string]$item.InstallIntent
                        $installIntentClass = switch -Regex ($installIntentVal.ToLower()) {
                            'required'  { 'intent-required'; break }
                            'available' { 'intent-available'; break }
                            'uninstall' { 'intent-uninstall'; break }
                            'not.*applicable' { 'intent-na'; break }
                            default     { 'intent-generic' }
                        }
                        $installIntentCell = "<td><span class='badge intent-badge $installIntentClass' title='Install Intent'>$([System.Web.HttpUtility]::HtmlEncode($installIntentVal))</span></td>"

                        $groupIdFull  = [System.Web.HttpUtility]::HtmlEncode([string]$item.GroupId)
                        # Show full ID (no truncation)
                        $groupIdCell  = "<td><code class='id-code' data-full='$groupIdFull' title='Click to copy ID'>$groupIdFull</code></td>"

                        $groupNameCell = "<td><span class='grp-name'>$([System.Web.HttpUtility]::HtmlEncode($item.GroupDisplayname))</span></td>"
                        $platformCell  = "<td><span class='platform-label'>$([System.Web.HttpUtility]::HtmlEncode($item.Platform))</span></td>"

                        if ($CurrentPolicyType -eq 'mobileApps') {
                            $rowHtml = "<tr class='policy-row' data-assignmenttype='$([System.Web.HttpUtility]::HtmlAttributeEncode($item.AssignmentType))'>$groupNameCell$groupIdCell$platformCell$assignmentTypeCell$filterDisplayCell$filterTypeCell$installIntentCell</tr>"
                        } elseif ($CurrentPolicyType -in @('deviceCustomAttributeShellScripts','intents','deviceShellScripts','deviceManagementScripts')) {
                            $rowHtml = "<tr class='policy-row' data-assignmenttype='$([System.Web.HttpUtility]::HtmlAttributeEncode($item.AssignmentType))'>$groupNameCell$groupIdCell$platformCell$assignmentTypeCell</tr>"
                        } else {
                            $rowHtml = "<tr class='policy-row' data-assignmenttype='$([System.Web.HttpUtility]::HtmlAttributeEncode($item.AssignmentType))'>$groupNameCell$groupIdCell$platformCell$assignmentTypeCell$filterDisplayCell$filterTypeCell</tr>"
                        }
                        $rows += $rowHtml
                    }
                }
            }

            $assignmentTypesAttr = ''
            if (-not $isUnassigned) {
                $assignmentTypesForPolicy = $assignments | Where-Object { $_.AssignmentType } | Select-Object -ExpandProperty AssignmentType -Unique
                $assignmentTypesAttr = ($assignmentTypesForPolicy -join ';')
            }
            $intentsAttr = ''
            if ($CurrentPolicyType -eq 'mobileApps' -and -not $isUnassigned) { $intentsAttr = ($intentsForPolicy -join ';') }
            $hasFilterAttr = if ($hasFilterForPolicy) { 'True' } else { 'False' }
            if ($CurrentPolicyType -eq 'mobileApps') { $tableHeader = '<th>Group</th><th>GroupId</th><th>Platform</th><th>Assignment</th><th>Filter</th><th>Filter Type</th><th>Intent</th>' } elseif ($CurrentPolicyType -in @('deviceCustomAttributeShellScripts','intents','deviceShellScripts','deviceManagementScripts')) { $tableHeader = '<th>Group</th><th>GroupId</th><th>Platform</th><th>Assignment</th>' } else { $tableHeader = '<th>Group</th><th>GroupId</th><th>Platform</th><th>Assignment</th><th>Filter</th><th>Filter Type</th>' }
            $badge = ''

            $descBlock = if ($needsToggle) {
                "<div class='policy-desc small text-muted' data-full='$descFullAttr' data-short='$descShortAttr'>"+
                "<span class='desc-text'>$descShort</span>"+
                " <button type='button' class='btn btn-link p-0 ms-1 small desc-toggle' onclick='toggleDesc(this)' data-state='short'>More</button>"+
                "</div>"
            } else { "<div class='policy-desc small text-muted'>$descShort</div>" }

            if ($isUnassigned) {
$policyBlock = @"
<div class='card mb-3 policy-block border-start-accent unassigned' data-policy='$([System.Web.HttpUtility]::HtmlAttributeEncode($policyName))' data-platform='$platform' data-unassigned='True' data-assignmenttypes='' data-intents='' data-hasfilter='False'>
  <div class='card-header bg-primary-gradient text-white'>
    <h5 class='mb-0'>$([System.Web.HttpUtility]::HtmlEncode($policyName))$badge</h5>
  </div>
  <div class='card-body p-0'>
    <div class='p-3 pt-3 pb-2'>
      $descBlock
      <div class='mt-2 small text-warning fw-semibold'><span class='badge bg-warning text-dark'>Unassigned</span></div>
    </div>
  </div>
</div>
"@
            } else {
$policyBlock = @"
<div class='card mb-3 policy-block border-start-accent' data-policy='$([System.Web.HttpUtility]::HtmlAttributeEncode($policyName))' data-platform='$platform' data-unassigned='False' data-assignmenttypes='$([System.Web.HttpUtility]::HtmlAttributeEncode($assignmentTypesAttr))' data-intents='$([System.Web.HttpUtility]::HtmlAttributeEncode($intentsAttr))' data-hasfilter='$hasFilterAttr'>
  <div class='card-header bg-primary-gradient text-white'>
    <h5 class='mb-0'>$([System.Web.HttpUtility]::HtmlEncode($policyName))$badge</h5>
  </div>
  <div class='card-body p-0'>
    <div class='p-3 pt-3 pb-2'>$descBlock</div>
    <div class='table-responsive'>
      <table class='table table-sm mb-0 align-middle'>
        <thead class='table-header-modern'><tr>$tableHeader</tr></thead>
        <tbody>
$(($rows -join "`n"))
        </tbody>
      </table>
    </div>
  </div>
</div>
"@
            }
            $platformSections += [pscustomobject]@{ Platform=$platform; Html=$policyBlock; Unassigned=$isUnassigned }
        }

        # Summary data
        $summaryGrouped = $platformSections | Group-Object Platform
        $summaryData = foreach ($sg in $summaryGrouped) { $un = ($sg.Group | Where-Object { $_.Unassigned }).Count; $total=$sg.Count; [pscustomobject]@{ Platform=$sg.Name; Total=$total; Assigned=($total-$un); Unassigned=$un } }
        $overallTotal = ($summaryData | Measure-Object Total -Sum).Sum
        $overallAssigned = ($summaryData | Measure-Object Assigned -Sum).Sum
        $overallUnassigned = ($summaryData | Measure-Object Unassigned -Sum).Sum
        $overallAssignedPct = if ($overallTotal) { [math]::Round(($overallAssigned/$overallTotal)*100,1) } else { 0 }
        $overallUnassignedPct = if ($overallTotal) { [math]::Round(($overallUnassigned/$overallTotal)*100,1) } else { 0 }
$overallSummaryCard = @"
<div class='card shadow-sm mb-3 summary-card border-0'>
  <div class='card-body p-3'>
    <div class='d-flex justify-content-between flex-wrap gap-3 align-items-center'>
      <div>
        <h2 class='h5 mb-2 text-primary'>Overview</h2>
        <div class='small text-muted'>Total Policies: <strong>$overallTotal</strong></div>
        <div class='small text-success'>Assigned: <strong>$overallAssigned</strong> (${overallAssignedPct}%)</div>
        <div class='small text-warning'>Unassigned: <strong>$overallUnassigned</strong> (${overallUnassignedPct}%)</div>
      </div>
      <div class='flex-grow-1'>
        <div class='progress prog-overall' style='height:22px;'>
          <div class='progress-bar bg-assigned fw-semibold' role='progressbar' style='width: ${overallAssignedPct}%;' title='Assigned ${overallAssignedPct}%'></div>
          <div class='progress-bar bg-warning text-dark fw-semibold' role='progressbar' style='width: ${overallUnassignedPct}%;' title='Unassigned ${overallUnassignedPct}%'></div>
        </div>
      </div>
    </div>
  </div>
</div>
"@
        $platformCards = foreach ($row in ($summaryData | Sort-Object Platform)) { $assignedPct = if ($row.Total) { [math]::Round(($row.Assigned/$row.Total)*100,1) } else { 0 }; $unassignedPct = if ($row.Total) { [math]::Round(($row.Unassigned/$row.Total)*100,1) } else { 0 }; $platformSafe=[System.Web.HttpUtility]::HtmlEncode($row.Platform); @"
<div class='col-12 col-sm-6 col-md-4 col-lg-3'>
  <div class='card h-100 border-0 platform-card'>
    <div class='card-body p-3'>
      <h3 class='h6 mb-2 text-primary'>$platformSafe</h3>
      <div class='small mb-2 text-muted'>Total: <strong>$($row.Total)</strong></div>
      <div class='d-flex justify-content-between small mb-1 fw-semibold'>
        <span class='text-success' title='Assigned policies'>A: $($row.Assigned)</span>
        <span class='text-warning' title='Unassigned policies'>U: $($row.Unassigned)</span>
      </div>
      <div class='progress progress-thin mb-1'>
        <div class='progress-bar bg-assigned' role='progressbar' style='width: ${assignedPct}%;' title='Assigned ${assignedPct}%'></div>
        <div class='progress-bar bg-warning' role='progressbar' style='width: ${unassignedPct}%;' title='Unassigned ${unassignedPct}%'></div>
      </div>
      <div class='text-muted small'>A ${assignedPct}% / U ${unassignedPct}%</div>
    </div>
  </div>
</div>
"@ }
$platformSummaryHtml = @"
$overallSummaryCard
<div class='row g-3'>
$([string]::Join("`n", $platformCards))
</div>
"@
        $platformGrouped = $platformSections | Group-Object Platform
        $platformHtml = foreach ($pg in $platformGrouped) {
            $groupHtml = ($pg.Group | ForEach-Object { $_.Html }) -join ''
            $platNameRaw = $pg.Name
            $platId = $platNameRaw.Replace(' ','-').ToLower()
            $platNameEsc = [System.Web.HttpUtility]::HtmlEncode($platNameRaw)
            "<div class='platform-section' data-platform='$platNameEsc'><h3 id='plat-$platId' class='mt-5 mb-3 section-title text-primary-dark'>$platNameEsc</h3>$groupHtml</div>"
        }
        $platformHtmlJoined = ($platformHtml -join "`n")

$searchScript = @'
<script>
function collectChecked(cls){return [...document.querySelectorAll('.'+cls+':checked')].map(c=>c.value.toLowerCase());}
function applyFilters(){
  const q = document.getElementById('searchBox').value.toLowerCase();
  const scope = document.getElementById('searchScope')?.value || 'all';
  const plat = document.getElementById('platformFilter').value;
  const unOnly = (document.getElementById('adv-unassignedOnly')?.checked);
  const assTypes = collectChecked('flt-assignment');
  const intents  = collectChecked('flt-intent');
  const hasFilterChoice = document.querySelector('input[name="flt-hasfilter"]:checked')?.value || 'any';
  document.querySelectorAll('.policy-block').forEach(pb=>{
    const name = pb.getAttribute('data-policy').toLowerCase();
    const platform = pb.getAttribute('data-platform');
    const unassigned = pb.getAttribute('data-unassigned') === 'True';
    const pbAssTypes = (pb.getAttribute('data-assignmenttypes')||'').toLowerCase().split(';').filter(x=>x);
    const pbIntents  = (pb.getAttribute('data-intents')||'').toLowerCase().split(';').filter(x=>x);
    const hasFilter  = pb.getAttribute('data-hasfilter') === 'True';
    const desc = (pb.querySelector('.policy-desc')?.textContent||'').toLowerCase();
    const groupNames = [...pb.querySelectorAll('.grp-name')].map(g=>g.textContent.toLowerCase());
    let show = true;
    if(q){
      let matched=false;
      if(scope==='name') matched = name.includes(q);
      else if(scope==='description') matched = desc.includes(q);
      else if(scope==='group') matched = groupNames.some(g=>g.includes(q));
      else matched = name.includes(q)||desc.includes(q)||groupNames.some(g=>g.includes(q));
      if(!matched) show=false;
    }
    if(plat && plat !== 'ALL' && platform !== plat) show=false;
    if(unOnly && !unassigned) show=false;
    if(!unOnly){
      if(assTypes.length && !assTypes.some(a=>pbAssTypes.includes(a))) show=false;
      if(intents.length && !intents.some(i=>pbIntents.includes(i))) show=false;
      if(hasFilterChoice==='yes' && !hasFilter) show=false; else if(hasFilterChoice==='no' && hasFilter) show=false;
    }
    pb.style.display = show ? '' : 'none';
  });
  document.querySelectorAll('.platform-section').forEach(sec=>{
    const anyVisible = [...sec.querySelectorAll('.policy-block')].some(b=>b.style.display !== 'none');
    sec.style.display = anyVisible ? '' : 'none';
  });
  updateSummary();
}
function updateSummary(){
  const container = document.getElementById('platformSummaryContent');
  if(!container) return;
  const visibleBlocks = [...document.querySelectorAll('.policy-block')].filter(b=>b.style.display !== 'none');
  if(!visibleBlocks.length){ container.innerHTML = '<div class="alert alert-info small mb-0">No policies match current filters.</div>'; return; }
  const map = new Map();
  visibleBlocks.forEach(b=>{ const plat=b.getAttribute('data-platform'); const un=b.getAttribute('data-unassigned')==='True'; if(!map.has(plat)) map.set(plat,{total:0,un:0}); const o=map.get(plat); o.total++; if(un) o.un++; });
  let overallTotal=0, overallUn=0; map.forEach(v=>{overallTotal+=v.total; overallUn+=v.un;});
  const overallAssigned = overallTotal - overallUn;
  const overallAssignedPct = overallTotal? ((overallAssigned/overallTotal)*100).toFixed(1):0;
  const overallUnPct = overallTotal? ((overallUn/overallTotal)*100).toFixed(1):0;
  let html = `
  <div class='card shadow-sm mb-3 summary-card border-0'>
    <div class='card-body p-3'>
      <div class='d-flex justify-content-between flex-wrap gap-3 align-items-center'>
        <div>
          <h2 class='h5 mb-2 text-primary'>Overview</h2>
          <div class='small text-muted'>Total Policies: <strong>${overallTotal}</strong></div>
          <div class='small text-success'>Assigned: <strong>${overallAssigned}</strong> (${overallAssignedPct}%)</div>
          <div class='small text-warning'>Unassigned: <strong>${overallUn}</strong> (${overallUnPct}%)</div>
        </div>
        <div class='flex-grow-1'>
          <div class='progress prog-overall' style='height:22px;'>
            <div class='progress-bar bg-assigned fw-semibold' role='progressbar' style='width: ${overallAssignedPct}%;' title='Assigned ${overallAssignedPct}%'></div>
            <div class='progress-bar bg-warning text-dark fw-semibold' role='progressbar' style='width: ${overallUnPct}%;' title='Unassigned ${overallUnPct}%'></div>
          </div>
        </div>
      </div>
    </div>
  </div>`;
  const cards = [...map.entries()].sort((a,b)=>a[0].localeCompare(b[0])).map(([plat,v])=>{
    const assigned = v.total - v.un; const aPct = v.total? ((assigned/v.total)*100).toFixed(1):0; const uPct = v.total? ((v.un/v.total)*100).toFixed(1):0;
    return `<div class='col-12 col-sm-6 col-md-4 col-lg-3'>
  <div class='card h-100 border-0 platform-card'>
    <div class='card-body p-3'>
      <h3 class='h6 mb-2 text-primary'>${plat}</h3>
      <div class='small mb-2 text-muted'>Total: <strong>${v.total}</strong></div>
      <div class='d-flex justify-content-between small mb-1 fw-semibold'>
        <span class='text-success' title='Assigned policies'>A: ${assigned}</span>
        <span class='text-warning' title='Unassigned policies'>U: ${v.un}</span>
      </div>
      <div class='progress progress-thin mb-1'>
        <div class='progress-bar bg-assigned' role='progressbar' style='width: ${aPct}%;' title='Assigned ${aPct}%'></div>
        <div class='progress-bar bg-warning' role='progressbar' style='width: ${uPct}%;' title='Unassigned ${uPct}%'></div>
      </div>
      <div class='text-muted small'>A ${aPct}% / U ${uPct}%</div>
    </div>
  </div>
</div>`; }).join('');
  html += `\n<div class='row g-3'>${cards}</div>`;
  container.innerHTML = html;
}
function toggleDesc(btn){
  const wrap = btn.closest('.policy-desc');
  const span = wrap.querySelector('.desc-text');
  const state = btn.getAttribute('data-state');
  const full = wrap.getAttribute('data-full');
  const short = wrap.getAttribute('data-short');
  if(state==='short'){ span.textContent = full; btn.textContent='Less'; btn.setAttribute('data-state','full'); wrap.classList.add('expanded'); }
  else { span.textContent = short; btn.textContent='More'; btn.setAttribute('data-state','short'); wrap.classList.remove('expanded'); }
}
function clearAdvanced(){
  document.querySelectorAll('.flt-assignment, .flt-intent').forEach(c=>c.checked=false);
  const any = document.getElementById('hf-any'); if(any) any.checked=true;
  const uaA = document.getElementById('adv-unassignedOnly'); if(uaA) uaA.checked=false;
  document.getElementById('searchBox').value='';
  applyFilters();
}
function toggleUnassignedMode(){
  const unOnly = (document.getElementById('adv-unassignedOnly')?.checked);
  const disableEls = document.querySelectorAll('.flt-assignment, .flt-intent, input[name="flt-hasfilter"]');
  disableEls.forEach(el=>{ el.disabled = unOnly; const wrap = el.closest('.form-check') || el.closest('div'); if(wrap){ wrap.classList.toggle('disabled-filter', unOnly); }});
  applyFilters();
}
['platformFilter','searchBox','adv-unassignedOnly','searchScope'].forEach(id=>{ const el=document.getElementById(id); if(el){ el.addEventListener((id==='searchBox')?'keyup':'change', e=>{ if(id==='adv-unassignedOnly'){ toggleUnassignedMode(); } else { applyFilters(); } }); }});
['change','click','keyup'].forEach(ev=>{ document.addEventListener(ev, e=>{ if(e.target.matches('.flt-assignment, .flt-intent, input[name="flt-hasfilter"]')) applyFilters(); }); });
window.addEventListener('DOMContentLoaded', ()=>{ toggleUnassignedMode(); updateSummary(); });
window.addEventListener('click', e=>{ const t=e.target; if(t.classList && t.classList.contains('id-code')){ navigator.clipboard.writeText(t.getAttribute('data-full')); t.classList.add('copied'); setTimeout(()=>t.classList.remove('copied'),1300); }});
</script>
'@

# Precompute install intent option lines (avoid inline if inside here-string)
$intentOptionLines = if ($CurrentPolicyType -eq 'mobileApps') {
    @(
        "          <div class='form-check form-switch small'><input class='form-check-input flt-intent' type='checkbox' value='required' id='int-required'><label class='form-check-label' for='int-required'>Required</label></div>",
        "          <div class='form-check form-switch small'><input class='form-check-input flt-intent' type='checkbox' value='available' id='int-available'><label class='form-check-label' for='int-available'>Available</label></div>",
        "          <div class='form-check form-switch small'><input class='form-check-input flt-intent' type='checkbox' value='uninstall' id='int-uninstall'><label class='form-check-label' for='int-uninstall'>Uninstall</label></div>"
    )
} else {
    @("          <div class='text-muted small fst-italic'>N/A</div>")
}

# Advanced filters panel updated to include Unassigned Only toggle
$advancedFiltersHtml = @"
<div class='advanced-filters collapse mt-2' id='advFilters'>
  <div class='card card-body p-3 shadow-sm'>
    <div class='row g-3'>      <div class='col-12 col-lg-3'>
        <div class='small text-muted fw-semibold mb-1'>Assignment Types</div>
        <div class='d-flex flex-column gap-1'>
          <div class='form-check form-switch small'><input class='form-check-input flt-assignment' type='checkbox' value='include' id='ass-include'><label class='form-check-label' for='ass-include'>Include</label></div>
          <div class='form-check form-switch small'><input class='form-check-input flt-assignment' type='checkbox' value='exclude' id='ass-exclude'><label class='form-check-label' for='ass-exclude'>Exclude</label></div>
        </div>
      </div>
      <div class='col-12 col-lg-3'>
        <div class='small text-muted fw-semibold mb-1'>Filter Presence</div>
        <div class='d-flex flex-column gap-1'>
          <div class='form-check form-switch small'><input class='form-check-input' type='radio' name='flt-hasfilter' id='hf-any' value='any' checked><label class='form-check-label' for='hf-any'>Any</label></div>
          <div class='form-check form-switch small'><input class='form-check-input' type='radio' name='flt-hasfilter' id='hf-yes' value='yes'><label class='form-check-label' for='hf-yes'>Has Filter</label></div>
          <div class='form-check form-switch small'><input class='form-check-input' type='radio' name='flt-hasfilter' id='hf-no' value='no'><label class='form-check-label' for='hf-no'>No Filter</label></div>
        </div>
      </div>
      <div class='col-12 col-lg-3'>
        <div class='small text-muted fw-semibold mb-1'>Install Intents</div>
        <div class='d-flex flex-column gap-1'>
$([string]::Join("`n", $intentOptionLines))
        </div>
      </div>
      <div class='col-12 col-lg-3'>
        <div class='small text-muted fw-semibold mb-1'>Mode & Actions</div>
        <div class='d-flex flex-column gap-2'>
          <div class='form-check form-switch small'><input class='form-check-input' type='checkbox' id='adv-unassignedOnly'><label class='form-check-label' for='adv-unassignedOnly'>Unassigned Only</label></div>
          <div class='d-flex gap-2 flex-wrap'>
            <button type='button' class='btn btn-sm btn-outline-secondary' onclick='clearAdvanced()'>Clear</button>
            <button type='button' class='btn btn-sm btn-outline-primary' data-bs-toggle='collapse' data-bs-target='#advFilters'>Close</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
"@

        # Inject advanced filters into main HTML layout (augment existing $html generation below)
        # ...existing code building $html before header bar...
        $html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='utf-8'/>
<title>Assignment Report - $CurrentPolicyType</title>
<meta name='viewport' content='width=device-width,initial-scale=1'/>
<link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css' rel='stylesheet'/>
<link rel='icon' type='image/x-icon' href='data:image/x-icon;base64,$iconBase64'>
<style>
:root { --primary:#007ACC; --primary-dark:#005A9E; --muted:#888888; }
body{padding:24px;background:#f5f7fa;font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;}
.header-logo{width:72px;height:72px;border-radius:12px;box-shadow:0 3px 8px rgba(0,0,0,.18);background:#fff;padding:6px;object-fit:contain;}
.header-icon{width:40px;height:40px;border-radius:6px;box-shadow:0 2px 4px rgba(0,0,0,.15);background:#fff;padding:4px;}
.header-bar{background:linear-gradient(135deg,var(--primary-dark),var(--primary));color:#fff;border-radius:12px;padding:18px 24px;box-shadow:0 4px 12px rgba(0,0,0,.15);}
.header-bar h1{font-weight:600;}
.filters select, .filters input{min-width:170px;}
.section-title{position:relative;padding-left:8px;}
.section-title:before{content:'';position:absolute;left:0;top:0;bottom:0;width:4px;background:var(--primary);border-radius:2px;}
.card{border-radius:12px;box-shadow:0 2px 6px rgba(0,0,0,.08);}
.card-header{border-top-left-radius:12px;border-top-right-radius:12px;}
.bg-primary-gradient{background:linear-gradient(135deg,var(--primary-dark),var(--primary));}
.platform-card{background:linear-gradient(180deg,#ffffff,#f0f6fb);}
.border-start-accent{border-left:5px solid var(--primary)!important;}
.progress{background:#e6eef4;}
.progress-thin{height:8px;}
.bg-assigned{background:var(--primary-dark)!important;}
.summary-card .progress{background:#d9e7f2;}
.policy-desc:not(.expanded) .desc-text{display:inline-block;}
.policy-desc.expanded .desc-text{white-space:normal;}
.desc-toggle{color:var(--primary)!important;text-decoration:none;}
.desc-toggle:hover{text-decoration:underline;}
.table-header-modern th{position:sticky;top:0;z-index:1;font-size:.90rem;letter-spacing:.05em;text-transform:uppercase;font-weight:600;background:linear-gradient(135deg,var(--primary-dark),var(--primary));color:#fff;border-bottom:0;}
.policy-block table tbody td{font-size:.95rem;vertical-align:middle;padding:.35rem .55rem;}
.policy-block table tbody tr{transition:background-color .15s ease;}
.policy-block table tbody tr:hover{background:#eef6fc;}
.grp-name{font-weight:600;}
.id-code{font-size:.70rem;background:#eef3f8;padding:.15rem .35rem;border-radius:4px;display:inline-block;cursor:pointer;transition:.2s;}
.id-code:hover{background:#d9e7f2;}
.id-code.copied{background:var(--primary-dark);color:#fff;}
.assignment-badge, .intent-badge, .filter-badge, .filtertype-badge{font-size:.70rem;letter-spacing:.03em;padding:.32em .60em;border-radius:6px;font-weight:600;}
.assignment-badge.badge-required, .intent-badge.intent-required{background:var(--primary-dark);color:#fff;}
.assignment-badge.badge-available, .intent-badge.intent-available{background:#6c7a86;color:#fff;}
.assignment-badge.badge-uninstall, .intent-badge.intent-uninstall{background:#dc3545;color:#fff;}
.assignment-badge.badge-include{background:#198754;color:#fff;}
.assignment-badge.badge-exclude{background:#fd7e14;color:#fff;}
.assignment-badge.badge-generic{background:#607d8b;color:#fff;}
.intent-badge.intent-na{background:#8899aa;color:#fff;}
.intent-badge.intent-generic{background:#5a6b7c;color:#fff;}
.filter-badge{background:#0dcaf0;color:#063545;}
.filtertype-badge{background:#b1d5e8;color:#14323f;}
.platform-label{font-weight:500;}
.policy-block.unassigned .card-header{background:linear-gradient(135deg,var(--primary-dark),var(--primary))}
.form-check-input:checked{background-color:var(--primary);border-color:var(--primary);} 
.form-check-input{cursor:pointer;}
.advanced-filters .card{border:1px solid #d0dae3;background:#ffffff;}
.advanced-filters .form-check-label{cursor:pointer;}
.advanced-filters .form-check-input:checked{background-color:var(--primary);border-color:var(--primary);} 
.disabled-filter{opacity:.45;}
</style>
</head>
<body>
<div class='container-fluid'>
  <div class='header-bar mb-4 d-flex flex-wrap justify-content-between align-items-center gap-4'>
    <div class='d-flex align-items-center gap-3'>
      $iconImg
      <div>
        <h1 class='h4 mb-1'>Assignment Report - $CurrentPolicyType</h1>
        <div class='small opacity-75'>Tenant: $tenantName &nbsp;|&nbsp; Generated: $generated</div>
      </div>
    </div>
    <div class='d-flex gap-2 align-items-start flex-wrap filters'>
      <div class='input-group input-group-sm'>
        <input id='searchBox' class='form-control' placeholder='Search...' />
        <select id='searchScope' class='form-select'>
          <option value='all' selected>All</option>
          <option value='name'>Name</option>
          <option value='description'>Description</option>
          <option value='group'>Group</option>
        </select>
      </div>
      <select id='platformFilter' class='form-select form-select-sm'>
        <option value='ALL'>All Platforms</option>
$([string]::Join('', ($summaryData.Platform | Sort-Object -Unique | ForEach-Object { "<option value='$_'>$_</option>" })) )
      </select>
      <button class='btn btn-sm btn-outline-light mt-1' type='button' data-bs-toggle='collapse' data-bs-target='#advFilters'>Advanced ▾</button>
    </div>
  </div>
  $advancedFiltersHtml
  <div class='mb-4'>
    <h2 class='h5 text-primary-dark mb-3'>Platform Summary</h2>
    <div id='platformSummaryContent'>
      $platformSummaryHtml
    </div>
  </div>
  $platformHtmlJoined
</div>
$searchScript
<script src='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js'></script>
</body>
</html>
"@
        # Inject disabled style
        if($html -notmatch 'disabled-filter'){ $html = $html -replace '</style>', '.disabled-filter{opacity:.45;}\n</style>' }
        # Replace advancedFiltersHtml placeholder
        $html = $html -replace '\$advancedFiltersHtml', [System.Text.RegularExpressions.Regex]::Escape($advancedFiltersHtml) -replace [System.Text.RegularExpressions.Regex]::Escape($advancedFiltersHtml), $advancedFiltersHtml
        # Replace searchScript placeholder
        $html = $html -replace '\$searchScript', [System.Text.RegularExpressions.Regex]::Escape($searchScript) -replace [System.Text.RegularExpressions.Regex]::Escape($searchScript), $searchScript        # Write file
        $html | Out-File -FilePath $OutputPath -Encoding utf8
        Write-IntuneToolkitLog -Message "Exported policy data to HTML file at $OutputPath" -Component "ExportToHtml"
        
        # Auto-open the HTML file
        try {
            Start-Process -FilePath $OutputPath
            Write-IntuneToolkitLog "Launched HTML report: $OutputPath" -component "ExportToHtml" -file "AssignmentReportButton.ps1"
        } catch {
            Write-IntuneToolkitLog "Failed to auto-open HTML report: $($_.Exception.Message)" -component "ExportToHtml" -file "AssignmentReportButton.ps1"
        }
    } catch {
        Write-IntuneToolkitLog -Message "An error occurred during HTML export: $_" -Component "ExportToHtml" -Severity "Error"
        [System.Windows.MessageBox]::Show("An error occurred during HTML export: $_","Export Failed",[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error)
    }
} # end Export-ToHtml

# Handler for Assignment Report button
$AssignmentReportButton.Add_Click({
    try {
        Write-IntuneToolkitLog "AssignmentReportButton clicked" -component "AssignmentReport-Button" -file "AssignmentReportButton.ps1"

        # Get items to export (selected or all)
        $policies = Get-PoliciesToExport -AllPolicies $global:AllPolicyData -DataGrid $PolicyDataGrid
        if (-not $policies -or $policies.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No policies to export.", "Information")
            return
        }

        # Show export format options
        $formats = Show-ExportOptionsDialog
        if (-not $formats -or $formats.Count -eq 0) { return }

        # Ensure Windows Forms types
        Add-Type -AssemblyName System.Windows.Forms
        $baseName = "AssignmentReport_$($global:CurrentPolicyType)_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"

        foreach ($fmt in $formats) {
            switch ($fmt) {
                'Markdown' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter   = 'Markdown (*.md)|*.md|All (*.*)|*.*'
                    $dlg.Title    = 'Save Assignment Report as Markdown'
                    $dlg.FileName = "$baseName.md"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        Export-ToMarkdown -OutputPath $dlg.FileName -PolicyDataGrid $policies -CurrentPolicyType $global:CurrentPolicyType
                    }
                }
                'CSV' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter   = 'CSV (*.csv)|*.csv|All (*.*)|*.*'
                    $dlg.Title    = 'Save Assignment Report as CSV'
                    $dlg.FileName = "$baseName.csv"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        Export-ToCsv -OutputPath $dlg.FileName -PolicyItems $policies
                    }
                }
                'HTML' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter   = 'HTML (*.html)|*.html|All (*.*)|*.*'
                    $dlg.Title    = 'Save Assignment Report as HTML'
                    $dlg.FileName = "$baseName.html"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        Export-ToHtml -OutputPath $dlg.FileName -PolicyDataGrid $policies -CurrentPolicyType $global:CurrentPolicyType
                    }
                }
            }
        }

        [System.Windows.MessageBox]::Show("Export complete.", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    } catch {
        Write-IntuneToolkitLog "Error in AssignmentReportButton: $_" -component "AssignmentReport-Button" -file "AssignmentReportButton.ps1"
        [System.Windows.MessageBox]::Show("Failed to generate assignment report: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
}) # end click handler
