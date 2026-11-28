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

# 2) Dışa aktar: sürüme özel klasöre (açık duran eski exe kilitli olabilir)
$out = "build/$tag"
Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $out -Force | Out-Null
$ErrorActionPreference = "Continue" # Godot uyarıları stderr'e yazar: PS 5.1'de hata sayılmasın
& $godot --headless --path . --export-release "Windows Desktop" "$out/Bazar.exe" 2>&1 | Out-Host
$ErrorActionPreference = "Stop"
if (-not (Test-Path "$out/Bazar.exe")) { throw "Export başarısız (export şablonları kurulu mu?)." }
Copy-Item steam_appid.txt $out/

# 3) Zip: dosya adı _Windows.zip ile bitmeli (.pck ayrıysa onu da ekle)
$zip = "build/Bazar_${tag}_Windows.zip"
$files = @("$out/Bazar.exe", "$out/steam_appid.txt") + @(Get-ChildItem "$out/*.dll", "$out/*.pck" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
Compress-Archive -Path $files -DestinationPath $zip -Force

# 4) Commit, etiket, Release. git uyarıları stderr'e yazar: PS 5.1'de hata sayılmasın, çıkış koduna bak.
$ErrorActionPreference = "Continue"
function Invoke-Step { & $args[0] $args[1..($args.Count - 1)] 2>&1 | Out-Host; if ($LASTEXITCODE) { throw "$($args -join ' ') başarısız." } }
if (git status --porcelain project.godot) {
    Invoke-Step git add project.godot
    Invoke-Step git commit -m "Sürüm $tag"
}
Invoke-Step git push
Invoke-Step gh release create $tag $zip --title $tag --notes $Notes
Write-Host "Yayınlandı: https://github.com/Obuto45/bazar/releases/tag/$tag"
