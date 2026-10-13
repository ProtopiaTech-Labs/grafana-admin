# Modul 4, cwiczenie 07: adnotacja regionowa deploymentu.
# POST na starcie (punkt), PATCH z timeEnd i tagiem result:<ok|failed> na koncu (region).
#
# Uzycie:  .\04-annotate-deploy.ps1 -Service cart -Version 1.0.0 [-DeploySeconds 20] [-Result ok|failed] [-DashboardUid <uid>]
#          .\04-annotate-deploy.ps1 -Cleanup [-CleanupTags deploy,...]
#            usuwa Twoje adnotacje: tag owner:<Owner> plus podane tagi (AND)
#
# Srodowisko:
#   GRAFANA_URL    np. https://grafana.workshop2.indexoutofrange.com
#   GRAFANA_TOKEN  token service account (Authorization: Bearer)  albo
#   GRAFANA_AUTH   login:haslo (basic auth imiennego konta); token ma pierwszenstwo
#   OWNER          login do tagu owner:<login>; domyslnie login z GRAFANA_AUTH
# Ctrl+C w trakcie "deploymentu" zostawia punkt bez timeEnd i bez tagu result (celowo, do cwiczenia).
param(
  [string]$Service = 'cart',
  [string]$Version = '1.0.0',
  [int]$DeploySeconds = 20,
  [ValidateSet('ok', 'failed')][string]$Result = 'ok',
  [string]$DashboardUid = '',
  [string]$Owner = $env:OWNER,
  [switch]$Cleanup,
  [string[]]$CleanupTags = @()
)
$ErrorActionPreference = 'Stop'

if (-not $env:GRAFANA_URL) { throw 'Ustaw GRAFANA_URL' }
if ($env:GRAFANA_TOKEN) {
  $headers = @{ Authorization = "Bearer $env:GRAFANA_TOKEN" }
} elseif ($env:GRAFANA_AUTH) {
  $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:GRAFANA_AUTH))
  $headers = @{ Authorization = "Basic $basic" }
} else { throw 'Ustaw GRAFANA_TOKEN albo GRAFANA_AUTH=login:haslo' }
if (-not $Owner -and $env:GRAFANA_AUTH) { $Owner = $env:GRAFANA_AUTH.Split(':')[0] }
if (-not $Owner) { throw 'Ustaw OWNER=<login> albo podaj -Owner' }

$base = $env:GRAFANA_URL.TrimEnd('/')
function NowMs { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
function Api([string]$Method, [string]$Path, $Body) {
  $p = @{ Method = $Method; Uri = "$base$Path"; Headers = $headers; ContentType = 'application/json' }
  if ($Body) { $p.Body = ($Body | ConvertTo-Json -Compress) }
  Invoke-RestMethod @p
}

if ($Cleanup) {
  $q = (@("owner:$Owner") + $CleanupTags | ForEach-Object { "tags=$([uri]::EscapeDataString($_))" }) -join '&'
  # ForEach-Object rozwija tablice JSON: Invoke-RestMethod w PowerShell 7 oddaje ja jako jeden obiekt
  $found = @(Api Get "/api/annotations?$q&type=annotation&limit=1000" $null | ForEach-Object { $_ })
  foreach ($a in $found) { Api Delete "/api/annotations/$($a.id)" $null | Out-Null }
  "usunieto: $($found.Count) adnotacji z tagami owner:$Owner $($CleanupTags -join ' ')"
  return
}

$tags = @('deploy', "service:$Service", 'env:lab', "owner:$Owner")
$start = NowMs
$body = @{ time = $start; text = "Deploy $Service $Version - start"; tags = $tags }
if ($DashboardUid) { $body.dashboardUID = $DashboardUid }
$id = (Api Post '/api/annotations' $body).id
"start: annotation id=$id"

Start-Sleep -Seconds $DeploySeconds   # wlasciwy deployment (tu: symulacja)

$end = NowMs
Api Patch "/api/annotations/$id" @{ timeEnd = $end; text = "Deploy $Service $Version - $Result"; tags = $tags + "result:$Result" } | Out-Null
"koniec: result=$Result, czas trwania $([int](($end - $start) / 1000)) s"

Api Get "/api/annotations/$id" $null | Select-Object id, time, timeEnd, text, tags, dashboardUID, login | ConvertTo-Json -Compress
