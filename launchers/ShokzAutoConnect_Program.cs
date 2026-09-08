using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace ShokzAutoConnect {
    class Program {
        static Mutex mutex = new Mutex(true, "ShokzAutoConnect_SingleInstance_Mutex");

        [STAThread]
        static void Main(string[] args) {
            if (!mutex.WaitOne(TimeSpan.Zero, true)) {
                // Ya esta en ejecucion, no duplicar procesos
                return;
            }

            try {
                string scriptPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ShokzAutoConnect.ps1");
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + scriptPath + "\"";
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;

                Process p = Process.Start(psi);
                p.WaitForExit();
            } catch { }
        }
    }
}
