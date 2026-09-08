using System;
using System.Diagnostics;
using System.IO;

namespace MiniaturaWizardLauncher {
    class Program {
        [STAThread]
        static void Main(string[] args) {
            try {
                string projectDir = @"f:\Miniatura-Wizard";
                string pythonw = @"C:\Users\luisg\AppData\Local\Programs\Python\Python312\pythonw.exe";
                if (!File.Exists(pythonw)) {
                    pythonw = "pythonw.exe";
                }
                string script = Path.Combine(projectDir, "gui.py");
                
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = pythonw;
                psi.Arguments = "\"" + script + "\"";
                psi.WorkingDirectory = projectDir;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                Process.Start(psi);
            } catch (Exception ex) {
                System.Windows.Forms.MessageBox.Show("Error al iniciar Miniatura-Wizard: " + ex.Message, "Miniatura Wizard");
            }
        }
    }
}
