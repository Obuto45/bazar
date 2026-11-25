# Yeni sürüm yayınlar: sürümü yazar, exe'yi dışa aktarır, zip'ler, GitHub Release açar.
# Oyunu açan herkes bu sürümü otomatik indirir (updater.gd).
# Kullanım:  .\release.ps1 0.2 "Değişiklik notları"
# Godot başka yerdeyse önce:  $env:GODOT = "C:\...\Godot_..._console.exe"
param(
    [Parameter(Mandatory)][string]$Version,
    [string]$Notes = "Yeni sürüm"
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$Version = $Version.TrimStart("v")
$tag = "v$Version"

$godot = $env:GODOT
if (-not $godot) {
    $godot = (Get-Command Godot*_console.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
}
if (-not $godot) { throw "Godot bulunamadı. `$env:GODOT ile console exe yolunu ver." }
if (git status --porcelain) { throw "Commit edilmemiş değişiklik var. Önce commit et." }
if (git tag -l $tag) { throw "$tag zaten var. Daha büyük bir sürüm numarası ver." }

# 1) Sürümü yaz (updater bu sayıyı Release etiketiyle karşılaştırır)
$p = Get-Content project.godot -Raw -Encoding utf8
$p = $p -replace 'config/version="[^"]*"', "config/version=`"$Version`""
[IO.File]::WriteAllText("$PSScriptRoot\project.godot", $p)

# 2) Dışa aktar
Remove-Item build -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory build | Out-Null
& $godot --headless --path . --export-release "Windows Desktop" build/Bazar.exe
if (-not (Test-Path build/Bazar.exe)) { throw "Export başarısız (export şablonları kurulu mu?)." }
Copy-Item steam_appid.txt build/

# 3) Zip: dosya adı _Windows.zip ile bitmeli
$zip = "build/Bazar_${tag}_Windows.zip"
Compress-Archive -Path build/Bazar.exe, build/*.dll, build/steam_appid.txt -DestinationPath $zip

# 4) Commit, etiket, Release
git add project.godot
git commit -m "Sürüm $tag"
git push
gh release create $tag $zip --title $tag --notes $Notes
Write-Host "Yayınlandı: https://github.com/Obuto45/bazar/releases/tag/$tag"
