<#
    Instalador de ID PEDIDOS (se ejecuta UNA sola vez).

    Desde la carpeta extraída del zip: doble clic en INSTALAR.cmd
    o desde internet, en PowerShell:
        irm https://raw.githubusercontent.com/bryanmoreta71/idpedidoscmd/main/install.ps1 | iex

    Después de instalar NO hace falta volver a usar el instalador:
      - Escritorio > "ID Pedidos"            -> abre la app
      - Escritorio > "ID Pedidos - Opciones" -> activar / desactivar inicio automático, desinstalar
#>
$ErrorActionPreference = 'Stop'
$Repo    = 'bryanmoreta71/idpedidoscmd'
$Branch  = if ($env:IDPEDIDOS_BRANCH) { $env:IDPEDIDOS_BRANCH } else { 'main' }
$Destino = Join-Path $env:LOCALAPPDATA 'IdPedidos'
$Archivos = @('IdPedidos.ps1', 'inicio.ps1', 'uninstall.ps1', 'README.md')

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
Remove-Item -Path (Join-Path $Destino 'IdPedidos.cmd') -ErrorAction SilentlyContinue   # de versiones anteriores

# Archivos de control dentro de la carpeta de la app
$cmdPs = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0'
$controles = [ordered]@{
    'ACTIVAR inicio automatico.cmd'    = "@echo off`r`n$($cmdPs)inicio.ps1`" -Activar`r`ntimeout /t 4 >nul`r`n"
    'DESACTIVAR inicio automatico.cmd' = "@echo off`r`n$($cmdPs)inicio.ps1`" -Desactivar`r`ntimeout /t 4 >nul`r`n"
    'DESINSTALAR.cmd'                  = "@echo off`r`n$($cmdPs)uninstall.ps1`"`r`npause`r`n"
}
foreach ($k in $controles.Keys) { Set-Content -Path (Join-Path $Destino $k) -Value $controles[$k] -Encoding ASCII -NoNewline }

# Accesos directos para ABRIR (consola clásica: clic derecho = pegar)
$shell   = New-Object -ComObject WScript.Shell
$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
$argApp  = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Destino 'IdPedidos.ps1') + '"'
$icono   = Join-Path $env:SystemRoot 'System32\shell32.dll,165'
function New-Acceso($ruta, $destino, $argumentos, $icon) {
    $lnk = $shell.CreateShortcut($ruta)
    $lnk.TargetPath = $destino
    if ($argumentos) { $lnk.Arguments = $argumentos }
    $lnk.WorkingDirectory = $Destino
    if ($icon) { $lnk.IconLocation = $icon }
    $lnk.Save()
}
$escritorio = [Environment]::GetFolderPath('Desktop')
New-Acceso (Join-Path $Destino 'ABRIR ID Pedidos.lnk')              $conhost $argApp $icono
New-Acceso (Join-Path $escritorio 'ID Pedidos.lnk')                 $conhost $argApp $icono
New-Acceso (Join-Path $escritorio 'ID Pedidos - Opciones.lnk')      $Destino $null (Join-Path $env:SystemRoot 'System32\shell32.dll,316')

# Menú Inicio > ID Pedidos
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'ID Pedidos'
New-Item -ItemType Directory -Force -Path $menu | Out-Null
New-Acceso (Join-Path $menu 'ID Pedidos.lnk') $conhost $argApp $icono
foreach ($k in $controles.Keys) { New-Acceso (Join-Path $menu ($k -replace '\.cmd$', '.lnk')) (Join-Path $Destino $k) $null $null }

# Inicio automático activado por defecto
& (Join-Path $Destino 'inicio.ps1') -Activar | Out-Null

# Consola clásica con QuickEdit (clic derecho pega lo copiado)
New-Item -Path 'HKCU:\Console' -Force | Out-Null
Set-ItemProperty -Path 'HKCU:\Console' -Name 'QuickEdit' -Value 1 -Type DWord

Write-Host ''
Write-Host ' INSTALADO. Ya no necesitas volver a usar el instalador.' -ForegroundColor Green
Write-Host '   Abrir la app:        Escritorio > "ID Pedidos"'
Write-Host '   Inicio automático:   Escritorio > "ID Pedidos - Opciones" > ACTIVAR / DESACTIVAR'
Write-Host ''
# Abre la app (si ya estaba abierta, solo la trae al frente)
Start-Process -FilePath $conhost -ArgumentList $argApp -WorkingDirectory $Destino
Start-Sleep -Seconds 2
