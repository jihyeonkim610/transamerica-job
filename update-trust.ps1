# Updates the crew's memory after you play.
#  1. Moves saved run logs (transamerica-job-*.csv) from your Downloads folder into data\runs
#  2. Runs the Bruin pipeline: CSV -> DuckDB (data\heist.duckdb) -> trust table -> trust.json
#  3. Shows the new trust table
# Then, on the claude.ai page, click "Load trust.json" and pick trust.json from this folder.
#
# Run it from PowerShell in this folder:
#   powershell -ExecutionPolicy Bypass -File .\update-trust.ps1

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$runs  = Join-Path $root 'data\runs'
$bruin = Join-Path $env:USERPROFILE '.local\bin\bruin.exe'

New-Item -ItemType Directory -Force $runs | Out-Null
$header = Join-Path $runs '_header.csv'
if (-not (Test-Path $header)) {
  'run_id,scene,step,time,kind,speaker,role,location_before,move_to,escape_exit,escape_route,share_wanted,said,action,reason,secret_tip_to_police,dice,status_after,heat,loot,roadblocks,note' |
    Set-Content -Encoding ascii $header
}

# 1. Collect new logs from Downloads
$downloads = Join-Path $env:USERPROFILE 'Downloads'
$new = @(Get-ChildItem -Path $downloads -Filter 'transamerica-job-*.csv' -ErrorAction SilentlyContinue)
foreach ($f in $new) { Move-Item -Force $f.FullName (Join-Path $runs $f.Name) }
Write-Host ("Moved {0} new run log(s) from Downloads into data\runs" -f $new.Count)
$total = @(Get-ChildItem -Path $runs -Filter 'transamerica-job-*.csv').Count
Write-Host ("Run logs in data\runs: {0}" -f $total)

if (-not (Test-Path $bruin)) { throw "Bruin CLI not found at $bruin. Install it first." }

# 2. Run the pipeline from the project folder (paths in the pipeline are relative to it)
Push-Location $root
try {
  & $bruin run pipelines/trust
  if ($LASTEXITCODE -ne 0) { throw "The Bruin pipeline failed (see the messages above)." }

  # 3. Show the trust table
  Write-Host ""
  Write-Host "Trust table (row = who trusts, column = whom):"
  & $bruin query --connection heist-duckdb --query "SELECT * FROM (PIVOT mart.trust ON trustee USING first(trust_score) GROUP BY truster) ORDER BY truster"
} finally {
  Pop-Location
}
Write-Host ""
Write-Host "Done. trust.json is updated. On the claude.ai page click 'Load trust.json' and pick:"
Write-Host (Join-Path $root 'trust.json')
