#!/usr/bin/env python3
"""
Task: synthesize_colombian_speech
Description: Synthesizes high-fidelity speech in Spanish with a female Colombian accent (es-CO-SalomeNeural)
             from input text and immediately plays the resulting audio.
             Verifies all web browsers and media players before speaking:
             - If audio/video is actively playing: pauses it before speaking.
             - If browsers are quiet/paused: does nothing (no false toggling).
             - Once speech finishes: counts 5 seconds and resumes the video/audio that was playing.
Adheres strictly to TASK_AUTOMATION_HARNESS.md specifications.
"""

import sys
import os
import json
import time
import argparse
import asyncio
import logging
import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, Optional, List, Tuple

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

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

# 2. Logging Setup (Dual Output: File & Stdout)
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(sys.stdout)
    ]
)

# 3. Load Settings
SETTINGS_FILE = CONFIG_DIR / "settings.json"
DEFAULT_SETTINGS = {
    "voice": "es-CO-SalomeNeural",
    "voice_gender": "Female",
    "voice_locale": "es-CO",
    "rate": "+0%",
    "volume": "+0%",
    "pitch": "+0Hz",
    "default_text": "¡Hola! ¿Cómo estás? Esta es una prueba de voz sintética colombiana.",
    "auto_pause_browser_media": True,
    "resume_delay_seconds": 5.0
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

# 4. Windows Interop: Browser & Active Media Playback Detection (SMTC + WASAPI)
user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32

KNOWN_BROWSERS = {
    "thorium.exe",
    "chrome.exe",
    "msedge.exe",
    "brave.exe",
    "firefox.exe",
    "opera.exe",
    "vivaldi.exe"
}

def toggle_hardware_media_key() -> None:
    """Sends global VK_MEDIA_PLAY_PAUSE hardware event."""
    VK_MEDIA_PLAY_PAUSE = 0xB3
    KEYEVENTF_KEYUP = 0x0002
    user32.keybd_event(VK_MEDIA_PLAY_PAUSE, 0, 0, 0)
    time.sleep(0.05)
    user32.keybd_event(VK_MEDIA_PLAY_PAUSE, 0, KEYEVENTF_KEYUP, 0)

async def detect_and_pause_active_media() -> Tuple[bool, List[Any], str]:
    """
    Inspects all system media sessions and running browser audio meters.
    - If video/audio is actively playing (status == 4 or peak audio > 0.001): pauses it.
    - If browsers are quiet/paused: does NOTHING (avoids accidental playback).
    Returns (was_paused: bool, paused_sessions: List, media_description: str)
    """
    paused_sessions = []
    desc = ""

    # Check 1: Windows System Media Transport Controls (WinRT SMTC)
    try:
        from winsdk.windows.media.control import GlobalSystemMediaTransportControlsSessionManager as SMTC
        mgr = await SMTC.request_async()
        sessions = mgr.get_sessions()

        for s in sessions:
            try:
                info = s.get_playback_info()
                status = int(info.playback_status) # 4 = Playing, 5 = Paused
                if status == 4: # Actively playing!
                    props = await s.try_get_media_properties_async()
                    title = props.title if props and props.title else s.source_app_user_model_id
                    desc = f"SMTC session '{title}'"
                    logging.info(f"[MEDIA] Active playback detected in {desc}. Pausing...")
                    success = await s.try_pause_async()
                    if success:
                        paused_sessions.append(s)
            except Exception as e_session:
                logging.debug(f"Error checking SMTC session: {e_session}")
    except Exception as e_smtc:
        logging.debug(f"SMTC check unavailable: {e_smtc}")

    # Check 2: WASAPI Audio Meter (Core Audio for browsers)
    try:
        from pycaw.pycaw import AudioUtilities, IAudioMeterInformation
        for audio_session in AudioUtilities.GetAllSessions():
            proc = audio_session.Process
            if proc and proc.name().lower() in KNOWN_BROWSERS:
                try:
                    meter = audio_session._ctl.QueryInterface(IAudioMeterInformation)
                    peak = meter.GetPeakValue()
                    if peak > 0.001: # Browser emitting physical sound!
                        desc = f"Browser '{proc.name()}' (Peak: {peak:.4f})"
                        logging.info(f"[MEDIA] Active sound detected from {desc}.")
                        if not paused_sessions:
                            logging.info("[MEDIA] Sending pause command to active browser...")
                            toggle_hardware_media_key()
                            paused_sessions.append("HARDWARE_KEY")
                except Exception:
                    pass
    except Exception as e_wasapi:
        logging.debug(f"WASAPI check error: {e_wasapi}")

    if paused_sessions:
        return True, paused_sessions, desc
    else:
        logging.info("[MEDIA] Browsers and media sessions are quiet/paused. No pause action needed.")
        return False, [], "QUIET"

async def resume_paused_media(paused_sessions: List[Any]) -> None:
    """Resumes only the media sessions that were previously playing."""
    for s in paused_sessions:
        try:
            if s == "HARDWARE_KEY":
                toggle_hardware_media_key()
            else:
                await s.try_play_async()
        except Exception as e:
            logging.error(f"[MEDIA] Failed to resume session {s}: {e}")

# 5. Rollback Procedure
def execute_rollback(audio_artifact: Optional[Path] = None, paused_sessions: Optional[List[Any]] = None) -> None:
    """Restores state if failure occurs during execution."""
    logging.warning("Initiating rollback sequence...")
    if paused_sessions:
        try:
            logging.info("Rollback: Resuming paused media sessions...")
            asyncio.run(resume_paused_media(paused_sessions))
        except Exception as e:
            logging.error(f"Failed to resume media in rollback: {e}")

    if audio_artifact and audio_artifact.exists():
        try:
            audio_artifact.unlink()
            logging.info(f"Cleaned up incomplete audio artifact: {audio_artifact}")
        except Exception as e:
            logging.error(f"Failed to remove artifact during rollback: {e}")
    logging.warning("Rollback sequence completed.")

# 6. Synthesis & Playback
async def synthesize_speech(text: str, voice: str, rate: str, pitch: str, volume: str, output_path: Path) -> int:
    import edge_tts
    communicate = edge_tts.Communicate(text=text, voice=voice, rate=rate, pitch=pitch, volume=volume)
    await communicate.save(str(output_path))
    return output_path.stat().st_size

def play_audio(audio_path: Path) -> float:
    """Plays the audio file and waits for completion."""
    play_start = time.time()
    try:
        os.environ["PYGAME_HIDE_SUPPORT_PROMPT"] = "1"
        import pygame
        pygame.mixer.init()
        pygame.mixer.music.load(str(audio_path))
        pygame.mixer.music.play()
        while pygame.mixer.music.get_busy():
            time.sleep(0.05)
        pygame.mixer.quit()
    except Exception as e:
        logging.warning(f"Pygame playback failed ({e}), falling back to Windows PowerShell Media Player...")
        import subprocess
        ps_cmd = (
            f"Add-Type -AssemblyName presentationCore; "
            f"$player = New-Object system.windows.media.mediaplayer; "
            f"$player.open([System.Uri]'{str(audio_path)}'); "
            f"$player.Play(); "
            f"Start-Sleep -Milliseconds 500; "
            f"while ($player.NaturalDuration.HasTimeSpan -and ($player.Position -lt $player.NaturalDuration.TimeSpan)) {{ Start-Sleep -Milliseconds 100 }}; "
            f"$player.Close()"
        )
        subprocess.run(["powershell", "-NoProfile", "-Command", ps_cmd], check=True)
    return time.time() - play_start

# 7. Main Task Routine
def run_task(text: Optional[str] = None, dry_run: bool = False, no_play: bool = False, no_pause_media: bool = False) -> int:
    start_time = datetime.now(timezone.utc)
    settings = load_settings()
    
    input_text = text.strip() if text and text.strip() else settings.get("default_text", "")
    voice = settings.get("voice", "es-CO-SalomeNeural")
    rate = settings.get("rate", "+0%")
    pitch = settings.get("pitch", "+0Hz")
    volume = settings.get("volume", "+0%")
    auto_pause_enabled = (settings.get("auto_pause_browser_media", True) or settings.get("auto_pause_youtube", True)) and not no_pause_media and not no_play
    resume_delay = float(settings.get("resume_delay_seconds", 5.0))

    output_audio = ARTIFACT_DIR / f"speech_es_CO_{TIMESTAMP}.mp3"
    media_paused = False
    paused_sessions: List[Any] = []

    kpis: Dict[str, Any] = {
        "task_name": "synthesize_colombian_speech",
        "timestamp": TIMESTAMP,
        "status": "RUNNING",
        "start_time": start_time.isoformat(),
        "dry_run": dry_run,
        "no_play": no_play,
        "voice": voice,
        "voice_gender": settings.get("voice_gender", "Female"),
        "text_length_chars": len(input_text),
        "text_preview": input_text[:80] + ("..." if len(input_text) > 80 else ""),
        "audio_artifact": str(output_audio) if not dry_run else None,
        "audio_bytes": 0,
        "browser_media_active_before": False,
        "media_paused_by_task": False,
        "resume_delay_seconds": resume_delay,
        "media_resumed_by_task": False,
        "synthesis_duration_seconds": 0.0,
        "playback_duration_seconds": 0.0,
        "total_duration_seconds": 0.0
    }

    try:
        logging.info("[Step 1/4] Validating parameters and audio configuration...")
        logging.info(f"Target Voice: {voice} (Colombian Female)")
        logging.info(f"Input Text: \"{kpis['text_preview']}\" ({len(input_text)} characters)")

        if dry_run:
            logging.info("[DRY RUN] Inspecting active browser media in simulation mode...")
            was_p, p_sess, d = asyncio.run(detect_and_pause_active_media())
            logging.info(f"[DRY RUN] Active media state: was_p={was_p}, detail='{d}'")
            logging.info("[DRY RUN] Skipping actual synthesis and playback.")
            kpis["status"] = "SUCCESS"
            return 0

        # Step 2: Synthesis
        logging.info("[Step 2/4] Synthesizing speech with high-fidelity neural model...")
        synth_start = time.time()
        file_size = asyncio.run(synthesize_speech(input_text, voice, rate, pitch, volume, output_audio))
        kpis["synthesis_duration_seconds"] = round(time.time() - synth_start, 2)
        kpis["audio_bytes"] = file_size
        logging.info(f"Synthesis successful. Generated {file_size} bytes in {kpis['synthesis_duration_seconds']}s.")
        logging.info(f"Audio saved to: {output_audio}")

        if no_play:
            logging.info("[Step 3/4] Audio playback skipped (--no-play flag enabled).")
            kpis["status"] = "SUCCESS"
            return 0

        # Step 3: Check all browsers - pause if actively playing, do nothing if quiet
        if auto_pause_enabled:
            logging.info("[Step 3/4] Verifying all web browsers for active media/video playback...")
            media_paused, paused_sessions, media_desc = asyncio.run(detect_and_pause_active_media())
            kpis["browser_media_active_before"] = media_paused
            kpis["media_paused_by_task"] = media_paused
            if media_paused:
                logging.info(f"[MEDIA] Active playback paused ({media_desc}).")
                time.sleep(0.3)
        else:
            logging.info("[Step 3/4] Browser media check bypassed by configuration/flag.")

        # Step 4: Play speech audio
        logging.info("[Step 4/4] Playing speech audio through system speakers...")
        playback_dur = play_audio(output_audio)
        kpis["playback_duration_seconds"] = round(playback_dur, 2)
        logging.info(f"Audio playback completed ({kpis['playback_duration_seconds']}s).")

        # Post-speech: If media was playing, wait 5 seconds and resume
        if media_paused and paused_sessions:
            logging.info(f"[MEDIA] Audio finished. Counting {int(resume_delay)} seconds before resuming video/audio...")
            for second_remaining in range(int(resume_delay), 0, -1):
                logging.info(f"[MEDIA] Resuming in {second_remaining}s...")
                time.sleep(1.0)
            
            logging.info("[MEDIA] Resuming browser video/audio playback now...")
            asyncio.run(resume_paused_media(paused_sessions))
            kpis["media_resumed_by_task"] = True
            logging.info("[MEDIA] Video/audio playback resumed successfully!")
        else:
            logging.info("[MEDIA] Browsers were quiet initially. No resume action performed.")

        kpis["status"] = "SUCCESS"
        return 0

    except Exception as e:
        kpis["status"] = "FAILED"
        kpis["error_message"] = str(e)
        logging.error(f"Execution failed: {e}", exc_info=True)
        execute_rollback(output_audio, paused_sessions=paused_sessions if media_paused else None)
        return 1

    finally:
        end_time = datetime.now(timezone.utc)
        kpis["end_time"] = end_time.isoformat()
        kpis["total_duration_seconds"] = round((end_time - start_time).total_seconds(), 2)

        with open(REPORT_FILE, "w", encoding="utf-8") as f:
            json.dump(kpis, f, indent=2, ensure_ascii=False)
        
        logging.info(f"Execution finished with status: {kpis['status']}. Report saved to: {REPORT_FILE}")

def main():
    parser = argparse.ArgumentParser(description="TTS Task: Colombian Spanish Female Voice with Intelligent Browser Media Pause & 5s Resume")
    parser.add_argument("--text", "-t", type=str, default="", help="Text string to synthesize into speech")
    parser.add_argument("--dry-run", action="store_true", help="Simulate execution without generating audio")
    parser.add_argument("--no-play", action="store_true", help="Generate audio file only, skip playback")
    parser.add_argument("--no-pause-media", "--no-pause-youtube", action="store_true", help="Do not check or pause browser media")
    args = parser.parse_args()

    exit_code = run_task(
        text=args.text,
        dry_run=args.dry_run,
        no_play=args.no_play,
        no_pause_media=args.no_pause_media
    )
    sys.exit(exit_code)

if __name__ == "__main__":
    main()
