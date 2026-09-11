# Aurora Console - Neon Powerline

Fondo negro puro, texto verde neon y carpetas cian sin rectangulos de fondo. Fuente JetBrainsMonoNL NFM de 16 puntos con iconos Nerd Font, instalada solo para el usuario. Prompt con bloques y flechas: ruta completa, rama Git si existe, Python si aplica, reloj y duracion. La ruta y el cursor comparten linea. Historial predictivo en linea.

Tab: menu de autocompletado. Ctrl+R: historial. Flechas: busqueda por prefijo. Alt+Shift+D: duplicar panel. aurora-help: ayuda. dir y Get-ChildItem muestran iconos conservando los objetos originales de PowerShell.

Desde PowerShell 7, dentro de esta carpeta: ./run.ps1 -DryRun para simular, ./run.ps1 para aplicar, ./verify.ps1 para comprobar. ./rollback.ps1 restaura el archivo original completo de Windows Terminal y la entrada anterior de registro de la fuente, conservando copia del estado reemplazado. Las herramientas portables, fuente y registros permanecen en artifacts/ y logs/.

El proyecto sigue TASK_AUTOMATION_HARNESS.md; backups/ contiene respaldos e informes en reports/. Los perfiles anteriores de PowerShell y el codigo de RollSync permanecen independientes. Para actualizar una sesion abierta, abre una nueva pestana Aurora Console. Si una ventana existente conserva la fuente anterior, abre una ventana nueva de Terminal.


Iconos por tipo: Git, JSON, C#, Visual Studio, Python, PowerShell, JavaScript, Markdown, imagenes, audio y carpetas especiales. Mapeo editable en config/file-icons.ps1.
