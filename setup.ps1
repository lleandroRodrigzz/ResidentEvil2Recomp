# Instalador de um comando para Windows.
# Uso: powershell -ExecutionPolicy Bypass -File setup.ps1 [-Leon "CD1.cue"] [-Claire "CD2.cue"] [-SemAot]
#   -SemAot  pula a pre-compilacao dos trechos carregados do disco (instala mais rapido
#            e usa menos espaco, mas o jogo engasga um pouco na primeira vez que cada trecho aparece)
param([string]$Leon, [string]$Claire, [switch]$SemAot)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

Write-Host "=== Resident Evil 2 Recompiled - instalacao ===" -ForegroundColor Cyan

# Git (o Git for Windows tambem fornece o bash usado pelos scripts)
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Write-Host "Git nao encontrado. Instale com: winget install Git.Git  (e reabra o PowerShell)" -ForegroundColor Red
    exit 1
}
$bash = Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe'
if (-not (Test-Path $bash)) { $bash = 'C:\Program Files\Git\bin\bash.exe' }
if (-not (Test-Path $bash)) {
    Write-Host "bash.exe do Git for Windows nao encontrado." -ForegroundColor Red
    exit 1
}

# Python
$pyOk = $false
foreach ($c in 'python', 'py') {
    try { & $c -c "import sys; sys.exit(sys.version_info < (3, 9))" 2>$null; if ($LASTEXITCODE -eq 0) { $pyOk = $true; break } } catch {}
}
if (-not $pyOk) {
    Write-Host "Python 3.9+ nao encontrado. Instale com: winget install Python.Python.3.12  (e reabra o PowerShell)" -ForegroundColor Red
    exit 1
}

# Discos: pede os dois .cue se nao foram informados
function Select-Cue([string]$titulo) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = $titulo
    $dlg.Filter = 'Imagem de disco (*.cue)|*.cue'
    if ($dlg.ShowDialog() -ne 'OK') { Write-Host 'Cancelado.'; exit 1 }
    return $dlg.FileName
}
if (-not $Leon)   { $Leon   = Select-Cue 'Selecione o .cue do CD1 (Leon) do Resident Evil 2' }
if (-not $Claire) { $Claire = Select-Cue 'Selecione o .cue do CD2 (Claire) do Resident Evil 2' }
foreach ($d in $Leon, $Claire) {
    if (-not (Test-Path $d)) { Write-Host "Arquivo nao encontrado: $d" -ForegroundColor Red; exit 1 }
}

Write-Host "CD1 (Leon):   $Leon"
Write-Host "CD2 (Claire): $Claire"
if ($SemAot) {
    $aotArg = ' --sem-aot'
    Write-Host "Pre-compilacao dos trechos do disco: DESLIGADA (-SemAot)."
    Write-Host "Isso pode levar de 30 a 80 minutos. Nao feche esta janela." -ForegroundColor Yellow
} else {
    $aotArg = ''
    Write-Host "Pre-compilacao dos trechos do disco: LIGADA (para desligar, rode de novo com -SemAot)."
    Write-Host "Isso pode levar de 40 a 90 minutos. Nao feche esta janela." -ForegroundColor Yellow
}

$root = $PSScriptRoot -replace '\','/'
& $bash -lc "cd '$root' && bash scripts/setup.sh '$($Leon -replace '\','/')' '$($Claire -replace '\','/')'$aotArg"
if ($LASTEXITCODE -ne 0) { Write-Host "A instalacao falhou. Veja as mensagens acima." -ForegroundColor Red; exit $LASTEXITCODE }

$dir = Join-Path $PSScriptRoot 'build-release'
$desk = [Environment]::GetFolderPath('Desktop')
$ws = New-Object -ComObject WScript.Shell
foreach ($p in @(@('Leon', 'ResidentEvil2_Leon.exe'), @('Claire', 'ResidentEvil2_Claire.exe'))) {
    $lnk = $ws.CreateShortcut((Join-Path $desk "Resident Evil 2 - $($p[0]).lnk"))
    $lnk.TargetPath = Join-Path $dir $p[1]
    $lnk.WorkingDirectory = $dir
    $lnk.Save()
}
Write-Host "`nPronto! Jogos em: $dir" -ForegroundColor Green
Write-Host "Atalhos 'Resident Evil 2 - Leon' e 'Resident Evil 2 - Claire' criados na Area de Trabalho."
