#!/usr/bin/env python3
"""
Task: voice_trigger_angel_transcription
Description: Captures real-time microphone audio stream, detects the English wake-word "angel",
             records the following voice utterance, and transcribes it using Whisper.
             Reuses the proven transcription technology from F:/YT-Downloader/transcribir.py.
Adheres strictly to TASK_AUTOMATION_HARNESS.md specifications.
"""

import sys
import os
import re
import wave
import json
import time
import queue
import logging
import argparse
import numpy as np
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, Optional, Tuple, List

# 1. Base Paths & Directory Isolation
TASK_DIR = Path(__file__).resolve().parent
LOG_DIR = TASK_DIR / "logs"
REPORT_DIR = TASK_DIR / "reports"
ARTIFACT_DIR = TASK_DIR / "artifacts"
BACKUP_DIR = TASK_DIR / "backups"
CONFIG_DIR = TASK_DIR / "config"

for directory in (LOG_DIR, REPORT_DIR, ARTIFACT_DIR, BACKUP_DIR, CONFIG_DIR):
    directory.mkdir(parents=True, exist_ok=True)

TIMESTAMP = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
LOG_FILE = LOG_DIR / f"task_{TIMESTAMP}.log"
REPORT_FILE = REPORT_DIR / f"report_{TIMESTAMP}.json"

# 2. Dual Output Logging (Stdout & File)
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(sys.stdout)
    ]
)

# 3. Settings Management
SETTINGS_FILE = CONFIG_DIR / "settings.json"
DEFAULT_SETTINGS = {
    "wake_word": "angel",
    "wake_word_language": "en",
    "whisper_model": "base",
    "transcription_language": None,
    "sample_rate": 16000,
    "vad_energy_threshold": 0.012,
    "sliding_window_seconds": 2.5,
    "silence_timeout_seconds": 2.0,
    "max_speech_record_seconds": 15.0,
    "listen_timeout_seconds": 0,
    "audio_device_index": None
}

def load_settings() -> Dict[str, Any]:
    if SETTINGS_FILE.exists():
        try:
            with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                return {**DEFAULT_SETTINGS, **data}
        except Exception as e:
            logging.warning(f"Could not read {SETTINGS_FILE}: {e}. Using defaults.")
    return DEFAULT_SETTINGS

# 4. Rollback Procedure
def execute_rollback(artifacts: List[Path]) -> None:
    """Cleans up temporary or incomplete artifacts if execution fails."""
    logging.warning("Initiating rollback sequence...")
    for art in artifacts:
        if art and art.exists():
            try:
                art.unlink()
                logging.info(f"Rollback: removed incomplete artifact {art}")
            except Exception as e:
                logging.error(f"Failed to remove {art}: {e}")
    logging.warning("Rollback completed safely.")

# 5. Whisper Transcription Engine (Reused & Adapted from F:/YT-Downloader/transcribir.py)
def _mmss(seg_seconds: float) -> str:
    """Formats seconds into [MM:SS] display."""
    seg = int(seg_seconds or 0)
    return f"{seg // 60:02d}:{seg % 60:02d}"

def load_whisper_model(model_name: str):
    """Loads Whisper model with GPU detection and graceful CPU fallback."""
    import whisper
    import torch
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    logging.info(f"Loading Whisper model '{model_name}' on {dev.upper()}...")
    try:
        model = whisper.load_model(model_name, device=dev)
        return model, dev
    except Exception as e_cuda:
        if dev == "cuda":
            logging.warning(f"Failed to load on CUDA ({e_cuda}). Falling back to CPU...")
            model = whisper.load_model(model_name, device="cpu")
            return model, "cpu"
        raise e_cuda

def transcribir_audio(audio_path: Path, model, device: str, language: Optional[str] = None) -> Tuple[str, List[Dict[str, Any]]]:
    """Transcribes audio file using loaded Whisper model matching F:/YT-Downloader."""
    start_t = time.time()
    fp16_mode = (device == "cuda")
    logging.info(f"Transcribing {audio_path.name} with Whisper (language={language or 'auto'}, fp16={fp16_mode})...")
    res = model.transcribe(str(audio_path), language=language, task="transcribe", fp16=fp16_mode)
    texto = (res.get("text") or "").strip()
    segmentos = res.get("segments", []) or []
    elapsed = round(time.time() - start_t, 2)
    logging.info(f"Transcription completed in {elapsed}s: {len(texto.split())} words, {len(segmentos)} segments.")
    return texto, segmentos

def guardar_transcripcion(dest_dir: Path, title: str, text: str, segments: List[Dict[str, Any]], prefix: str = "") -> Tuple[Path, Path]:
    """Saves both raw text (.txt) and timestamped Markdown (.md) transcription."""
    txt_name = f"{prefix}transcripcion.txt" if prefix else "transcripcion.txt"
    md_name = f"{prefix}transcripcion.md" if prefix else "transcripcion.md"
    txt_path = dest_dir / txt_name
    md_path = dest_dir / md_name

    with open(txt_path, "w", encoding="utf-8") as f:
        f.write(text or "")

    with open(md_path, "w", encoding="utf-8") as f:
        f.write(f"# Transcripción — {title}\n\n")
        f.write(f"*Fecha de captura:* `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`\n\n")
        f.write("## 📝 Contenido\n\n")
        if segments:
            for s in segments:
                start_str = _mmss(s.get("start", 0))
                end_str = _mmss(s.get("end", 0))
                f.write(f"**[{start_str} - {end_str}]** {s.get('text', '').strip()}\n\n")
        else:
            f.write(text or "")

    logging.info(f"Saved transcription artifacts: {txt_name} and {md_name}")
    return txt_path, md_path

def save_wav(samples: np.ndarray, sample_rate: int, output_path: Path) -> int:
    """Saves float32 numpy samples (-1.0 to 1.0) into standard 16-bit PCM WAV."""
    int16_samples = (np.clip(samples, -1.0, 1.0) * 32767).astype(np.int16)
    with wave.open(str(output_path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(int16_samples.tobytes())
    return output_path.stat().st_size

# 6. Audio Stream Listening & Wake-Word Detection
def run_voice_trigger_task(dry_run: bool = False, timeout_seconds: int = 0) -> int:
    start_time = datetime.now(timezone.utc)
    settings = load_settings()
    created_artifacts: List[Path] = []

    kpis: Dict[str, Any] = {
        "task_name": "voice_trigger_angel_transcription",
        "timestamp": TIMESTAMP,
        "status": "RUNNING",
        "start_time": start_time.isoformat(),
        "dry_run": dry_run,
        "wake_word": settings["wake_word"],
        "wake_word_detected": False,
        "listen_duration_seconds": 0.0,
        "recorded_audio_seconds": 0.0,
        "audio_artifact": None,
        "transcript_text": None,
        "words_transcribed": 0,
        "segments_count": 0,
        "total_duration_seconds": 0.0
    }

    try:
        logging.info("[Step 1/4] Validating audio input devices and loading Whisper model...")
        import sounddevice as sd

        device_idx = settings.get("audio_device_index")
        input_info = sd.query_devices(device=device_idx, kind="input")
        logging.info(f"Microphone detected: '{input_info['name']}' (Index: {input_info['index']})")

        if dry_run:
            logging.info("[DRY RUN] Simulating stream activation and model verification.")
            model_name = settings.get("whisper_model", "base")
            logging.info(f"[DRY RUN] Model '{model_name}' configured for wake word '{settings['wake_word']}'.")
            kpis["status"] = "SUCCESS"
            return 0

        model_name = settings.get("whisper_model", "base")
        model, device = load_whisper_model(model_name)

        sample_rate = settings.get("sample_rate", 16000)
        energy_threshold = settings.get("vad_energy_threshold", 0.012)
        window_samples = int(settings.get("sliding_window_seconds", 2.5) * sample_rate)
        silence_timeout = settings.get("silence_timeout_seconds", 2.0)
        max_record_sec = settings.get("max_speech_record_seconds", 15.0)
        effective_timeout = timeout_seconds if timeout_seconds > 0 else settings.get("listen_timeout_seconds", 0)

        wake_word_regex = re.compile(rf"\b{re.escape(settings['wake_word'])}\b", re.IGNORECASE)

        # Audio stream queue
        audio_queue: queue.Queue[np.ndarray] = queue.Queue()

        def audio_callback(indata, frames, time_info, status):
            if status:
                logging.debug(f"Stream status: {status}")
            audio_queue.put(indata.copy())

        logging.info("[Step 2/4] Initializing real-time microphone stream...")
        logging.info(f"Listening for wake-word '{settings['wake_word'].upper()}' in English...")
        if effective_timeout > 0:
            logging.info(f"Listening timeout configured: {effective_timeout} seconds.")
        else:
            logging.info("Listening continuously until wake-word trigger (Press Ctrl+C to cancel)...")

        sliding_buffer = np.zeros(0, dtype=np.float32)
        post_trigger_samples: List[np.ndarray] = []
        is_triggered = False
        trigger_time = 0.0
        last_voice_time = 0.0
        listen_start = time.time()
        last_eval_time = time.time()

        with sd.InputStream(samplerate=sample_rate, channels=1, dtype="float32",
                            device=device_idx, callback=audio_callback, blocksize=int(sample_rate * 0.2)):
            
            while True:
                now = time.time()

                # Check timeout before trigger
                if not is_triggered and effective_timeout > 0 and (now - listen_start) > effective_timeout:
                    logging.info(f"Listen timeout ({effective_timeout}s) reached without wake-word activation.")
                    kpis["status"] = "TIMEOUT"
                    return 0

                try:
                    chunk = audio_queue.get(timeout=0.2).flatten()
                except queue.Empty:
                    continue

                chunk_rms = float(np.sqrt(np.mean(chunk**2)))

                if not is_triggered:
                    # Accumulate sliding window
                    sliding_buffer = np.concatenate((sliding_buffer, chunk))
                    if len(sliding_buffer) > window_samples:
                        sliding_buffer = sliding_buffer[-window_samples:]

                    # Evaluate wake word every 0.6 seconds if recent energy indicates presence of voice
                    if (now - last_eval_time >= 0.6) and (chunk_rms >= energy_threshold or np.sqrt(np.mean(sliding_buffer**2)) >= energy_threshold):
                        last_eval_time = now
                        eval_audio = sliding_buffer.copy()

                        # Fast wake-word inference in English
                        res = model.transcribe(eval_audio, language="en", task="transcribe", fp16=(device == "cuda"))
                        cand_text = (res.get("text") or "").strip()
                        if cand_text:
                            logging.debug(f"Heard candidate: '{cand_text}' (RMS: {chunk_rms:.4f})")

                        if wake_word_regex.search(cand_text):
                            is_triggered = True
                            trigger_time = now
                            last_voice_time = now
                            kpis["wake_word_detected"] = True
                            kpis["listen_duration_seconds"] = round(trigger_time - listen_start, 2)
                            logging.info(f"🔔 [WAKE-WORD ACTIVATED] Detected '{settings['wake_word'].upper()}' in audio stream!")
                            logging.info("🎙️ Recording speech utterance (Speak now)...")
                            print("\n" + "="*60, flush=True)
                            print(f"🔔 [ACTIVATED] Escuché '{settings['wake_word'].upper()}'. Grabando tu mensaje...", flush=True)
                            print("="*60 + "\n", flush=True)
                            continue

                else:
                    # Post-trigger recording
                    post_trigger_samples.append(chunk)
                    elapsed_record = now - trigger_time

                    if chunk_rms >= energy_threshold:
                        last_voice_time = now

                    silence_duration = now - last_voice_time

                    # Stop conditions: silence after minimum speech OR max duration reached
                    if (elapsed_record >= 1.5 and silence_duration >= silence_timeout) or (elapsed_record >= max_record_sec):
                        logging.info(f"Speech recording complete ({round(elapsed_record, 2)}s captured).")
                        break

        # If triggered, proceed with transcription
        if is_triggered and post_trigger_samples:
            full_speech = np.concatenate(post_trigger_samples)
            speech_seconds = len(full_speech) / sample_rate
            kpis["recorded_audio_seconds"] = round(speech_seconds, 2)

            logging.info(f"[Step 3/4] Persisting captured audio to artifacts ({kpis['recorded_audio_seconds']}s)...")
            wav_artifact = ARTIFACT_DIR / f"angel_recording_{TIMESTAMP}.wav"
            created_artifacts.append(wav_artifact)
            wav_bytes = save_wav(full_speech, sample_rate, wav_artifact)
            kpis["audio_artifact"] = str(wav_artifact)
            logging.info(f"WAV audio saved: {wav_artifact} ({wav_bytes} bytes).")

            logging.info("[Step 4/4] Transcribing captured speech using Whisper engine...")
            target_lang = settings.get("transcription_language")
            transcript_text, segments = transcribir_audio(wav_artifact, model, device, language=target_lang)

            txt_art, md_art = guardar_transcripcion(
                dest_dir=ARTIFACT_DIR,
                title=f"Activación por Wake-Word Angel ({TIMESTAMP})",
                text=transcript_text,
                segments=segments,
                prefix=f"angel_{TIMESTAMP}_"
            )
            created_artifacts.extend([txt_art, md_art])

            kpis["transcript_text"] = transcript_text
            kpis["words_transcribed"] = len(transcript_text.split())
            kpis["segments_count"] = len(segments)

            # Display final transcription prominently
            print("\n" + "="*60, flush=True)
            print("📝 [TRANSCRIPCIÓN RESULTANTE]:", flush=True)
            print(transcript_text if transcript_text else "(No se detectaron palabras legibles)", flush=True)
            print("="*60 + "\n", flush=True)

            kpis["status"] = "SUCCESS"
            return 0
        else:
            kpis["status"] = "NO_TRIGGER"
            return 0

    except KeyboardInterrupt:
        logging.info("Interrupted by user (Ctrl+C). Exiting cleanly.")
        kpis["status"] = "CANCELLED"
        return 0

    except Exception as e:
        kpis["status"] = "FAILED"
        kpis["error_message"] = str(e)
        logging.error(f"Execution failed: {e}", exc_info=True)
        execute_rollback(created_artifacts)
        return 1

    finally:
        end_time = datetime.now(timezone.utc)
        kpis["end_time"] = end_time.isoformat()
        kpis["total_duration_seconds"] = round((end_time - start_time).total_seconds(), 2)

        with open(REPORT_FILE, "w", encoding="utf-8") as f:
            json.dump(kpis, f, indent=2, ensure_ascii=False)
        logging.info(f"Execution finished with status: {kpis['status']}. Report: {REPORT_FILE}")

def main():
    parser = argparse.ArgumentParser(description="Wake-word 'Angel' Listener and Whisper Transcription Task")
    parser.add_argument("--dry-run", action="store_true", help="Simulate execution without capturing audio")
    parser.add_argument("--timeout", type=int, default=0, help="Stop listening after N seconds (0 = infinite)")
    args = parser.parse_args()

    exit_code = run_voice_trigger_task(dry_run=args.dry_run, timeout_seconds=args.timeout)
    sys.exit(exit_code)

if __name__ == "__main__":
    main()
