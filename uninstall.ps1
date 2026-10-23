# Quita los accesos directos de ID PEDIDOS. Los registros se conservan en %LOCALAPPDATA%\IdPedidos\registros
foreach ($carpeta in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Startup'))) {
    Remove-Item -Path (Join-Path $carpeta 'ID Pedidos.lnk') -ErrorAction SilentlyContinue
}
Write-Host 'Accesos directos eliminados. Tus registros siguen en' (Join-Path $env:LOCALAPPDATA 'IdPedidos\registros')
