using System;
using System.Diagnostics;
using System.IO;

namespace ToggleShokzLauncher {
    class Program {
        static void Main(string[] args) {
            try {
                string scriptPath = @"F:\windows\launchers\Toggle-Shokz.ps1";
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + scriptPath + "\"";
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                Process.Start(psi);
            } catch { }
        }
    }
}
