# Windows 11 Engineering & Automation Harness (`F:\windows`)

Comprehensive repository of system automation tasks, performance tuning scripts, silent launcher binaries, and hardware optimization harnesses for Windows 11 on modern creator/developer laptops (Target: **ASUS Vivobook Pro 15 OLED K6500ZC**).

---

## 🏛️ Architectural Standard: `TASK_AUTOMATION_HARNESS.md`

All tasks adhere strictly to an isolated, verifiable, and reversible engineering standard:
* ⚙️ `config/settings.json`: Externalized parameters, flags, thresholds, and target definitions.
* 🚀 `run.ps1`: Step-by-step idempotent execution script with structured timestamped logging (`[INFO]`, `[WARN]`, `[ERROR]`).
* 🔄 `rollback.ps1`: Pre-development reversion procedure for instantaneous state recovery.
* 📊 `reports/`: Dual-output reports in machine-readable JSON (`report_*.json`) and user-facing Markdown (`report_*.md`).
* 📝 `logs/`: High-resolution audit traces (`task_*.log`).

---

## 💻 Hardware Environment

* **Model:** ASUS Vivobook Pro 15 OLED (`K6500ZC`)
* **CPU:** 12th Gen Intel Core i7-12650H (Alder Lake-P, 10 Cores / 16 Threads)
* **RAM:** 16 GB LPDDR5 Micron @ 4800 MHz (Optimized: ~10 GB Free / 65% available)
* **Storage:** Samsung PM9A1 NVMe PCIe 4.0 1TB SSD (`hiberfil.sys` disabled, +7.8 GB freed)
* **Displays (Triple Monitor Topology):**
  1. `DISPLAY1`: 15.6" 2.8K OLED (2880x1620) @ 120Hz.
  2. `DISPLAY2`: 22" Samsung FHD (1920x1080) @ 60Hz.
  3. `DISPLAY3`: 22" Samsung FHD (1920x1080) @ 60Hz.

---

## 📂 Executed Automation Tasks Catalog

### 🌐 1. Browsers & Development Environments
* `tasks/setup_thorium_optimized_launcher`: Custom batch launcher & taskbar pin with `--process-per-site`, 10 renderer process cap, aggressive tab discarding, and 120Hz GPU rasterization.
* `tasks/tune_thorium_browser`: Browser memory saver tuning (15 min background discard), parallel multithreaded downloads, and Zero-Copy VRAM textures.
* `tasks/setup_silent_admin_antigravity`: C# zero-UAC elevated Antigravity GUI launcher (`AntigravitySilentAdmin.exe`).
* `tasks/optimize_antigravity_ide`: GPU rasterization and file-watcher exclusions (`.venv`, `node_modules`).
* `tasks/install_powershell7`: PowerShell 7 (`pwsh`) modern runtime installation.

### ⚡ 2. RAM Optimization, Services & Kernel Tuning
* `tasks/setup_daily_maintenance_purge`: Automated scheduled task `Maintenance_DailyPerformancePurge` triggering on Logon & 06:00 AM daily.
* `tasks/deep_ram_and_system_optimization`: Disabled GameDVR background capture, per-user sync templates, added Defender exclusions, and reclaimed +7.8 GB SSD space.
* `tasks/optimize_windows_services`: Stopped and disabled 14 heavy background services (SysMain, Telemetry, DiagTrack, PcaSvc, etc.).
* `tasks/disable_searchhost_prelaunch`: Disabled background web search and prelaunch overhead of `SearchHost.exe`.
* `tasks/disable_windows_search_indexer`: Disabled `WSearch` SSD disk churning indexer.
* `tasks/startup_optimization_and_benchmark`: Depurated startup execution entries.

### 🗑️ 3. Debloat & System Component Stripping
* `tasks/uninstall_microsoft_edge`: Removed Microsoft Edge and blocked auto-reinstallation policies.
* `tasks/permanently_disable_edge_update`: Disabled `edgeupdate` and `edgeupdatem`.
* `tasks/uninstall_outlook_and_store`: Removed modern Outlook and Store startup hooks.
* `tasks/remove_and_disable_copilot`: Neutralized Windows Copilot policies and UI triggers.
* `tasks/disconnect_and_uninstall_onedrive`: Unlinked and removed OneDrive sync.
* `tasks/disable_and_remove_windows_widgets`: Stripped Windows 11 Widgets newsfeed panel.
* `tasks/disable_user_experience_evaluation`: Neutralized telemetry data harvesting.
* `tasks/debloat_oem_utilities_and_benchmark`: Removed factory UWP bloatware packages.

### 🎧 4. Audio, Bluetooth & Drivers
* `tasks/install_asus_realtek_audio_driver`: Downloaded and injected official ASUS Realtek UAD (`6.0.9329.1`) & Intel SST (`10.29.0.7767`) packages into DriverStore.
* `tasks/restore_bluetooth_device_pairing`: Configured `DevicesFlowUserSvc`, `DevicePickerUserSvc`, and `CDPUserSvc` in manual on-demand mode.
* `tasks/test_microphone_and_speaker_loopback`: End-to-end acoustic loopback test suite with 44.1 kHz 16-bit PCM sampling and waveform analysis.
* `tasks/install_windows_file_recovery`: Deployed Microsoft `winfr.exe` utility.

### ⌨️ 5. Keyboard, International & Visual Polish
* `tasks/set_english_latin_america_keyboard`: Fixed `en-US` with Latin American keyboard layout (`0409:0000080A`), registry `Preload` (`d0010409`), and `Substitutes` (`0000080a`).
* `tasks/optimize_visual_effects_for_performance`: Stripped Mica/Acrylic blur, transparency, and window animations while preserving ClearType font smoothing.
* `tasks/enable_dark_theme`: Universal dark mode across system shell and applications.
* `tasks/set_minimalist_black_wallpaper`: Pure black minimal wallpaper across all 3 displays.

### 🔌 6. Power & Display Management
* `tasks/configure_ac_power_plan`: Configured AC power plan (10m display turnoff, 0 sleep/hibernate, continuous background execution with lid closed).
* `tasks/configure_display_topology`: Triple-display layout alignment and OLED 120Hz refresh rate calibration.
* `tasks/monitor_hardware_temperature`: Real-time thermal diagnostics for Intel Core i7 CPU and Samsung NVMe SSD.
* `tasks/system_audit`: Comprehensive hardware, BIOS, storage, and network audit.

---

## 📜 License
MIT License.
