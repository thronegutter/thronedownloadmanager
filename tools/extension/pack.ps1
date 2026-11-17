# Builds the browser extension for each browser family from extension/ (one background.js):
#   target/extension/chromium/  - manifest.json (Chrome, Edge, Brave, Opera, Vivaldi; load unpacked)
#   target/extension/firefox/   - manifest.firefox.json as manifest.json
#   target/extension/safari/    - manifest.safari.json as manifest.json (a folder only: tools/safari
#                                 builds it into the app as Safari's extension, macOS)
#   target/extension/mdm-chromium.zip - the chromium folder, zipped (a release download: unzip it
#                                       and load the folder unpacked)
#   target/extension/mdm-firefox.xpi  - the firefox folder, zipped (Firefox needs it signed by AMO
#                                       to install for good; about:debugging loads it unsigned)
#   target/extension/mdm-chrome-store.zip - what is uploaded to the Chrome Web Store (see below)
# Both manifests get the app's version (Cargo.toml), so an extension and its app always match.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$src = Join-Path $root "extension"
# Joined part by part: .NET (the zips below) takes a backslash literally on Linux and macOS.
$out = Join-Path (Join-Path $root "target") "extension"
$cargo = Get-Content (Join-Path $root "Cargo.toml") -Raw
$ipc = Get-Content -LiteralPath (Join-Path $root "crates/ipc/src/extension.rs") -Raw
$firefoxHost = [regex]::Match($ipc, 'FIREFOX_HOST_NAME: &str = "([^"]+)"').Groups[1].Value
if (-not $firefoxHost) { throw "no Firefox native host in crates/ipc/src/extension.rs" }
$encoding = New-Object Text.UTF8Encoding $false
$version = [regex]::Match($cargo, '(?m)^version\s*=\s*"([^"]+)"').Groups[1].Value
if (-not $version) { throw "no version in Cargo.toml" }
# The stores take one to four dot-separated numbers only (no "-rc.1").
if ($version -notmatch '^\d+(\.\d+){0,3}$') { throw "version ${version}: browsers take only numbers like 1.2.3" }
foreach ($kind in "chromium", "firefox", "safari") {
  $dir = Join-Path $out $kind
  if (Test-Path $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
  New-Item -ItemType Directory -Force $dir | Out-Null
  # The background part; the download button over videos and the Alt-click watcher (content
  # scripts in every page); the toolbar button's popup.
  foreach ($f in "background.js", "video.js", "page.js", "popup.html", "popup.css", "popup.js") {
    Copy-Item (Join-Path $src $f) $dir
  }
  Copy-Item (Join-Path $src "icons") (Join-Path $dir "icons") -Recurse
  # Its texts in the browser's language (tools/extension/locales.py).
  Copy-Item (Join-Path $src "_locales") (Join-Path $dir "_locales") -Recurse
  if ($kind -eq "firefox") {
    # Use the desktop icon and Throne Blue palette for the Firefox package.
    $appIcons = Join-Path $root "crates/app/assets/icons/app"
    foreach ($size in 16, 32, 48, 128) {
      Copy-Item -LiteralPath (Join-Path $appIcons "mdm-$size.png") (Join-Path $dir "icons/icon-$size.png")
    }
    $video = Join-Path $dir "video.js"
    $videoCode = [IO.File]::ReadAllText($video)
    $originalLogo = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $src "icons/icon-48.png")))
    $throneLogo = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $appIcons "mdm-48.png")))
    if (-not $videoCode.Contains($originalLogo)) { throw "no embedded logo in video.js" }
    [IO.File]::WriteAllText($video, $videoCode.Replace($originalLogo, $throneLogo), $encoding)
    $popup = Join-Path $dir "popup.css"
    $palette = [IO.File]::ReadAllText((Join-Path $src "popup.firefox.css"))
    [IO.File]::AppendAllText($popup, "`n" + $palette, $encoding)
    foreach ($file in @((Join-Path $dir "popup.html"), (Join-Path $dir "video.js")) +
        @(Get-ChildItem -LiteralPath (Join-Path $dir "_locales") -Recurse -Filter "messages.json" | ForEach-Object FullName)) {
      $text = [IO.File]::ReadAllText($file).Replace("Mister Download Manager", "Throne Download Manager")
      [IO.File]::WriteAllText($file, $text, $encoding)
    }
    $background = Join-Path $dir "background.js"
    $code = [IO.File]::ReadAllText($background)
    $hostLine = 'const HOST = "com.misterdownloadmanager.host";'
    if (-not $code.Contains($hostLine)) { throw "no host declaration in background.js" }
    [IO.File]::WriteAllText($background, $code.Replace($hostLine, "const HOST = `"$firefoxHost`";"), $encoding)
  }
  # Norwegian: Chrome takes only "no", Firefox looks for "nb" (Bokmål) as its users' browsers say.
  if ($kind -eq "firefox" -and (Test-Path (Join-Path $dir "_locales/no"))) {
    Copy-Item (Join-Path $dir "_locales/no") (Join-Path $dir "_locales/nb") -Recurse
  }
  $manifest = switch ($kind) { "firefox" { "manifest.firefox.json" } "safari" { "manifest.safari.json" } default { "manifest.json" } }
  $json = Get-Content (Join-Path $src $manifest) -Raw
  # The first "version" only (the manifest's own).
  $json = ([regex]'("version"\s*:\s*)"[^"]*"').Replace($json, "`${1}`"$version`"", 1)
  [IO.File]::WriteAllText((Join-Path $dir "manifest.json"), $json, (New-Object Text.UTF8Encoding $false))
}
# The Chrome Web Store's copy of the chromium folder. The store signs it with its own key (it
# refuses a manifest that carries "key"; the native host knows both IDs).
$store = Join-Path $out "chrome-store"
if (Test-Path $store) { Remove-Item -LiteralPath $store -Recurse -Force }
Copy-Item (Join-Path $out "chromium") $store -Recurse
$manifest = Get-Content (Join-Path $store "manifest.json") -Raw | ConvertFrom-Json
$manifest.PSObject.Properties.Remove("key")
$json = $manifest | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText((Join-Path $store "manifest.json"), $json, (New-Object Text.UTF8Encoding $false))
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
# The zips have manifest.json at their root. Entries are named with "/" as zip requires
# (Windows PowerShell's CreateFromDirectory writes "\", which Firefox rejects).
foreach ($pair in @(@("chromium", "mdm-chromium.zip"), @("firefox", "mdm-firefox.xpi"), @("chrome-store", "mdm-chrome-store.zip"))) {
  $dir = (Resolve-Path (Join-Path $out $pair[0])).Path
  $zip = Join-Path $out $pair[1]
  if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
  $archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($f in Get-ChildItem -LiteralPath $dir -Recurse -File | Sort-Object FullName) {
      $name = $f.FullName.Substring($dir.Length).TrimStart('\', '/').Replace('\', '/')
      [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $f.FullName, $name)
    }
  } finally { $archive.Dispose() }
}
"built $out (chromium, firefox, safari, chrome-store, mdm-chromium.zip, mdm-firefox.xpi, mdm-chrome-store.zip; version $version)"
