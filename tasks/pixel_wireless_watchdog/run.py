#!/usr/bin/env python3
"""
Task: pixel_wireless_watchdog
Description: Watchdog service that continuously monitors Google Pixel 8 Pro
             wireless debugging endpoint (IP and dynamic TLS port) via mDNS,
             keeps ADB connected, and automatically overwrites RollSync's
             Pixel-Conexion.json whenever the address changes.
Adheres strictly to TASK_AUTOMATION_HARNESS.md specifications.
"""

import sys
import os
import json
import time
import re
import socket
import argparse
import logging
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, Optional, Tuple, List

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
DEFAULT_SETTINGS: Dict[str, Any] = {
    "device_serial": "3A181FDJG0011R",
    "device_name": "Pixel 8 Pro",
    "target_config_path": r"F:\RollSync\Pixel-Conexion.json",
    "check_interval_seconds": 30,
    "auto_connect_adb": True,
    "voice_notifications": True,
    "voice_script_path": r"C:\Users\luisg\.gemini\config\salome_speak.py",
    "pin": "8137",
    "auto_unlock_on_change": True,
    "ensure_camera_video_mode": True,
    "mdns_service_type": "_adb-tls-connect._tcp",
    "default_ip": "192.168.1.103",
    "default_port": 36013,
    "log_level": "INFO"
}

def load_settings() -> Dict[str, Any]:
    if SETTINGS_FILE.exists():
        try:
            with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
                loaded = json.load(f)
                cfg = dict(DEFAULT_SETTINGS)
                cfg.update(loaded)
                return cfg
        except Exception as e:
            logging.warning(f"Error reading {SETTINGS_FILE}: {e}. Using defaults.")
    return dict(DEFAULT_SETTINGS)


class PixelWirelessWatchdog:
    def __init__(self, config: Dict[str, Any], dry_run: bool = False, enable_voice: bool = True):
        self.config = config
        self.dry_run = dry_run
        self.enable_voice = enable_voice and config.get("voice_notifications", True)
        self.serial = config.get("device_serial", "3A181FDJG0011R")
        self.target_config_path = Path(config.get("target_config_path", r"F:\RollSync\Pixel-Conexion.json"))
        self.voice_script = Path(config.get("voice_script_path", r"C:\Users\luisg\.gemini\config\salome_speak.py"))
        self.pin = str(config.get("pin", "8137"))
        
        self.checks_count = 0
        self.updates_count = 0
        self.errors_count = 0
        self.last_endpoint: Optional[str] = None
        self.last_status: str = "INITIALIZING"

    def run_cmd(self, cmd: List[str], timeout: float = 8.0) -> Tuple[int, str, str]:
        """Ejecuta un comando en el sistema de manera segura y sin ventana."""
        try:
            res = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
            )
            return res.returncode, res.stdout.strip(), res.stderr.strip()
        except subprocess.TimeoutExpired:
            return -1, "", "Timeout en comando"
        except Exception as e:
            return -1, "", str(e)

    def speak(self, text: str) -> None:
        """Emite mensaje por voz colombiana con Salomé si está habilitada."""
        if not self.enable_voice or not self.voice_script.exists():
            return
        try:
            subprocess.Popen(
                ["python", str(self.voice_script), text],
                creationflags=subprocess.DETACHED_PROCESS if os.name == "nt" else 0
            )
        except Exception as e:
            logging.debug(f"No se pudo reproducir TTS: {e}")

    def verify_adb(self) -> bool:
        """Paso 1: Comprobar que ADB está disponible en el PATH del sistema."""
        code, out, _ = self.run_cmd(["adb", "version"], timeout=5.0)
        return code == 0 and "Android Debug Bridge" in out

    def discover_device_endpoint(self) -> Optional[str]:
        """
        Paso 2: Detecta la dirección IP y puerto dinámico del Pixel 8 Pro.
        1. Consulta mDNS en tiempo real (_adb-tls-connect._tcp).
        2. Revisa conexiones activas existentes en adb devices.
        3. Comprueba el endpoint fijado en la configuración como fallback.
        """
        candidates: List[str] = []

        # 1. mDNS discovery
        code, out_mdns, _ = self.run_cmd(["adb", "mdns", "services"], timeout=5.0)
        if code == 0 and out_mdns:
            pattern = re.compile(
                rf"\S*{re.escape(self.serial)}.*_adb-tls-connect.*?\s+(\d{{1,3}}\.\d{{1,3}}\.\d{{1,3}}\.\d{{1,3}}:\d+)"
            )
            for line in out_mdns.splitlines():
                m = pattern.search(line)
                if m:
                    candidates.append(m.group(1))
                elif "_adb-tls-connect" in line:
                    m_ip = re.search(r"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+)", line)
                    if m_ip:
                        candidates.append(m_ip.group(1))

        # 2. Existing connected devices
        code, out_dev, _ = self.run_cmd(["adb", "devices"], timeout=5.0)
        if code == 0 and out_dev:
            for line in out_dev.splitlines():
                m = re.match(r"^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+)\s+device\s*$", line.strip())
                if m:
                    candidates.append(m.group(1))

        # 3. Target config fallback
        current_cfg = self.read_target_config()
        if current_cfg and "IP" in current_cfg and "Puerto" in current_cfg:
            candidates.append(f"{current_cfg['IP']}:{current_cfg['Puerto']}")

        # Verificar identidad de los candidatos (ro.serialno)
        for cand in set(candidates):
            # Conectar si no está conectado
            self.run_cmd(["adb", "connect", cand], timeout=4.0)
            code, serial_out, _ = self.run_cmd(["adb", "-s", cand, "shell", "getprop", "ro.serialno"], timeout=4.0)
            if code == 0 and serial_out.strip() == self.serial:
                return cand

        return None

    def read_target_config(self) -> Dict[str, Any]:
        """Lee el archivo Pixel-Conexion.json de RollSync."""
        if self.target_config_path.exists():
            try:
                with open(self.target_config_path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception as e:
                logging.warning(f"Error leyendo {self.target_config_path}: {e}")
        return {}

    def backup_target_config(self) -> Optional[Path]:
        """Crea copia de seguridad de Pixel-Conexion.json antes de modificarlo."""
        if not self.target_config_path.exists():
            return None
        ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        backup_file = BACKUP_DIR / f"Pixel-Conexion_{ts}.json"
        try:
            data = self.target_config_path.read_text(encoding="utf-8")
            backup_file.write_text(data, encoding="utf-8")
            logging.info(f"[Step 4/5] Copia de respaldo guardada en {backup_file.name}")
            return backup_file
        except Exception as e:
            logging.error(f"Fallo creando backup de configuración: {e}")
            return None

    def update_target_config(self, ip: str, port: int) -> bool:
        """Actualiza atómicamente Pixel-Conexion.json con la nueva IP y puerto."""
        if self.dry_run:
            logging.info(f"[DRY-RUN] Se actualizaría {self.target_config_path} con IP={ip}, Puerto={port}")
            return True

        self.backup_target_config()

        current = self.read_target_config()
        current["Nombre"] = current.get("Nombre", self.config.get("device_name", "Pixel 8 Pro"))
        current["IP"] = ip
        current["Puerto"] = int(port)
        current["Serie"] = self.serial
        current["PIN"] = current.get("PIN", self.pin)
        if "Scrcpy" not in current:
            current["Scrcpy"] = r"F:\scrcpy-win64-v3.3.4\scrcpy.exe"

        try:
            temp_path = self.target_config_path.with_suffix(".tmp")
            with open(temp_path, "w", encoding="utf-8") as f:
                json.dump(current, f, indent=2, ensure_ascii=False)
            temp_path.replace(self.target_config_path)
            logging.info(f"[Step 4/5] {self.target_config_path} actualizado exitosamente: {ip}:{port}")
            self.updates_count += 1
            return True
        except Exception as e:
            logging.error(f"Fallo al sobrescribir {self.target_config_path}: {e}")
            return False

    def perform_device_setup(self, endpoint: str) -> None:
        """Opcional: despierta, desbloquea con PIN y asegura modo video."""
        if not self.config.get("auto_unlock_on_change", True) or self.dry_run:
            return
        logging.info(f"[Step 4/5] Verificando desbloqueo y cámara en {endpoint}...")
        try:
            # Despertar y swipe
            self.run_cmd(["adb", "-s", endpoint, "shell", "input keyevent 224; input keyevent 82"], timeout=3.0)
            time.sleep(0.3)
            self.run_cmd(["adb", "-s", endpoint, "shell", "input swipe 500 1800 500 400 200"], timeout=3.0)
            time.sleep(0.3)
            self.run_cmd(["adb", "-s", endpoint, "shell", f"input text {self.pin}; input keyevent 66"], timeout=3.0)
            time.sleep(0.4)
            if self.config.get("ensure_camera_video_mode", True):
                self.run_cmd(["adb", "-s", endpoint, "shell", "am start -a android.media.action.VIDEO_CAMERA"], timeout=4.0)
        except Exception as e:
            logging.debug(f"Excepción en setup inicial de pantalla: {e}")

    def check_cycle(self) -> Dict[str, Any]:
        """Ejecuta una iteración de detección y sincronización."""
        self.checks_count += 1
        logging.info(f"--- Ciclo de comprobación #{self.checks_count} ---")

        # 1. Comprobar ADB
        logging.info("[Step 1/5] Verificando disponibilidad de herramientas ADB...")
        if not self.verify_adb():
            msg = "ADB no disponible o no responde"
            logging.error(f"[ERROR] {msg}")
            self.errors_count += 1
            self.last_status = "ADB_UNAVAILABLE"
            return {"status": "ERROR", "message": msg}

        # 2. Descubrir endpoint
        logging.info(f"[Step 2/5] Buscando Pixel 8 Pro (Serie: {self.serial}) vía mDNS...")
        endpoint = self.discover_device_endpoint()
        if not endpoint:
            msg = f"Pixel no detectado en la red. Verifica que la Depuración inalámbrica esté activa."
            logging.warning(f"[WARN] {msg}")
            self.last_status = "DEVICE_NOT_FOUND"
            return {"status": "NOT_FOUND", "message": msg}

        logging.info(f"[Step 3/5] Dispositivo confirmado en {endpoint}")
        self.last_endpoint = endpoint
        new_ip, new_port_str = endpoint.split(":")
        new_port = int(new_port_str)

        # 3. Comparar con target_config
        cfg = self.read_target_config()
        curr_ip = cfg.get("IP")
        curr_port = cfg.get("Puerto")

        needs_update = (curr_ip != new_ip or curr_port != new_port)
        if needs_update:
            logging.info(f"[Step 4/5] CAMBIO DETECTADO: Anterior=[{curr_ip}:{curr_port}] -> Nuevo=[{new_ip}:{new_port}]")
            ok = self.update_target_config(new_ip, new_port)
            if ok:
                self.perform_device_setup(endpoint)
                self.speak(f"Conexión del Pixel actualizada al puerto {new_port}")
                self.last_status = "UPDATED"
            else:
                self.last_status = "UPDATE_FAILED"
        else:
            logging.info(f"[Step 4/5] Configuración ya sincronizada [{new_ip}:{new_port}]. No requiere cambios.")
            self.last_status = "SYNCHRONIZED"

        return {
            "status": "SUCCESS",
            "endpoint": endpoint,
            "ip": new_ip,
            "port": new_port,
            "updated": needs_update
        }

    def generate_report(self, start_time: float, exit_status: str) -> Path:
        """Paso 5: Emite el informe KPI estandarizado según TASK_AUTOMATION_HARNESS.md."""
        end_time = time.time()
        duration = round(end_time - start_time, 2)
        
        report_data = {
            "metadata": {
                "task_name": "pixel_wireless_watchdog",
                "execution_timestamp": datetime.now(timezone.utc).isoformat(),
                "hostname": socket.gethostname(),
                "triggered_by": os.getenv("USERNAME", "luisg"),
                "exit_status": exit_status
            },
            "timing": {
                "start_time": datetime.fromtimestamp(start_time, timezone.utc).isoformat(),
                "end_time": datetime.fromtimestamp(end_time, timezone.utc).isoformat(),
                "total_duration_seconds": duration
            },
            "kpis": {
                "total_checks_performed": self.checks_count,
                "config_updates_performed": self.updates_count,
                "errors_recorded": self.errors_count,
                "last_known_endpoint": self.last_endpoint,
                "target_config_file": str(self.target_config_path),
                "device_serial": self.serial,
                "dry_run": self.dry_run
            }
        }

        try:
            with open(REPORT_FILE, "w", encoding="utf-8") as f:
                json.dump(report_data, f, indent=2, ensure_ascii=False)
            logging.info(f"[Step 5/5] Informe KPI generado en {REPORT_FILE.name}")
        except Exception as e:
            logging.error(f"Fallo al escribir informe KPI: {e}")

        return REPORT_FILE


def main():
    parser = argparse.ArgumentParser(description="Watchdog de conexión inalámbrica para Pixel 8 Pro y RollSync")
    parser.add_argument("--once", action="store_true", help="Ejecuta una sola comprobación y sale.")
    parser.add_argument("--daemon", action="store_true", help="Ejecuta en bucle continuo de supervisión.")
    parser.add_argument("--interval", type=int, help="Intervalo en segundos entre comprobaciones (default: 30s).")
    parser.add_argument("--dry-run", action="store_true", help="Simula sin actualizar Pixel-Conexion.json.")
    parser.add_argument("--no-voice", action="store_true", help="Desactiva los avisos de voz con Salomé.")
    args = parser.parse_args()

    cfg = load_settings()
    interval = args.interval or cfg.get("check_interval_seconds", 30)

    start_time = time.time()
    watchdog = PixelWirelessWatchdog(
        config=cfg,
        dry_run=args.dry_run,
        enable_voice=not args.no_voice
    )

    logging.info("==========================================================")
    logging.info("   PIXEL 8 PRO | VIGILANTE DE CONEXIÓN INALÁMBRICA       ")
    logging.info("   Sincronizador automático de mDNS para RollSync         ")
    logging.info("==========================================================")
    logging.info(f"Modo: {'UNA SOLA VEZ (--once)' if args.once else f'SUPERVISIÓN CONTINUA (cada {interval}s)'}")
    logging.info(f"Archivo objetivo: {watchdog.target_config_path}")
    logging.info(f"Dispositivo: {watchdog.serial} ({cfg.get('device_name', 'Pixel 8 Pro')})")

    exit_status = "SUCCESS"
    try:
        if args.once or not args.daemon:
            res = watchdog.check_cycle()
            if res.get("status") == "ERROR":
                exit_status = "FAILED"
        else:
            logging.info(f"Iniciando bucle de supervisión continua. Presiona Ctrl+C para detener.")
            while True:
                watchdog.check_cycle()
                time.sleep(interval)
    except KeyboardInterrupt:
        logging.info("\n[INFO] Supervisión detenida por el usuario (Ctrl+C).")
        exit_status = "STOPPED_BY_USER"
    except Exception as e:
        logging.exception(f"[ERROR] Error inesperado en el vigilante: {e}")
        exit_status = "FAILED"
    finally:
        watchdog.generate_report(start_time, exit_status)

    sys.exit(0 if exit_status in ("SUCCESS", "STOPPED_BY_USER") else 1)


if __name__ == "__main__":
    main()
