# ID PEDIDOS – registro de despachos para la consola de Windows

App de consola (ventana tipo CMD) para registrar los IDs de los pedidos despachados de **Uber**, **PedidosYa** y **Rappi**, avisar si un pedido ya se despachó e imprimir un ticket en la impresora térmica Bluetooth.

## Instalación (PowerShell)

Abre **PowerShell** y pega:

```powershell
irm https://raw.githubusercontent.com/bryanmoreta71/idpedidoscmd/main/install.ps1 | iex
```

O con el archivo **IdPedidos.zip**: clic derecho → **Extraer todo**, y doble clic en **INSTALAR.cmd**. También puedes ejecutar desde PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

El instalador se usa **una sola vez**. Al terminar se cierra solo y abre la app (una sola ventana). Después ya puedes borrar el zip y la carpeta extraída.

**Para el día a día:**

| Dónde | Qué hace |
|---|---|
| Escritorio → **ID Pedidos** | Abre la app (si ya está abierta, la trae al frente; nunca abre dos) |
| Escritorio → **ID Pedidos - Opciones** → `ACTIVAR inicio automatico` | Se abre sola al encender la computadora |
| Escritorio → **ID Pedidos - Opciones** → `DESACTIVAR inicio automatico` | Ya no se abre sola |
| Escritorio → **ID Pedidos - Opciones** → `DESINSTALAR` | Quita accesos e inicio automático (los registros se conservan) |

Lo mismo aparece en el **Menú Inicio → ID Pedidos**. El inicio automático queda activado al instalar.

## Uso

1. Copia el ID del pedido (Ctrl+C).
2. En la ventana, **clic derecho** (pega el ID) o simplemente **ENTER** con la línea vacía (usa lo copiado).
3. Presiona la tecla: **1** Uber · **2** PedidosYa · **3** Rappi.
4. Se guarda con la hora y se imprime solo.

Colores: **Uber = verde**, **PedidosYa = rojo**, **Rappi = naranja**.

Si el ID ya se registró antes (cualquier día) aparece en rojo:
**¡NO ENTREGAR! ESTE PEDIDO YA SE HA DESPACHADO**, con la fecha, hora y plataforma.

Al abrir se muestran solo los pedidos del día; al día siguiente la lista empieza vacía.

| Tecla | Acción |
|---|---|
| `H` | Historial: ver días anteriores, una fecha (AAAA-MM-DD) o buscar un ID |
| `R` | Reimprimir el último ticket |
| `B` | Borrar el último pedido (si te equivocaste de plataforma) |
| `I` | Configurar impresora |
| `P` | Probar conexión con la impresora |
| `D` | Diagnóstico de impresora (prueba canales y formatos, guarda el que funciona) |
| `L` | Limpiar pantalla |

## Impresora térmica Bluetooth

Escribe `I` dentro de la app:
- **1. Impresora instalada en Windows** (recomendado): empareja la impresora por Bluetooth, instálala en Windows y elígela de la lista.
- **2. Puerto COM Bluetooth**: si la impresora aparece como puerto serie (Configuración → Bluetooth → Más opciones → Puertos COM, el "Saliente").

Ticket impreso (papel 58 mm; también 80 mm):

```
+-------+--------------+-------+
| P YA  | 4815162342   | 14:32 |
+-------+--------------+-------+
Despachado 23/10/2026 14:32:05
```

Abreviaturas: `UBER`, `P YA`, `RAPPI`. Si el ID es largo continúa en la siguiente fila del recuadro.

## Registros

Un archivo por día en `%LOCALAPPDATA%\IdPedidos\registros\AAAA-MM-DD.csv` (se abre con Excel). Si se cierra la ventana no se pierde nada.

Para quitar el inicio automático: `uninstall.ps1` (los registros se conservan).
