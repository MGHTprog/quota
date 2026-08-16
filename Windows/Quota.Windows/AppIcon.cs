using System.Drawing;
using System.Windows.Forms;

namespace Quota.Windows
{
    internal static class AppIcon
    {
        public static Icon Load()
        {
            try
            {
                var extracted = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
                if (extracted != null)
                {
                    using (extracted) return (Icon)extracted.Clone();
                }
            }
            catch { }
            return (Icon)SystemIcons.Application.Clone();
        }
    }
}
