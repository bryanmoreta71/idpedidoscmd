<#
    Activa o desactiva que ID PEDIDOS se abra solo al encender la computadora.
        inicio.ps1 -Activar
        inicio.ps1 -Desactivar
#>
param([switch]$Activar, [switch]$Desactivar)

$AppDir  = $PSScriptRoot
$Startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'ID Pedidos.lnk'

if ($Activar) {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($Startup)
    $lnk.TargetPath       = Join-Path $env:SystemRoot 'System32\conhost.exe'
    $lnk.Arguments        = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $AppDir 'IdPedidos.ps1') + '"'
    $lnk.WorkingDirectory = $AppDir
    $lnk.IconLocation     = Join-Path $env:SystemRoot 'System32\shell32.dll,165'
    $lnk.Save()
    Write-Host ''
    Write-Host ' INICIO AUTOMÁTICO ACTIVADO' -ForegroundColor Green
    Write-Host ' ID PEDIDOS se abrirá solo cada vez que enciendas la computadora.'
} elseif ($Desactivar) {
    Remove-Item -Path $Startup -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host ' INICIO AUTOMÁTICO DESACTIVADO' -ForegroundColor Yellow
    Write-Host ' ID PEDIDOS ya no se abrirá solo. Ábrelo con el acceso "ID Pedidos" del Escritorio.'
} else {
    $estado = $(if (Test-Path $Startup) { 'ACTIVADO' } else { 'DESACTIVADO' })
    Write-Host " Inicio automático: $estado"
}
