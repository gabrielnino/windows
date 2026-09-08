# Task: voice_trigger_angel_transcription

Captura un flujo continuo de audio desde el micrófono, monitorea en tiempo real la palabra clave de activación (**wake-word**) **"angel"** (en inglés), y tras activarse graba la locución del usuario y la transcribe con **Whisper**.

Reutiliza y adapta la tecnología desarrollada para [`F:\YT-Downloader\transcribir.py`](../../../YT-Downloader/transcribir.py) (detección CUDA/CPU, segmentación con timestamps `[MM:SS]`, exportación dual a texto plano y Markdown estructurado).

---

## 🚀 Cómo Usar

### 1. Iniciar la escucha desde PowerShell
```powershell
.\tasks\voice_trigger_angel_transcription\run.ps1
```

1. La tarea inicializará el micrófono y cargará el modelo Whisper (`base`).
2. Mostrará en consola:
   ```text
   Listening for wake-word 'ANGEL' in English...
   ```
3. Di la palabra **"Angel"** en inglés hacia el micrófono.
4. La consola se activará:
   ```text
   🔔 [ACTIVATED] Escuché 'ANGEL'. Grabando tu mensaje...
   ```
5. Pronuncia tu frase o consulta. Al guardar silencio (pausa de 2 segundos), la grabación se detiene automáticamente.
6. Whisper transcribirá la locución e imprimirá el resultado en pantalla.

---

### 2. Modos Opcionales

#### Con límite de tiempo de escucha (Timeout en segundos):
Si deseas que escuche durante máximo 30 segundos y luego termine si no escucha "Angel":
```powershell
.\tasks\voice_trigger_angel_transcription\run.ps1 -TimeoutSeconds 30
```

#### Modo Simulación (Dry Run):
Verifica la disponibilidad de dispositivos y dependencias sin abrir el micrófono:
```powershell
.\tasks\voice_trigger_angel_transcription\run.ps1 -DryRun
```

#### Ejecución directa desde Python:
```bash
python .\tasks\voice_trigger_angel_transcription\run.py --timeout 30
```

---

## ⚙️ Configuración (`config/settings.json`)

```json
{
  "wake_word": "angel",
  "wake_word_language": "en",
  "whisper_model": "base",
  "transcription_language": null,
  "sample_rate": 16000,
  "vad_energy_threshold": 0.012,
  "sliding_window_seconds": 2.5,
  "silence_timeout_seconds": 2.0,
  "max_speech_record_seconds": 15.0,
  "listen_timeout_seconds": 0,
  "audio_device_index": null
}
```
* **`wake_word`:** Palabra de activación (por defecto `"angel"`).
* **`whisper_model`:** Modelo de Whisper (`base`, `tiny`, `small`, etc.).
* **`vad_energy_threshold`:** Umbral RMS de energía para filtrar silencio y ahorrar CPU.
* **`silence_timeout_seconds`:** Segundos de silencio necesarios tras hablar para finalizar la grabación (2.0s).
* **`transcription_language`:** `null` para detección automática de idioma (español, inglés, etc.) tras la activación.

---

## 📂 Artefactos Generados (`artifacts/`)

Tras cada activación exitosa, se generan tres artefactos aislados:
1. `artifacts/angel_recording_<timestamp>.wav`: Audio PCM a 16 kHz capturado tras la activación.
2. `artifacts/angel_<timestamp>_transcripcion.txt`: Transcripción en texto plano.
3. `artifacts/angel_<timestamp>_transcripcion.md`: Transcripción formateada en Markdown con marcas de tiempo `[MM:SS]`.
4. `reports/report_<timestamp>.json`: Informe estructurado con KPIs (duración, palabras transcritas, estado).
