<#
    Instalador de ID PEDIDOS

    Opción A (desde internet), en PowerShell:
        irm https://raw.githubusercontent.com/bryanmoreta71/idpedidoscmd/main/install.ps1 | iex

    Opción B (desde la carpeta descargada), en PowerShell:
        powershell -ExecutionPolicy Bypass -File .\install.ps1
#>
$ErrorActionPreference = 'Stop'
$Repo    = 'bryanmoreta71/idpedidoscmd'
$Branch  = if ($env:IDPEDIDOS_BRANCH) { $env:IDPEDIDOS_BRANCH } else { 'main' }
$Destino = Join-Path $env:LOCALAPPDATA 'IdPedidos'
$Archivos = @('IdPedidos.ps1', 'IdPedidos.cmd')

Write-Host ''
Write-Host ' Instalando ID PEDIDOS en' $Destino -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $Destino | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Destino 'registros') | Out-Null

$origenLocal = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'IdPedidos.ps1'))) { $PSScriptRoot } else { $null }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
foreach ($a in $Archivos) {
    $dst = Join-Path $Destino $a
    if ($origenLocal) {
        Copy-Item -Path (Join-Path $origenLocal $a) -Destination $dst -Force
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/$Repo/$Branch/$a" -OutFile $dst
    }
    Unblock-File -Path $dst -ErrorAction SilentlyContinue
}

# Accesos directos: Escritorio + Inicio automático de Windows.
# Se abre con conhost.exe para usar la consola clásica (clic derecho = pegar).
$shell  = New-Object -ComObject WScript.Shell
$target = Join-Path $env:SystemRoot 'System32\conhost.exe'
$argumentos   = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Destino 'IdPedidos.ps1') + '"'
$icono  = Join-Path $env:SystemRoot 'System32\shell32.dll,165'
foreach ($carpeta in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Startup'))) {
    $lnk = $shell.CreateShortcut((Join-Path $carpeta 'ID Pedidos.lnk'))
    $lnk.TargetPath       = $target
    $lnk.Arguments        = $argumentos
    $lnk.WorkingDirectory = $Destino
    $lnk.IconLocation     = $icono
    $lnk.Description      = 'Registro de IDs de pedidos despachados'
    $lnk.Save()
}

# Consola clásica con QuickEdit (clic derecho pega lo copiado)
New-Item -Path 'HKCU:\Console' -Force | Out-Null
Set-ItemProperty -Path 'HKCU:\Console' -Name 'QuickEdit' -Value 1 -Type DWord

Write-Host ' Listo. Se abrirá solo al iniciar Windows y hay un acceso directo en el Escritorio.' -ForegroundColor Green
Write-Host ' Dentro de la app escribe  I  para configurar la impresora térmica Bluetooth.' -ForegroundColor Green
Write-Host ''
Start-Process -FilePath $target -ArgumentList $argumentos -WorkingDirectory $Destino
