$modRoot = "D:\kcd2multiplayer\mod"
$modData = "$modRoot\Data"
$pakFile = "$modData\kcd_multiplayer.pak"
$zipFile = "$modData\kcd_multiplayer.zip"
$scriptsDir = "$modData\Scripts"
$srcDir = "$modRoot\src"

# Copy source scripts to pak structure
Remove-Item $scriptsDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path "$scriptsDir\Startup" -Force | Out-Null
New-Item -ItemType Directory -Path "$scriptsDir\mods" -Force | Out-Null

Copy-Item "$srcDir\kcd2mp_startup.lua" "$scriptsDir\Startup\kcd2mp_startup.lua"
Copy-Item "$srcDir\kcd_multiplayer.lua" "$scriptsDir\mods\kcd_multiplayer.lua"

# Build pak (zip renamed to .pak)
if (Test-Path $pakFile) { [System.IO.File]::Delete($pakFile) }
if (Test-Path $zipFile) { [System.IO.File]::Delete($zipFile) }

Push-Location $modData
Compress-Archive -Path "Scripts" -DestinationPath $zipFile -Force
Pop-Location

Copy-Item $zipFile $pakFile -Force
Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
Remove-Item $scriptsDir -Recurse -Force

Write-Host "PAK built: $pakFile"
