Option Explicit
Dim shell, files, folder, setup, powershell, command
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
folder = files.GetParentFolderName(WScript.ScriptFullName)
setup = files.BuildPath(folder, "Cai-Dat.ps1")
powershell = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
If Not files.FileExists(setup) Then
    MsgBox "Giai nen toan bo ZIP truoc khi chay Cai-Dat.vbs.", vbExclamation, "Dem nguoc Tet"
    WScript.Quit 1
End If
command = """" & powershell & """ -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File """ & setup & """"
shell.Run command, 0, True
