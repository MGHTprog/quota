using System;
using System.Threading;
using System.Windows.Forms;
using System.Net;

namespace Quota.Windows
{
    internal static class Program
    {
        private const string MutexName = "Quota.Windows.SingleInstance";

        [STAThread]
        private static void Main()
        {
            // .NET Framework applications can inherit legacy Schannel defaults
            // on some Windows installations. Xiaomi's console requires modern TLS.
            AppContext.SetSwitch("Switch.System.Net.DontEnableSchUseStrongCrypto", false);
            AppContext.SetSwitch("Switch.System.Net.DontEnableSystemDefaultTlsVersions", false);
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            ServicePointManager.DefaultConnectionLimit = 10;

            bool created;
            using (var mutex = new Mutex(true, MutexName, out created))
            {
                if (!created)
                {
                    MessageBox.Show("Quota 已在运行。", "Quota", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new MainForm());
            }
        }
    }
}
