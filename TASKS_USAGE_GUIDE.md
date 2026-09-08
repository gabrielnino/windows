# Guía de Uso de Tasks (`f:\windows\tasks`)

Esta guía explica de forma práctica cómo ejecutar, configurar, auditar y revertir cualquiera de las tareas de automatización del repositorio `f:\windows`.

---

## 📌 1. ¿Qué es una "Task" en este repositorio?

Cada tarea es un módulo autocontenido ubicado en su propia carpeta dentro de `f:\windows\tasks\<nombre_de_tarea>/`. Todas las tareas cumplen con el estándar arquitectónico de [`TASK_AUTOMATION_HARNESS.md`](./TASK_AUTOMATION_HARNESS.md):

```text
tasks/<nombre_de_tarea>/
├── run.ps1                  # Script de ejecución principal en PowerShell
├── run.py                   # Script de ejecución principal en Python (si aplica)
├── rollback.ps1             # Rutina de reversión o limpieza en caso de fallos
├── README.md                # Documentación específica de la tarea
├── config/                  # Configuraciones externas
│   └── settings.json        # Parámetros editables (sin tocar el código fuente)
├── logs/                    # Registro paso a paso con timestamp (task_*.log)
├── reports/                 # Informes KPI en JSON (report_*.json)
├── artifacts/               # Archivos generados (audio, exports, capturas, etc.)
└── backups/                 # Copias de seguridad automáticas previas a cambios
```

---

## 🚀 2. Formas Estándar de Ejecución

### Requisitos previos
1. Abrir **PowerShell** (o **PowerShell 7 / pwsh**).
2. Para tareas que modifican el sistema (servicios, drivers, registro), abrir como **Administrador**.
3. Para tareas de usuario (como síntesis de voz, pruebas de audio, benchmarks de usuario), no se requiere elevación.

---

## 🎙️ 3. Tarea Destacada: Síntesis de Voz Colombiana (`synthesize_colombian_speech`)

Esta tarea recibe una cadena de texto, genera voz neuronal femenina con acento colombiano (`es-CO-SalomeNeural`) y **la reproduce de inmediato en tus parlantes**.

### Ejemplos de uso:

#### A. Pasando el texto como parámetro:
```powershell
.\tasks\synthesize_colombian_speech\run.ps1 -Text "¡Hola! ¿Cómo estás? Esta es una prueba con voz colombiana."
```

#### B. Mediante tubería (Pipeline):
```powershell
"El proceso de optimización ha terminado con éxito." | .\tasks\synthesize_colombian_speech\run.ps1
```

#### C. Directamente con Python:
```bash
python .\tasks\synthesize_colombian_speech\run.py --text "Buenas tardes, ¿en qué te puedo colaborar hoy?"
```

#### D. Solo generar el archivo MP3 (sin reproducir audio por parlantes):
```powershell
.\tasks\synthesize_colombian_speech\run.ps1 -Text "Audio guardado para después" -NoPlay
```

#### E. Simulación (Dry Run):
```powershell
.\tasks\synthesize_colombian_speech\run.ps1 -Text "Prueba" -DryRun
```

#### F. Control inteligente de video/audio en navegadores (Pausa y cuenta de 5 segundos):
La tarea inspecciona todos los navegadores (**Thorium**, Chrome, Edge, Brave, etc.):
1. **Si hay video o audio corriendo:** Lo pausa inmediatamente antes de hablar.
2. **Si el navegador está quieto / pausado:** No hace nada (no interrumpe ni reanuda por error).
3. Habla a través de los parlantes.
4. Al terminar la voz, **cuenta regresivamente 5 segundos**.
5. **Reanuda automáticamente** el video o audio que estaba corriendo.
*(Si deseas desactivar esta función en una ejecución puntual, añade `-NoPauseMedia`)*.

#### G. Personalizar la voz y parámetros:
Edita `tasks/synthesize_colombian_speech/config/settings.json`:
```json
{
  "voice": "es-CO-SalomeNeural",
  "rate": "+0%",
  "volume": "+0%",
  "pitch": "+0Hz",
  "auto_pause_browser_media": true,
  "resume_delay_seconds": 5.0,
  "default_text": "Texto por defecto si no se pasa ninguno"
}
```
*También puedes cambiar la voz a masculina colombiana (`es-CO-GonzaloNeural`) si lo deseas.*

---

## 👂 4. Tarea Destacada: Activación por Voz ("Angel") y Transcripción Whisper (`voice_trigger_angel_transcription`)

Esta tarea escucha continuamente el micrófono, se activa al detectar la palabra clave en inglés **"Angel"**, graba tu locución posterior hasta que hagas una pausa, y la transcribe en texto plano y Markdown con timestamps usando el motor de **Whisper** de `F:\YT-Downloader`.

### Ejemplos de uso:

#### A. Iniciar escucha en tiempo real:
```powershell
.\tasks\voice_trigger_angel_transcription\run.ps1
```
*Pronuncia **"Angel"** hacia el micrófono. Al activarse, di tu mensaje.*

#### B. Escucha con límite de tiempo (ej. 30 segundos):
```powershell
.\tasks\voice_trigger_angel_transcription\run.ps1 -TimeoutSeconds 30
```

#### C. Modo simulación (Dry Run):
```powershell
.\tasks\voice_trigger_angel_transcription\run.ps1 -DryRun
```

---

## 🛠️ 5. Parámetros Comunes en las Tasks

La mayoría de tareas admiten los siguientes modificadores estándar:

| Parámetro | Tipo | Descripción |
| :--- | :--- | :--- |
| `-DryRun` | `[switch]` | Simula la ejecución sin realizar cambios reales ni generar archivos definitivos. |
| `-NoPlay` | `[switch]` | *(En tareas de audio)* Genera el artefacto sin reproducir sonido. |
| `-Force` | `[switch]` | Omite confirmaciones interactivas en tareas de limpieza profunda. |

---

## 📊 5. Cómo Consultar Logs, Reportes y Artefactos

Cada vez que se ejecuta una tarea, se generan automáticamente archivos de auditoría dentro de su subcarpeta:

### 1. Ver el Log de la última ejecución:
```powershell
Get-Content (Get-ChildItem .\tasks\<nombre_de_tarea>\logs\task_*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
```

### 2. Ver el Reporte KPI en JSON:
```powershell
Get-Content (Get-ChildItem .\tasks\<nombre_de_tarea>\reports\report_*.json | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName | ConvertFrom-Json
```

### 3. Ver los Artefactos Generados:
Los archivos creados (como el `.mp3` generado en la síntesis de voz) se encuentran en:
```text
tasks/<nombre_de_tarea>/artifacts/
```

---

## 🔄 6. Cómo Revertir Cambios (Rollback)

Si una tarea falla durante su ejecución, **el rollback se ejecuta automáticamente** limpiando archivos temporales o restaurando copias de seguridad desde `backups/`.

Si deseas disparar la reversión manualmente en cualquier momento:
```powershell
.\tasks\<nombre_de_tarea>\rollback.ps1 -Reason "Reversión manual solicitada por el usuario"
```

---

## 📋 7. Catálogo de Comandos Rápidos para Tareas Frecuentes

```powershell
# 1. Voz sintética colombiana con reproducción inmediata
.\tasks\synthesize_colombian_speech\run.ps1 -Text "Hola, tarea ejecutada correctamente."

# 2. Prueba de loopback acústico de micrófono y parlantes
.\tasks\test_microphone_and_speaker_loopback\run.ps1

# 3. Monitoreo térmico de hardware (CPU y NVMe)
.\tasks\monitor_hardware_temperature\run.ps1

# 4. Auditoría profunda del sistema
.\tasks\system_audit\run.ps1

# 5. Optimización de servicios de Windows
.\tasks\optimize_windows_services\run.ps1
```

---

## 💡 8. Buenas Prácticas al Crear o Modificar Tasks

1. **Nunca escribir en la raíz (`f:\windows\`):** Todo archivo generado debe ir a `artifacts/`, `logs/` o `reports/` de la tarea respectiva.
2. **Idempotencia:** Una tarea debe poder ejecutarse múltiples veces sin corromper el estado del sistema.
3. **No quemar rutas absolutas:** Usar siempre `$PSScriptRoot` en PowerShell o `Path(__file__).resolve().parent` en Python.
