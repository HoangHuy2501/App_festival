using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class WidgetLauncher
{
    [STAThread]
    private static void Main()
    {
        try
        {
            string folder = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(folder, "DemNguocTet.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("Thiếu tệp của widget. Hãy chạy lại Cai-Dat.vbs.");

            string powerShell = Path.Combine(Environment.SystemDirectory,
                @"WindowsPowerShell\v1.0\powershell.exe");
            var options = new ProcessStartInfo(powerShell,
                "-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File \"" + script + "\"");
            options.UseShellExecute = false;
            options.CreateNoWindow = true;
            options.WorkingDirectory = folder;

            using (Process widget = Process.Start(options))
            {
                widget.WaitForExit();
                if (widget.ExitCode != 0)
                    throw new InvalidOperationException("Windows PowerShell trả mã " + widget.ExitCode + ".");
            }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Đếm ngược Tết", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
