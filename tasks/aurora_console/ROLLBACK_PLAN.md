# Plan de restauracion
Antes de cambiar Windows Terminal se guardara su archivo completo y su hash en backups.
Aurora usara un perfil dedicado y un archivo de inicio propio: no modifica los perfiles PowerShell existentes.
Las herramientas se instalaran de forma portable dentro de artifacts, sin instaladores globales ni cambios de PATH o registro.
rollback.ps1 restaura settings.json. Si detecta cambios posteriores, conserva una copia antes de restaurar.
Ante un fallo al aplicar configuracion, run.ps1 invoca la restauracion automaticamente.
Los binarios portables y los registros permanecen en el proyecto como artefactos inactivos tras restaurar.

Revision Neon: registrar JetBrains Mono Nerd Font solo para el usuario, desde artifacts/fonts. Guardar estado previo de la entrada Fonts y retirarla al restaurar. El archivo fuente permanece en el proyecto. Los formatos de iconos solo se cargan en Aurora.

Revision iconos: copia de config y README en backups/icons_FECHA antes de editar. Los iconos usan solo formato de salida local; no cambian archivos ni objetos devueltos. Restaurar esa copia y reaplicar run.ps1 revierte esta revision.
