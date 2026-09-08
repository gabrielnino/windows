# Task: synthesize_colombian_speech

Esta tarea sintetiza voz neuronal en español con acento colombiano femenino de alta calidad (`es-CO-SalomeNeural`) y reproduce el audio resultante de forma inmediata en el sistema.

Cumple con todas las especificaciones de [`TASK_AUTOMATION_HARNESS.md`](../../TASK_AUTOMATION_HARNESS.md).

---

## 🎙️ Voz Utilizada
* **Identificador de Voz:** `es-CO-SalomeNeural`
* **Género:** Femenino
* **Región / Acento:** Colombia (`es-CO`)
* **Modelo:** Microsoft Edge / Azure Neural TTS (gratuito, sin necesidad de API key)
* **Calidad:** 24kHz / MP3 alta fidelidad

---

## 🚀 Uso Rápido

### Opción 1: Desde PowerShell (`run.ps1`)
```powershell
# Pasando el texto como parámetro:
.\tasks\synthesize_colombian_speech\run.ps1 -Text "Hola parcero, ¿cómo estás? Todo bien por aquí."

# O enviando el texto por tubería (pipeline):
"Buenas tardes, la tarea se completó con éxito." | .\tasks\synthesize_colombian_speech\run.ps1

# Solo generar el archivo de audio sin reproducirlo:
.\tasks\synthesize_colombian_speech\run.ps1 -Text "Mensaje guardado" -NoPlay

# Modo simulación (Dry Run):
.\tasks\synthesize_colombian_speech\run.ps1 -Text "Test" -DryRun

# Desactivar la pausa automática de YouTube:
.\tasks\synthesize_colombian_speech\run.ps1 -Text "No pauses YouTube" -NoPauseYouTube
```

### Opción 2: Directamente con Python (`run.py`)
```bash
python .\tasks\synthesize_colombian_speech\run.py --text "Hola, ¿en qué te puedo colaborar hoy?"

# Sin reproducir por parlantes:
python .\tasks\synthesize_colombian_speech\run.py --text "Solo guardar audio" --no-play

# Desactivar control de YouTube:
python .\tasks\synthesize_colombian_speech\run.py --text "Texto" --no-pause-youtube
```

---

## 🎥 Control Inteligente de Medios y Navegadores

La tarea inspecciona automáticamente todos los navegadores abiertos (`thorium.exe`, `chrome.exe`, `msedge.exe`, `brave.exe`, `firefox.exe`, `opera.exe`, etc.) mediante la API de Transporte Multimedia de Windows (WinRT SMTC) y medidores de audio WASAPI:
1. **Si hay video o audio reproduciéndose activamente:** Lo pausa inmediatamente antes de hablar.
2. **Si el navegador está quieto / en pausa:** No realiza ninguna acción de pausa (evita reanudar accidentalmente un video que ya habías pausado).
3. **Reproduce la locución:** Con la voz neuronal colombiana (`es-CO-SalomeNeural`).
4. **Cuenta 5 segundos:** Al finalizar la voz, cuenta regresivamente **5 segundos** (`5s... 4s... 3s... 2s... 1s...`).
5. **Reanudación automática:** Reanuda únicamente el video o audio que estaba corriendo previamente.

---

## ⚙️ Configuración (`config/settings.json`)

Puedes ajustar la velocidad, tono, volumen y control de medios en `config/settings.json`:
```json
{
  "voice": "es-CO-SalomeNeural",
  "rate": "+0%",
  "volume": "+0%",
  "pitch": "+0Hz",
  "auto_pause_browser_media": true,
  "resume_delay_seconds": 5.0
}
```

---

## 📂 Estructura de la Tarea

```
tasks/synthesize_colombian_speech/
├── run.ps1                  # Ejecutable principal en PowerShell (cumple con el Harness)
├── run.py                   # Lógica de síntesis (edge-tts) y reproducción (pygame)
├── rollback.ps1             # Rutina de reversión / limpieza segura
├── README.md                # Esta documentación
├── config/
│   └── settings.json        # Parámetros de voz
├── logs/                    # Registro paso a paso de cada ejecución
├── reports/                 # Informes KPI en JSON
├── artifacts/               # Archivos de audio generados (.mp3)
└── backups/                 # Instantáneas de seguridad
```
