# Tarea: Vigilante de Conexión Inalámbrica del Pixel (`pixel_wireless_watchdog`)

## 📌 1. Descripción y Propósito
Servicio vigilante (*Watchdog*) diseñado para ejecutarse localmente en la máquina Windows. Supervisa de forma pasiva y sin impacto térmico en el teléfono los anuncios **mDNS** (`_adb-tls-connect._tcp`) del **Google Pixel 8 Pro** conectado como cámara de estudio.

Cuando el sistema operativo Android asigna un puerto dinámico nuevo o cambia de dirección IP:
1. Detecta el cambio en tiempo real a través de mDNS y `adb devices`.
2. Realiza una copia de seguridad automática en `backups/`.
3. Sobrescribe de forma atómica el archivo de configuración `F:\RollSync\Pixel-Conexion.json` con la nueva IP y puerto.
4. Conecta la sesión ADB (`adb connect <ip>:<puerto>`) y verifica la identidad (`ro.serialno: 3A181FDJG0011R`).
5. Despierta la pantalla, ingresa el PIN `8137` y asegura que la Cámara nativa de Google quede en modo Video.
6. Emite un aviso sonoro por voz colombiana (**Salomé**) informando la actualización.

Cumple estrictamente con el estándar arquitectónico de [`TASK_AUTOMATION_HARNESS.md`](../../TASK_AUTOMATION_HARNESS.md).

---

## 📂 2. Estructura de Directorios

```text
f:/windows/tasks/pixel_wireless_watchdog/
├── run.ps1                  # Frontend de ejecución PowerShell con soporte para parámetros
├── run.py                   # Lógica principal del vigilante y generador de reportes KPI
├── rollback.ps1             # Rutina de reversión que restaura la copia previa de Pixel-Conexion.json
├── README.md                # Documentación técnica completa
├── config/
│   └── settings.json        # Parámetros editables (intervalo, serial, PIN, voz, etc.)
├── logs/
│   └── task_YYYYMMDD_HHMMSS.log   # Registro paso a paso con timestamps
├── reports/
│   └── report_YYYYMMDD_HHMMSS.json # Informe KPI de ejecución estandarizado
├── artifacts/               # Archivos generados y volcados de diagnóstico
└── backups/                 # Instantáneas de seguridad de Pixel-Conexion.json
```

---

## 🚀 3. Formas de Ejecución

### A. Comprobación única y generación de reporte KPI:
```powershell
.\tasks\pixel_wireless_watchdog\run.ps1 -Once
```
O directamente con Python:
```bash
python .\tasks\pixel_wireless_watchdog\run.py --once
```

### B. Supervisión continua (Bucle Watchdog cada 30 segundos):
```powershell
.\tasks\pixel_wireless_watchdog\run.ps1 -Continuous -IntervalSeconds 30
```

### C. Modo Simulación (Dry-Run):
```powershell
.\tasks\pixel_wireless_watchdog\run.ps1 -Once -DryRun
```

### D. Modo Silencioso (Sin avisos de voz TTS):
```powershell
.\tasks\pixel_wireless_watchdog\run.ps1 -Continuous -NoVoice
```

---

## ⚙️ 4. Parámetros de Configuración (`config/settings.json`)

```json
{
  "device_serial": "3A181FDJG0011R",
  "device_name": "Pixel 8 Pro",
  "target_config_path": "F:\\RollSync\\Pixel-Conexion.json",
  "check_interval_seconds": 30,
  "auto_connect_adb": true,
  "voice_notifications": true,
  "voice_script_path": "C:\\Users\\luisg\\.gemini\\config\\salome_speak.py",
  "pin": "8137",
  "auto_unlock_on_change": true,
  "ensure_camera_video_mode": true,
  "mdns_service_type": "_adb-tls-connect._tcp",
  "default_ip": "192.168.1.103",
  "default_port": 36013,
  "log_level": "INFO"
}
```

---

## 🔄 5. Reversión (*Rollback*)
En caso de requerir volver a la configuración anterior:
```powershell
.\tasks\pixel_wireless_watchdog\rollback.ps1
```
Restaurará automáticamente la versión previa de `Pixel-Conexion.json` guardada en `backups/`.
