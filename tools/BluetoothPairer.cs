using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Windows.Devices.Enumeration;
using Windows.Devices.Bluetooth;

namespace BluetoothTool
{
    class Program
    {
        static AutoResetEvent doneEvent = new AutoResetEvent(false);

        static void Main(string[] args)
        {
            Console.WriteLine("=== BLUETOOTH SCANNER & AUTO-PAIRER ===");
            Console.WriteLine("Searching for Shokz / OpenRun / Bluetooth audio devices in pairing mode...");

            string aqs = "System.Devices.Aep.ProtocolId:=\"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\"";
            var requestedProperties = new List<string> {
                "System.Devices.Aep.DeviceAddress",
                "System.Devices.Aep.IsConnected",
                "System.Devices.Aep.CanPair",
                "System.Devices.Aep.IsPaired"
            };

            var watcher = DeviceInformation.CreateWatcher(
                aqs,
                requestedProperties,
                DeviceInformationKind.AssociationEndpoint
            );

            watcher.Added += (w, info) =>
            {
                if (!string.IsNullOrEmpty(info.Name))
                {
                    Console.WriteLine(string.Format("[DISCOVERED] {0} (CanPair: {1}, IsPaired: {2})", info.Name, info.Pairing.CanPair, info.Pairing.IsPaired));
                    
                    string lowerName = info.Name.ToLower();
                    if (lowerName.Contains("shokz") || 
                        lowerName.Contains("openrun") || 
                        lowerName.Contains("aftershokz") || 
                        lowerName.Contains("opencomm") || 
                        lowerName.Contains("openfit") ||
                        lowerName.Contains("headphone") ||
                        lowerName.Contains("audio"))
                    {
                        Console.WriteLine(string.Format("\n>>> MATCH FOUND: '{0}'! Starting pairing process...", info.Name));
                        PairDevice(info);
                    }
                }
            };

            watcher.Updated += (w, update) => { };
            watcher.EnumerationCompleted += (w, obj) => {
                Console.WriteLine("[INFO] Device discovery cycle active...");
            };

            watcher.Start();

            // Wait 20 seconds for pairing to complete
            doneEvent.WaitOne(20000);
            watcher.Stop();
            Console.WriteLine("\n[INFO] Bluetooth scan ended.");
        }

        static async void PairDevice(DeviceInformation info)
        {
            try
            {
                var customPairing = info.Pairing.Custom;
                if (customPairing != null)
                {
                    customPairing.PairingRequested += (sender, args) =>
                    {
                        Console.WriteLine(string.Format("[PAIRING] Accepting pairing request (Type: {0})...", args.PairingKind));
                        args.Accept();
                    };
                }

                var result = await info.Pairing.PairAsync(DevicePairingProtectionLevel.None);
                Console.WriteLine("\n**************************************************");
                Console.WriteLine(string.Format("PAIRING RESULT FOR '{0}': {1}", info.Name, result.Status));
                Console.WriteLine("**************************************************\n");

                if (result.Status == DevicePairingResultStatus.Paired || result.Status == DevicePairingResultStatus.AlreadyPaired)
                {
                    Console.WriteLine(string.Format("SUCCESS: '{0}' is now connected and paired with Windows!", info.Name));
                    doneEvent.Set();
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine(string.Format("Pairing Exception: {0}", ex.Message));
            }
        }
    }
}
