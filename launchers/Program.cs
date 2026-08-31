using System;
using System.Diagnostics;

namespace AntigravityLauncher {
    class Program {
        static void Main(string[] args) {
            try {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "schtasks.exe";
                psi.Arguments = "/run /tn \"Launch_Antigravity_Elevated\"";
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                Process.Start(psi);
            } catch {}
        }
    }
}
