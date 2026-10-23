# Quita los accesos directos de ID PEDIDOS. Los registros se conservan en %LOCALAPPDATA%\IdPedidos\registros
$escritorio = [Environment]::GetFolderPath('Desktop')
Remove-Item -Path (Join-Path ([Environment]::GetFolderPath('Startup')) 'ID Pedidos.lnk') -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $escritorio 'ID Pedidos.lnk') -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $escritorio 'ID Pedidos - Opciones.lnk') -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path ([Environment]::GetFolderPath('Programs')) 'ID Pedidos') -Recurse -ErrorAction SilentlyContinue
Write-Host 'ID PEDIDOS desinstalado (accesos directos e inicio automático eliminados).'
Write-Host 'Tus registros siguen en' (Join-Path $env:LOCALAPPDATA 'IdPedidos\registros')
