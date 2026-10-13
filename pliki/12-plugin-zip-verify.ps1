# Modul 12, cwiczenie 05: pakiet pluginu do instalacji air-gapped (wariant PowerShell 7).
# Pobiera ZIP z katalogu grafana.com dla wskazanej platformy, porownuje sha256
# z API katalogu, rozpakowuje i sprawdza pliki wobec MANIFEST.txt tak jak
# Grafana przy starcie. Na koncu przewiduje status podpisu.
#
# Uzycie:
#   .\pliki\12-plugin-zip-verify.ps1 -Id grafana-clock-panel [-Version 3.2.4] [-Platform linux-amd64]
#   .\pliki\12-plugin-zip-verify.ps1 -Check .\plugins-airgap\grafana-clock-panel
#   -OutDir  katalog na pakiety i rozpakowane pluginy (domyslnie .\plugins-airgap)
#
# Przewidywanie jak w 12-plugin-zip-verify.sh: brak MANIFEST.txt -> unsigned;
# inna suma, brak pliku, plik spoza manifestu, inne id/wersja -> modified.
[CmdletBinding(DefaultParameterSetName = 'Download')]
param(
    [Parameter(ParameterSetName = 'Download', Mandatory, Position = 0)] [string] $Id,
    [Parameter(ParameterSetName = 'Download')] [string] $Version,
    [Parameter(ParameterSetName = 'Download')] [string] $Platform = 'any',
    [Parameter(ParameterSetName = 'Download')] [string] $OutDir = 'plugins-airgap',
    [Parameter(ParameterSetName = 'Check', Mandatory)] [string] $Check
)
$ErrorActionPreference = 'Stop'
$Api = 'https://grafana.com/api/plugins'

function Test-PluginDir([string] $Dir) {
    $Dir = (Resolve-Path $Dir).Path
    $manifestPath = Join-Path $Dir 'MANIFEST.txt'
    if (-not (Test-Path $manifestPath)) {
        'MANIFEST.txt: brak'
        'PRZEWIDYWANIE: unsigned (signatureMissing); zaladuje sie tylko z allow_loading_unsigned_plugins'
        return
    }
    # JSON manifestu to tresc miedzy linia "{" i "}" w bloku PGP SIGNED MESSAGE
    $lines = Get-Content $manifestPath
    $start = [array]::IndexOf($lines, '{'); $end = [array]::IndexOf($lines, '}')
    $m = ($lines[$start..$end] -join "`n") | ConvertFrom-Json -AsHashtable
    "MANIFEST.txt: plugin=$($m.plugin) wersja=$($m.version) signatureType=$($m.signatureType) signedByOrg=$($m.signedByOrg) plikow=$($m.files.Count)"
    if ($m.rootUrls) { "rootUrls: $($m.rootUrls -join ', ') - plugin zaladuje sie tylko przy takim root_url" }

    $bad = $false
    $pj = Get-Content (Join-Path $Dir 'plugin.json') -Raw | ConvertFrom-Json
    if ($pj.id -ne $m.plugin -or $pj.info.version -ne $m.version) {
        "plugin.json ($($pj.id) $($pj.info.version)) nie zgadza sie z manifestem"; $bad = $true
    }
    foreach ($f in $m.files.Keys) {
        $p = Join-Path $Dir $f
        if (-not (Test-Path $p)) { "${f}: brak pliku"; $bad = $true; continue }
        if ((Get-FileHash $p -Algorithm SHA256).Hash.ToLower() -ne $m.files[$f]) { "${f}: FAILED"; $bad = $true }
    }
    $extra = Get-ChildItem $Dir -Recurse -File |
        ForEach-Object { [IO.Path]::GetRelativePath($Dir, $_.FullName).Replace('\', '/') } |
        Where-Object { $_ -ne 'MANIFEST.txt' -and -not $m.files.ContainsKey($_) }
    if ($extra) { 'pliki spoza manifestu:'; $extra | ForEach-Object { "  $_" }; $bad = $true }

    if ($bad) { 'PRZEWIDYWANIE: modified (signatureModified); nie zaladuje sie nigdy, allowlista nie pomoze' }
    else { 'PRZEWIDYWANIE: valid - wszystkie pliki zgodne z MANIFEST.txt' }
}

if ($PSCmdlet.ParameterSetName -eq 'Check') { Test-PluginDir $Check; return }

if (-not $Version) { $Version = (Invoke-RestMethod "$Api/$Id").version }
$info = Invoke-RestMethod "$Api/$Id/versions/$Version"
$platforms = $info.packages.PSObject.Properties.Name
"$Id $($info.version): grafanaDependency $($info.grafanaDependency), pakiety: $($platforms -join ', ')"
if ($platforms -notcontains $Platform) {
    Write-Warning "brak pakietu $Platform - plugin ma tylko: $($platforms -join ', '); biore any"
    $Platform = 'any'
}
$expected = $info.packages.$Platform.sha256

$url = "$Api/$Id/versions/$Version/download"
if ($Platform -ne 'any') { $os, $arch = $Platform -split '-', 2; $url += "?os=$os&arch=$arch" }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$zip = Join-Path $OutDir "$Id-$Version.$Platform.zip"
# download to 302 na storage.googleapis.com - allowlista proxy musi objac oba hosty
Invoke-WebRequest $url -OutFile $zip
$actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
"pakiet:          $zip ($((Get-Item $zip).Length) B)"
"sha256 katalog:  $expected"
"sha256 plik:     $actual"
if ($expected -ne $actual) { throw 'SUMA SIE NIE ZGADZA - nie instaluj' }
'sha256 OK'

# ZIP z katalogu ma juz katalog glowny <plugin-id>/ - rozpakowujesz do katalogu pluginow
$target = Join-Path $OutDir $Id
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
Expand-Archive $zip -DestinationPath $OutDir -Force
$gpx = Get-ChildItem $target -Filter 'gpx_*' -File
if ($gpx) { $gpx | ForEach-Object { "binarka backendu: $($_.Name)" } } else { 'binarka backendu: brak (plugin frontend-only)' }
Test-PluginDir $target
