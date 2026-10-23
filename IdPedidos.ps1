#Requires -Version 5.1
<#
    ID PEDIDOS - Registro de pedidos despachados (Uber / PedidosYa / Rappi)

    Uso rápido:
      - Clic derecho en la ventana = pega el ID copiado (o ENTER vacío usa el portapapeles).
      - ENTER -> elegir 1 Uber, 2 PedidosYa, 3 Rappi.
      - Se guarda con la hora y se imprime en la impresora térmica.
#>

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Rutas y configuración
# --------------------------------------------------------------------------
$AppDir      = $PSScriptRoot
$DataDir     = Join-Path $AppDir 'registros'
$ConfigPath  = Join-Path $AppDir 'config.json'
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

$Plataformas = [ordered]@{
    '1' = @{ Nombre = 'Uber';      Rgb = '0;200;0';   Color = 'Green'      }
    '2' = @{ Nombre = 'PedidosYa'; Rgb = '235;30;45'; Color = 'Red'        }
    '3' = @{ Nombre = 'Rappi';     Rgb = '255;140;0'; Color = 'DarkYellow' }
}

function Get-Config {
    $default = [pscustomobject]@{ Modo = 'ninguna'; Impresora = ''; Puerto = ''; Baudios = 9600; Bluetooth = ''; BluetoothNombre = ''; Canal = 0; Formato = 'escpos'; Negocio = ''; Ancho = 32 }
    if (Test-Path $ConfigPath) {
        try {
            $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $default.PSObject.Properties) {
                if (-not $cfg.PSObject.Properties[$p.Name]) { $cfg | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
            }
            return $cfg
        } catch { }
    }
    return $default
}

function Save-Config($cfg) {
    $cfg | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

# --------------------------------------------------------------------------
# Consola: colores reales (VT) y "clic derecho = pegar" (QuickEdit)
# --------------------------------------------------------------------------
Add-Type -Namespace IdPedidos -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr h, out uint mode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr h, uint mode);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
'@

# Una sola ventana: si la app ya está abierta, se trae al frente y esta se cierra
$TituloVentana = 'ID PEDIDOS - Despachos'
$mutexCreado = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\IdPedidosApp', [ref]$mutexCreado)
if (-not $mutexCreado) {
    try {
        $h = [IdPedidos.Native]::FindWindow($null, $TituloVentana)
        if ($h -ne [IntPtr]::Zero) {
            [void][IdPedidos.Native]::ShowWindow($h, 9)   # SW_RESTORE
            [void][IdPedidos.Native]::SetForegroundWindow($h)
        }
    } catch { }
    exit
}

$script:Vt = $false
try {
    $out = [IdPedidos.Native]::GetStdHandle(-11)
    $m = 0
    if ([IdPedidos.Native]::GetConsoleMode($out, [ref]$m)) {
        $script:Vt = [IdPedidos.Native]::SetConsoleMode($out, $m -bor 0x0004)   # ENABLE_VIRTUAL_TERMINAL_PROCESSING
    }
    $in = [IdPedidos.Native]::GetStdHandle(-10)
    if ([IdPedidos.Native]::GetConsoleMode($in, [ref]$m)) {
        # ENABLE_QUICK_EDIT_MODE (0x40) + ENABLE_EXTENDED_FLAGS (0x80): clic derecho pega
        [void][IdPedidos.Native]::SetConsoleMode($in, ($m -bor 0x40 -bor 0x80))
    }
} catch { }

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
try { $Host.UI.RawUI.WindowTitle = $TituloVentana } catch { }

$Esc = [char]27

function Write-Plat([string]$texto, $plat, [switch]$NoNewline) {
    if ($script:Vt) {
        Write-Host "$Esc[1;38;2;$($plat.Rgb)m$texto$Esc[0m" -NoNewline:$NoNewline
    } else {
        Write-Host $texto -ForegroundColor $plat.Color -NoNewline:$NoNewline
    }
}

function Get-PlatByName([string]$nombre) {
    foreach ($p in $Plataformas.Values) { if ($p.Nombre -eq $nombre) { return $p } }
    return @{ Nombre = $nombre; Rgb = '200;200;200'; Color = 'Gray' }
}

# --------------------------------------------------------------------------
# Registros (un CSV por día: registros\AAAA-MM-DD.csv)
# --------------------------------------------------------------------------
function Get-DayFile([datetime]$fecha) { Join-Path $DataDir ($fecha.ToString('yyyy-MM-dd') + '.csv') }

function Read-Day([string]$archivo) {
    if (-not (Test-Path $archivo)) { return @() }
    return @(Import-Csv -Path $archivo -Encoding UTF8)
}

function Add-Registro($reg) {
    $archivo = Get-DayFile (Get-Date)
    $reg | Export-Csv -Path $archivo -Append -NoTypeInformation -Encoding UTF8
}

function Remove-UltimoRegistro {
    $archivo = Get-DayFile (Get-Date)
    $regs = Read-Day $archivo
    if ($regs.Count -eq 0) { return $null }
    $ultimo = $regs[-1]
    if ($regs.Count -eq 1) { Remove-Item $archivo }
    else { $regs[0..($regs.Count - 2)] | Export-Csv -Path $archivo -NoTypeInformation -Encoding UTF8 }
    return $ultimo
}

# Índice de TODOS los IDs ya despachados (todos los días) para detectar repetidos
$script:Indice = @{}
function Build-Indice {
    $script:Indice = @{}
    foreach ($f in Get-ChildItem -Path $DataDir -Filter '*.csv' | Sort-Object Name) {
        foreach ($r in Read-Day $f.FullName) {
            if ($r.ID) { $script:Indice[$r.ID.ToUpperInvariant()] = $r }
        }
    }
}

function Normalize-Id([string]$texto) {
    if (-not $texto) { return '' }
    $linea = ($texto -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if (-not $linea) { return '' }
    return ($linea -replace '\s', '').Trim()
}

# --------------------------------------------------------------------------
# Impresión ESC/POS (impresora térmica Bluetooth)
#   Modo 'bt'     : Bluetooth directo (SPP/RFCOMM), p. ej. Sunmi V2 Pro de PedidosYa
#   Modo 'windows': impresora instalada en Windows (envío RAW)
#   Modo 'com'    : puerto COM serie de Bluetooth (SPP)
# --------------------------------------------------------------------------
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class IdPedidosRawPrinter {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public class DOCINFO {
        [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
    }
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool OpenPrinter(string name, out IntPtr h, IntPtr def);
    [DllImport("winspool.drv", SetLastError = true)] static extern bool ClosePrinter(IntPtr h);
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool StartDocPrinter(IntPtr h, int level, [In] DOCINFO di);
    [DllImport("winspool.drv", SetLastError = true)] static extern bool EndDocPrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError = true)] static extern bool StartPagePrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError = true)] static extern bool EndPagePrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError = true)] static extern bool WritePrinter(IntPtr h, byte[] buf, int count, out int written);

    public static void Send(string printer, byte[] data) {
        IntPtr h;
        if (!OpenPrinter(printer, out h, IntPtr.Zero)) throw new Exception("No se pudo abrir la impresora '" + printer + "' (error " + Marshal.GetLastWin32Error() + ")");
        try {
            DOCINFO di = new DOCINFO(); di.pDocName = "ID Pedido"; di.pDataType = "RAW";
            if (!StartDocPrinter(h, 1, di)) throw new Exception("StartDocPrinter fallo (error " + Marshal.GetLastWin32Error() + ")");
            try {
                StartPagePrinter(h);
                int w;
                if (!WritePrinter(h, data, data.Length, out w)) throw new Exception("WritePrinter fallo (error " + Marshal.GetLastWin32Error() + ")");
                EndPagePrinter(h);
            } finally { EndDocPrinter(h); }
        } finally { ClosePrinter(h); }
    }
}
'@

# Conexión Bluetooth RFCOMM sin puerto COM (Winsock AF_BTH), perfil serie SPP
Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
public class IdPedidosBtEndPoint : EndPoint {
    const int AF_BTH = 32;
    public static readonly Guid SPP = new Guid("00001101-0000-1000-8000-00805F9B34FB");
    public ulong Address;
    public int Channel;   // 0 = buscar el servicio serie (SPP) automáticamente; 1-30 = canal RFCOMM fijo
    public IdPedidosBtEndPoint(ulong address, int channel) { Address = address; Channel = channel; }
    public override AddressFamily AddressFamily { get { return (AddressFamily)AF_BTH; } }
    public override SocketAddress Serialize() {
        // SOCKADDR_BTH (empaquetado): family(2) + btAddr(8) + serviceClassId(16) + port(4)
        SocketAddress sa = new SocketAddress((AddressFamily)AF_BTH, 30);
        byte[] a = BitConverter.GetBytes(Address);
        for (int i = 0; i < 8; i++) sa[2 + i] = a[i];
        if (Channel <= 0) {
            byte[] g = SPP.ToByteArray();
            for (int i = 0; i < 16; i++) sa[10 + i] = g[i];
        } else {
            byte[] c = BitConverter.GetBytes((uint)Channel);
            for (int i = 0; i < 4; i++) sa[26 + i] = c[i];
        }
        return sa;
    }
    public override EndPoint Create(SocketAddress sa) { return this; }
}
public static class IdPedidosBluetooth {
    static string Explicar(SocketException e) {
        switch (e.ErrorCode) {
            case 10050: return "el Bluetooth de la PC esta apagado o no hay adaptador";
            case 10051: case 10065: return "no se encuentra el aparato (encendido, Bluetooth activo y cerca?)";
            case 10060: return "el aparato no contesto a tiempo (encendido y cerca?)";
            case 10061: return "el aparato rechazo la conexion (servicio de impresion no disponible)";
            case 10064: return "el aparato no esta disponible (apagado, fuera de alcance o no emparejado)";
            case 10108: return "el aparato no ofrece el servicio de puerto serie en ese canal";
            case 10013: return "permiso denegado (vuelve a emparejar el aparato)";
            default: return e.Message;
        }
    }
    // Conexión síncrona en un hilo aparte para poder cortar por tiempo
    static Socket Connect(string mac, int channel, int timeoutMs) {
        ulong addr = Convert.ToUInt64(mac.Replace(":", "").Replace("-", ""), 16);
        Socket s = new Socket((AddressFamily)32, SocketType.Stream, (ProtocolType)3);
        Exception error = null;
        System.Threading.Thread t = new System.Threading.Thread(delegate() {
            try { s.Connect(new IdPedidosBtEndPoint(addr, channel)); } catch (Exception ex) { error = ex; }
        });
        t.IsBackground = true;
        t.Start();
        if (!t.Join(timeoutMs)) { try { s.Close(); } catch { } throw new Exception("el aparato no contesto en " + (timeoutMs / 1000) + " s (encendido y cerca?)"); }
        if (error != null) {
            try { s.Close(); } catch { }
            SocketException se = error as SocketException;
            if (se != null) throw new Exception(Explicar(se) + " [codigo " + se.ErrorCode + "]");
            throw new Exception(error.Message);
        }
        return s;
    }
    public static void Send(string mac, int channel, byte[] data, int timeoutMs) {
        using (Socket s = Connect(mac, channel, timeoutMs)) {
            int enviado = 0;
            while (enviado < data.Length) {
                int n = Math.Min(256, data.Length - enviado);   // en trozos pequeños, como lo hacen los celulares
                enviado += s.Send(data, enviado, n, SocketFlags.None);
                System.Threading.Thread.Sleep(30);
            }
            System.Threading.Thread.Sleep(2500);               // dar tiempo a que el aparato imprima antes de cortar
            try { s.Shutdown(SocketShutdown.Both); } catch { }
        }
    }
    // Solo conecta y desconecta, sin imprimir nada
    public static void Test(string mac, int channel, int timeoutMs) {
        using (Socket s = Connect(mac, channel, timeoutMs)) { try { s.Shutdown(SocketShutdown.Both); } catch { } }
    }
}
'@

# Dispositivos Bluetooth emparejados con esta PC: MAC + nombre
function Get-BluetoothEmparejados {
    $lista = @()
    $raiz = 'HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices'
    if (Test-Path $raiz) {
        foreach ($k in Get-ChildItem $raiz -ErrorAction SilentlyContinue) {
            $nombre = ''
            try {
                $bytes = (Get-ItemProperty $k.PSPath -Name Name -ErrorAction Stop).Name
                $nombre = ([Text.Encoding]::UTF8.GetString($bytes)).Trim([char]0)
            } catch { }
            $lista += [pscustomobject]@{ Mac = $k.PSChildName.ToUpper(); Nombre = $(if ($nombre) { $nombre } else { '(sin nombre)' }) }
        }
    }
    if ($lista.Count -eq 0) {
        try {
            foreach ($d in Get-PnpDevice -Class Bluetooth -ErrorAction Stop) {
                if ($d.InstanceId -match 'DEV_([0-9A-F]{12})') { $lista += [pscustomobject]@{ Mac = $Matches[1]; Nombre = $d.FriendlyName } }
            }
        } catch { }
    }
    return @($lista | Sort-Object Mac -Unique)
}

$LogPath = Join-Path $AppDir 'diagnostico.txt'
function Write-Log([string]$texto) {
    try { Add-Content -Path $LogPath -Encoding UTF8 -Value ('{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $texto) } catch { }
}

# Prueba varias formas de conectar con la impresora Bluetooth y guarda la que funcione
function Start-Diagnostico {
    $cfg = Get-Config
    Write-Host ''
    Write-Host ' DIAGNÓSTICO DE IMPRESORA' -ForegroundColor Cyan
    Write-Log '===== Diagnóstico ====='
    $linea = { param($t, $c) Write-Host " $t" -ForegroundColor $c; Write-Log $t }
    & $linea ("Windows: {0}  PowerShell: {1}" -f [Environment]::OSVersion.Version, $PSVersionTable.PSVersion) Gray
    & $linea ("Configuración: modo={0} disp={1} [{2}] canal={3} puerto={4} impresora={5}" -f $cfg.Modo, $cfg.BluetoothNombre, $cfg.Bluetooth, $cfg.Canal, $cfg.Puerto, $cfg.Impresora) Gray
    try {
        foreach ($r in Get-PnpDevice -Class Bluetooth -ErrorAction Stop | Where-Object { $_.InstanceId -notmatch 'DEV_' } | Select-Object -First 3) {
            & $linea ("Adaptador Bluetooth: {0} ({1})" -f $r.FriendlyName, $r.Status) Gray
        }
    } catch { }
    $bts = Get-BluetoothEmparejados
    & $linea ("Dispositivos emparejados: {0}" -f (($bts | ForEach-Object { "$($_.Nombre) [$($_.Mac)]" }) -join ', ')) Gray
    $puertos = @([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object -Unique)
    & $linea ("Puertos COM: {0}" -f $(if ($puertos) { $puertos -join ', ' } else { 'ninguno' })) Gray

    if ($cfg.Modo -ne 'bt' -or -not $cfg.Bluetooth) {
        & $linea 'La impresora no está en modo Bluetooth directo. Escribe I y elige 1.' Yellow
        return
    }
    $prueba = [pscustomobject]@{ Fecha = (Get-Date).ToString('dd/MM/yyyy'); Hora = (Get-Date).ToString('HH:mm:ss'); ID = 'PRUEBA-123'; Plataforma = 'PedidosYa' }
    $canales = @(0) + (1..12)
    foreach ($c in $canales) {
        $desc = $(if ($c -eq 0) { 'servicio serie (SPP)' } else { "canal $c" })
        Write-Host (" Probando {0}... " -f $desc) -NoNewline
        try {
            [IdPedidosBluetooth]::Test($cfg.Bluetooth, $c, 12000)
            Write-Host 'CONECTÓ' -ForegroundColor Green
            Write-Log "$desc : conectó"
            # Conectó: probar los dos formatos de datos
            foreach ($f in @('escpos', 'texto')) {
                $cfg.Formato = $f
                $nombreF = $(if ($f -eq 'escpos') { 'comandos de impresora (ESC/POS)' } else { 'texto simple' })
                Write-Host "   Enviando ticket de prueba en $nombreF..." -NoNewline
                try { [IdPedidosBluetooth]::Send($cfg.Bluetooth, $c, (New-Ticket $prueba $cfg), 12000); Write-Host ' enviado' -ForegroundColor Green }
                catch { Write-Host " $($_.Exception.Message)" -ForegroundColor Yellow; Write-Log "$desc / $f : $($_.Exception.Message)"; continue }
                if ((Read-Host '   ¿Salió el ticket impreso en el aparato? (S/N)') -match '^[sS]') {
                    $cfg.Canal = $c; Save-Config $cfg
                    & $linea "Funciona con $desc en $nombreF. Configuración guardada." Green
                    return
                }
                Write-Log "$desc / $f : enviado pero NO imprimió"
            }
        } catch {
            Write-Host $_.Exception.Message -ForegroundColor Yellow
            Write-Log "$desc : $($_.Exception.Message)"
            if ($c -eq 0 -and $_.Exception.Message -match 'codigo 1005[01]') { break }   # Bluetooth de la PC apagado: no tiene caso seguir
        }
    }
    & $linea 'No se logró imprimir. Envía el archivo diagnostico.txt (se abrirá ahora).' Yellow
    try { Start-Process notepad.exe $LogPath } catch { }
}

# Comprueba (sin imprimir) que la impresora responde; el resultado se muestra en el encabezado
$script:EstadoImpresora = ''
function Test-Impresora {
    $cfg = Get-Config
    switch ($cfg.Modo) {
        'bt' {
            Write-Host (' Conectando con {0}...' -f $cfg.BluetoothNombre) -ForegroundColor DarkGray
            try { [IdPedidosBluetooth]::Test($cfg.Bluetooth, [int]$cfg.Canal, 10000); $script:EstadoImpresora = "OK|$($cfg.BluetoothNombre): conectada" }
            catch {
                Write-Log "Prueba de conexión: $($_.Exception.Message)"
                $script:EstadoImpresora = "ERR|$($cfg.BluetoothNombre): $($_.Exception.Message)  -> escribe D para diagnóstico"
            }
        }
        'windows' { $script:EstadoImpresora = "OK|$($cfg.Impresora)" }
        'com'     { $script:EstadoImpresora = "OK|$($cfg.Puerto)" }
        default   { $script:EstadoImpresora = 'ERR|Sin impresora (escribe I para configurarla)' }
    }
}

function Remove-Acentos([string]$s) {
    $n = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($c in $n.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
    }
    return ($sb.ToString() -replace '[^\x20-\x7E]', '')
}

# Abreviatura impresa en el ticket
$Abreviaturas = @{ 'Uber' = 'UBER'; 'PedidosYa' = 'P YA'; 'Rappi' = 'RAPPI' }

# Recuadro en texto ASCII (compatible con cualquier térmica):
#   +-------+--------------+-------+
#   | P YA  | 4815162342   | 14:32 |
#   +-------+--------------+-------+
#   Despachado 23/10/2026 14:32:05
function Format-Recuadro($reg, [int]$ancho) {
    $plat = $Abreviaturas[$reg.Plataforma]
    if (-not $plat) { $plat = $reg.Plataforma.ToUpper() }
    $plat = Remove-Acentos $plat
    $hora = ([string]$reg.Hora).Substring(0, [Math]::Min(5, ([string]$reg.Hora).Length))
    $id   = Remove-Acentos ([string]$reg.ID)

    $wP = [Math]::Max(5, $plat.Length)
    $wH = 5
    $wI = [Math]::Max(6, $ancho - $wP - $wH - 10)

    $sep = '+' + ('-' * ($wP + 2)) + '+' + ('-' * ($wI + 2)) + '+' + ('-' * ($wH + 2)) + '+'
    $lineas = @($sep)
    $trozos = @()
    for ($i = 0; $i -lt $id.Length; $i += $wI) { $trozos += $id.Substring($i, [Math]::Min($wI, $id.Length - $i)) }
    if ($trozos.Count -eq 0) { $trozos = @('') }
    for ($i = 0; $i -lt $trozos.Count; $i++) {
        $p = $(if ($i -eq 0) { $plat } else { '' })
        $h = $(if ($i -eq 0) { $hora } else { '' })
        $lineas += '| ' + $p.PadRight($wP) + ' | ' + $trozos[$i].PadRight($wI) + ' | ' + $h.PadRight($wH) + ' |'
    }
    $lineas += $sep
    $lineas += ('Despachado {0} {1}' -f $reg.Fecha, $reg.Hora)
    return $lineas
}

function New-Ticket($reg, $cfg) {
    $b = New-Object System.Collections.Generic.List[byte]
    $add = { param([byte[]]$x) $b.AddRange($x) }
    $txt = { param([string]$s) $b.AddRange([Text.Encoding]::ASCII.GetBytes((Remove-Acentos $s))); $b.Add(0x0A) }
    $ESC = 0x1B; $GS = 0x1D
    $ancho = [int]$cfg.Ancho
    if ($ancho -lt 24) { $ancho = 32 }

    # Formato 'texto': solo letras y saltos de línea, sin comandos de impresora
    if ($cfg.Formato -eq 'texto') {
        if ($cfg.Negocio) { & $txt $cfg.Negocio }
        foreach ($l in (Format-Recuadro $reg $ancho)) { & $txt $l }
        & $add @(0x0A, 0x0A, 0x0A, 0x0A)
        return ,$b.ToArray()
    }

    & $add @($ESC, 0x40)                 # inicializar
    & $add @($ESC, 0x61, 0)              # alineado a la izquierda (el recuadro ocupa todo el ancho)
    if ($cfg.Negocio) { & $add @($ESC, 0x61, 1, $ESC, 0x45, 1); & $txt $cfg.Negocio; & $add @($ESC, 0x45, 0, $ESC, 0x61, 0) }
    & $add @($ESC, 0x45, 1)              # negrita
    foreach ($l in (Format-Recuadro $reg $ancho)) { & $txt $l }
    & $add @($ESC, 0x45, 0)
    & $add @(0x0A, 0x0A, 0x0A)
    & $add @($GS, 0x56, 0x42, 0x00)      # corte parcial (si la impresora lo soporta)
    return ,$b.ToArray()
}

function Send-Ticket($reg) {
    $cfg = Get-Config
    if ($cfg.Modo -eq 'ninguna' -or -not $cfg.Modo) {
        Write-Host '   (Impresora no configurada: escribe I para configurarla)' -ForegroundColor DarkGray
        return
    }
    $bytes = New-Ticket $reg $cfg
    try {
        if ($cfg.Modo -eq 'bt') {
            try { [IdPedidosBluetooth]::Send($cfg.Bluetooth, [int]$cfg.Canal, $bytes, 15000) }
            catch { Start-Sleep -Seconds 2; [IdPedidosBluetooth]::Send($cfg.Bluetooth, [int]$cfg.Canal, $bytes, 15000) }   # segundo intento
        } elseif ($cfg.Modo -eq 'windows') {
            [IdPedidosRawPrinter]::Send($cfg.Impresora, $bytes)
        } elseif ($cfg.Modo -eq 'com') {
            $sp = New-Object System.IO.Ports.SerialPort $cfg.Puerto, ([int]$cfg.Baudios)
            $sp.WriteTimeout = 5000
            $sp.Open()
            try { $sp.Write($bytes, 0, $bytes.Length); Start-Sleep -Milliseconds 300 } finally { $sp.Close() }
        }
        Write-Host '   Impreso.' -ForegroundColor DarkGray
    } catch {
        Write-Log "No se pudo imprimir $($reg.ID): $($_.Exception.Message)"
        Write-Host "   NO SE PUDO IMPRIMIR: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host '   (El pedido SI quedó guardado. Revisa el Bluetooth y usa R para reimprimir.)' -ForegroundColor Yellow
    }
}

function Set-Impresora {
    Write-Host ''
    Write-Host ' CONFIGURAR IMPRESORA TÉRMICA' -ForegroundColor Cyan
    Write-Host ' 1. Bluetooth directo (Sunmi V2 Pro de PedidosYa u otra térmica) - recomendado'
    Write-Host ' 2. Impresora instalada en Windows'
    Write-Host ' 3. Puerto COM Bluetooth (SPP)'
    Write-Host ' 4. Sin impresora'
    $op = Read-Host ' Opción'
    $cfg = Get-Config
    switch ($op) {
        '1' {
            Write-Host ' (Primero empareja el aparato en Configuración > Bluetooth y dispositivos)' -ForegroundColor DarkGray
            $bts = Get-BluetoothEmparejados
            for ($i = 0; $i -lt $bts.Count; $i++) { Write-Host (' {0}. {1}   [{2}]' -f ($i + 1), $bts[$i].Nombre, ($bts[$i].Mac -replace '(..)(?!$)', '$1:')) }
            if ($bts.Count -eq 0) { Write-Host ' No se encontraron dispositivos emparejados.' -ForegroundColor Yellow }
            $n = Read-Host ' Número del dispositivo (o escribe la MAC, ej. 00:11:22:AA:BB:CC)'
            $hex = ($n -replace '[:\-\s]', '').ToUpper()
            if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $bts.Count) {
                $cfg.Modo = 'bt'; $cfg.Canal = 0; $cfg.Bluetooth = $bts[[int]$n - 1].Mac; $cfg.BluetoothNombre = $bts[[int]$n - 1].Nombre
            } elseif ($hex -match '^[0-9A-F]{12}$') {
                $cfg.Modo = 'bt'; $cfg.Canal = 0; $cfg.Bluetooth = $hex; $cfg.BluetoothNombre = $hex
            } else { Write-Host ' Opción inválida.' -ForegroundColor Yellow; return }
        }
        '2' {
            $lista = @(Get-CimInstance Win32_Printer | Select-Object -ExpandProperty Name)
            if ($lista.Count -eq 0) { Write-Host ' No hay impresoras instaladas.' -ForegroundColor Yellow; return }
            for ($i = 0; $i -lt $lista.Count; $i++) { Write-Host (' {0}. {1}' -f ($i + 1), $lista[$i]) }
            $n = Read-Host ' Número de la impresora'
            if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $lista.Count) {
                $cfg.Modo = 'windows'; $cfg.Impresora = $lista[[int]$n - 1]
            } else { Write-Host ' Opción inválida.' -ForegroundColor Yellow; return }
        }
        '3' {
            $puertos = @([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object -Unique)
            Write-Host (' Puertos disponibles: {0}' -f ($(if ($puertos) { $puertos -join ', ' } else { 'ninguno' })))
            $p = Read-Host ' Puerto (ej. COM5)'
            if (-not $p) { return }
            $bd = Read-Host ' Baudios [9600]'
            $cfg.Modo = 'com'; $cfg.Puerto = $p.Trim().ToUpper(); $cfg.Baudios = $(if ($bd -match '^\d+$') { [int]$bd } else { 9600 })
        }
        '4' { $cfg.Modo = 'ninguna' }
        default { return }
    }
    $neg = Read-Host " Nombre del negocio para el ticket (ENTER = '$($cfg.Negocio)')"
    if ($neg) { $cfg.Negocio = $neg }
    $an = Read-Host " Papel: 1 = 58 mm, 2 = 80 mm (ENTER = sin cambio)"
    if ($an -eq '1') { $cfg.Ancho = 32 } elseif ($an -eq '2') { $cfg.Ancho = 48 }
    Save-Config $cfg
    Write-Host ' Configuración guardada.' -ForegroundColor Green
    if ($cfg.Modo -ne 'ninguna' -and (Read-Host ' ¿Imprimir prueba? (S/N)') -match '^[sS]') {
        Send-Ticket ([pscustomobject]@{ Fecha = (Get-Date).ToString('dd/MM/yyyy'); Hora = (Get-Date).ToString('HH:mm:ss'); ID = 'PRUEBA-123'; Plataforma = 'PedidosYa' })
    }
}

# --------------------------------------------------------------------------
# Pantallas
# --------------------------------------------------------------------------
function Show-Lista($regs) {
    if ($regs.Count -eq 0) { Write-Host '   (Sin pedidos despachados)' -ForegroundColor DarkGray; return }
    $i = 0
    foreach ($r in $regs) {
        $i++
        $plat = Get-PlatByName $r.Plataforma
        Write-Host ('  {0,3}. {1}  ' -f $i, $r.Hora) -NoNewline -ForegroundColor Gray
        Write-Plat ('{0,-24} {1}' -f $r.ID, $r.Plataforma) $plat
    }
    Write-Host ''
    Write-Host '   Total: ' -NoNewline
    Write-Host $regs.Count -NoNewline -ForegroundColor White
    foreach ($p in $Plataformas.Values) {
        $c = @($regs | Where-Object { $_.Plataforma -eq $p.Nombre }).Count
        Write-Host '   |   ' -NoNewline -ForegroundColor DarkGray
        Write-Plat ("{0}: {1}" -f $p.Nombre, $c) $p -NoNewline
    }
    Write-Host ''
}

function Show-Encabezado {
    Clear-Host
    $hoy = Get-Date
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '                 ID PEDIDOS  -  DESPACHOS' -ForegroundColor White
    Write-Host ('                 Hoy: {0}' -f $hoy.ToString('dddd dd/MM/yyyy', [Globalization.CultureInfo]'es-ES')) -ForegroundColor Gray
    Write-Host '==============================================================' -ForegroundColor Cyan
    if ($script:EstadoImpresora) {
        $ok = $script:EstadoImpresora.StartsWith('OK|')
        Write-Host ' Impresora: ' -NoNewline -ForegroundColor Gray
        Write-Host $script:EstadoImpresora.Substring($(if ($ok) { 3 } else { 4 })) -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })
        Write-Host '--------------------------------------------------------------' -ForegroundColor DarkCyan
    }
    Show-Lista (Read-Day (Get-DayFile $hoy))
    Write-Host '--------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host ' Clic derecho = pegar ID  |  ENTER vacío = usar lo copiado' -ForegroundColor DarkGray
    Write-Host ' H = historial   R = reimprimir último   B = borrar último' -ForegroundColor DarkGray
    Write-Host ' I = configurar impresora   P = probar   D = diagnóstico' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-Historial {
    $archivos = @(Get-ChildItem -Path $DataDir -Filter '*.csv' | Sort-Object Name -Descending)
    if ($archivos.Count -eq 0) { Write-Host ' No hay historial todavía.' -ForegroundColor DarkGray; return }
    Write-Host ''
    Write-Host ' HISTORIAL (últimos días)' -ForegroundColor Cyan
    $mostrar = $archivos | Select-Object -First 30
    $i = 0
    foreach ($f in $mostrar) {
        $i++
        $n = @(Read-Day $f.FullName).Count
        Write-Host (' {0,2}. {1}   ({2} pedidos)' -f $i, $f.BaseName, $n)
    }
    Write-Host ' También puedes escribir una fecha (AAAA-MM-DD) o buscar un ID.'
    $op = Read-Host ' Número, fecha o ID (ENTER = volver)'
    if (-not $op) { return }
    $archivo = $null
    if ($op -match '^\d{1,2}$' -and [int]$op -ge 1 -and [int]$op -le $mostrar.Count) { $archivo = $mostrar[[int]$op - 1].FullName }
    elseif ($op -match '^\d{4}-\d{2}-\d{2}$') { $archivo = Join-Path $DataDir "$op.csv" }

    if ($archivo) {
        Write-Host ''
        Write-Host (' PEDIDOS DEL {0}' -f [IO.Path]::GetFileNameWithoutExtension($archivo)) -ForegroundColor Cyan
        Show-Lista (Read-Day $archivo)
    } else {
        $id = (Normalize-Id $op).ToUpperInvariant()
        if ($script:Indice.ContainsKey($id)) {
            $r = $script:Indice[$id]
            Write-Host ' Encontrado: ' -NoNewline
            Write-Plat ('{0}  {1}  {2} {3}' -f $r.ID, $r.Plataforma, $r.Fecha, $r.Hora) (Get-PlatByName $r.Plataforma)
        } else { Write-Host ' No se encontró ese ID.' -ForegroundColor Yellow }
    }
    Write-Host ''
    Read-Host ' ENTER para volver' | Out-Null
}

function Show-YaDespachado($r) {
    [Console]::Beep(1000, 250); [Console]::Beep(700, 400)
    Write-Host ''
    if ($script:Vt) {
        Write-Host "$Esc[1;97;41m                                                        $Esc[0m"
        Write-Host "$Esc[1;97;41m     ¡NO ENTREGAR!  ESTE PEDIDO YA SE HA DESPACHADO     $Esc[0m"
        Write-Host "$Esc[1;97;41m                                                        $Esc[0m"
    } else {
        Write-Host '  ¡NO ENTREGAR!  ESTE PEDIDO YA SE HA DESPACHADO  ' -ForegroundColor White -BackgroundColor DarkRed
    }
    Write-Host '   Despachado el ' -NoNewline
    Write-Plat ('{0} a las {1} por {2}  (ID {3})' -f $r.Fecha, $r.Hora, $r.Plataforma, $r.ID) (Get-PlatByName $r.Plataforma)
    Write-Host ''
}

function Read-Plataforma {
    Write-Host '   ¿Plataforma?  ' -NoNewline
    foreach ($k in $Plataformas.Keys) {
        Write-Plat ("$k $($Plataformas[$k].Nombre)") $Plataformas[$k] -NoNewline
        Write-Host '   ' -NoNewline
    }
    Write-Host '(ESC = cancelar): ' -NoNewline -ForegroundColor DarkGray
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Escape') { Write-Host 'cancelado' -ForegroundColor DarkGray; return $null }
        $c = [string]$k.KeyChar
        if ($Plataformas.Contains($c)) {
            Write-Plat $Plataformas[$c].Nombre $Plataformas[$c]
            return $Plataformas[$c]
        }
    }
}

# --------------------------------------------------------------------------
# Programa principal
# --------------------------------------------------------------------------
Build-Indice
Test-Impresora
$diaActual = (Get-Date).Date
Show-Encabezado

while ($true) {
    Write-Host ' ID del pedido > ' -NoNewline -ForegroundColor Cyan
    $entrada = [Console]::ReadLine()
    if ($null -eq $entrada) { break }

    # Cambio de día con la ventana abierta: la lista se reinicia sola
    if ((Get-Date).Date -ne $diaActual) { $diaActual = (Get-Date).Date; Show-Encabezado }

    switch -Regex ($entrada.Trim()) {
        '^[hH]$' { Show-Historial; Show-Encabezado; continue }
        '^[iI]$' { Set-Impresora; Test-Impresora; Start-Sleep -Seconds 1; Show-Encabezado; continue }
        '^[pP]$' { Test-Impresora; Show-Encabezado; continue }
        '^[dD]$' { Start-Diagnostico; Read-Host ' ENTER para volver' | Out-Null; Test-Impresora; Show-Encabezado; continue }
        '^[lL]$' { Show-Encabezado; continue }
        '^[rR]$' {
            $regs = Read-Day (Get-DayFile (Get-Date))
            if ($regs.Count -gt 0) { Send-Ticket $regs[-1] } else { Write-Host '   No hay pedidos hoy.' -ForegroundColor DarkGray }
            continue
        }
        '^[bB]$' {
            $regs = Read-Day (Get-DayFile (Get-Date))
            if ($regs.Count -eq 0) { Write-Host '   No hay pedidos hoy.' -ForegroundColor DarkGray; continue }
            $u = $regs[-1]
            if ((Read-Host "   ¿Borrar $($u.ID) ($($u.Plataforma))? (S/N)") -match '^[sS]') {
                [void](Remove-UltimoRegistro); Build-Indice; Show-Encabezado
            }
            continue
        }
    }
    if ($entrada.Trim() -match '^[hHiIlLrRbBpPdD]$') { continue }

    $id = Normalize-Id $entrada
    if (-not $id) {
        try { $id = Normalize-Id (Get-Clipboard -Raw) } catch { $id = '' }
        if (-not $id) { continue }
        Write-Host "   Usando lo copiado: $id" -ForegroundColor Gray
    }

    $clave = $id.ToUpperInvariant()
    if ($script:Indice.ContainsKey($clave)) { Show-YaDespachado $script:Indice[$clave]; continue }

    $plat = Read-Plataforma
    if (-not $plat) { continue }

    $ahora = Get-Date
    $reg = [pscustomobject]@{
        Fecha      = $ahora.ToString('dd/MM/yyyy')
        Hora       = $ahora.ToString('HH:mm:ss')
        ID         = $id
        Plataforma = $plat.Nombre
    }
    Add-Registro $reg
    $script:Indice[$clave] = $reg

    Write-Host '   GUARDADO ' -NoNewline -ForegroundColor White
    Write-Plat ('{0}  {1}  {2}' -f $reg.Hora, $reg.ID, $reg.Plataforma) $plat
    Send-Ticket $reg
    Start-Sleep -Milliseconds 900
    Show-Encabezado
}
