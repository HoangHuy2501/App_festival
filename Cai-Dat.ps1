$ErrorActionPreference = 'Stop'
$stage = $null
try {
    Add-Type -AssemblyName System.Windows.Forms
    $source = Join-Path $PSScriptRoot 'ung-dung'
    $destination = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'DemNguocTet'
    $stage = Join-Path ([IO.Path]::GetTempPath()) ('DemNguocTet-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    $generated = Join-Path $stage 'DemNguocTet.exe'
    $compiler = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
    if (-not [IO.File]::Exists($compiler)) {
        throw 'Thiếu trình biên dịch .NET Framework của Windows.'
    }

    $code = Join-Path $source 'TrinhMo.cs'
    $systemAssembly = [System.Diagnostics.Process].Assembly.Location
    $formsAssembly = [System.Windows.Forms.MessageBox].Assembly.Location
    $compilerFlags = '/nologo /noconfig /target:winexe /platform:anycpu /optimize+'
    $references = '/reference:"{0}" /reference:"{1}"' -f $systemAssembly, $formsAssembly
    $paths = '/out:"{0}" "{1}"' -f $generated, $code
    $arguments = "$compilerFlags $references $paths"
    $compilerOptions = [Diagnostics.ProcessStartInfo]::new($compiler, $arguments)
    $compilerOptions.UseShellExecute = $false
    $compilerOptions.CreateNoWindow = $true
    $compilerOptions.RedirectStandardOutput = $true
    $compilerOptions.WorkingDirectory = Split-Path -Parent $compiler
    $build = [Diagnostics.Process]::Start($compilerOptions)
    try {
        $details = $build.StandardOutput.ReadToEnd()
        $build.WaitForExit()
        if ($build.ExitCode -ne 0 -or -not [IO.File]::Exists($generated)) {
            throw "Không tạo được ứng dụng. $details"
        }
    } finally {
        $build.Dispose()
    }

    [void][IO.Directory]::CreateDirectory($destination)
    foreach ($name in @('DemNguocTet.ps1', 'Widget.xaml', 'Lich-Ngay-Le.csv', 'Lich-Ngay-Le.xaml')) {
        $file = [IO.File]::ReadAllBytes((Join-Path $source $name))
        [IO.File]::WriteAllBytes((Join-Path $destination $name), $file)
    }
    $target = Join-Path $destination 'DemNguocTet.exe'
    [IO.File]::WriteAllBytes($target, [IO.File]::ReadAllBytes($generated))

    [void][Diagnostics.Process]::Start($target)

    $saved = @()
    try {
        $shell = New-Object -ComObject WScript.Shell
        $locations = [ordered]@{
            'Desktop' = [Environment]::GetFolderPath('DesktopDirectory')
            'menu Start' = [Environment]::GetFolderPath('Programs')
        }
        foreach ($location in $locations.Keys) {
            try {
                $folder = $locations[$location]
                if ([string]::IsNullOrWhiteSpace($folder)) { continue }
                [void][IO.Directory]::CreateDirectory($folder)
                $shortcutPath = Join-Path $folder 'DemNguocTet.lnk'
                $shortcut = $shell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath = $target
                $shortcut.WorkingDirectory = $destination
                $shortcut.Description = 'Widget dem nguoc ngay le'
                $shortcut.Save()
                $saved += $location
            } catch {
                Write-Warning $_.Exception.Message
            }
        }
    } catch {
        Write-Warning $_.Exception.Message
    }

    $message = if ($saved.Count -gt 0) {
        'Đã cài widget. Mở lại bằng lối tắt DemNguocTet ở ' + ($saved -join ' và ') + '.'
    } else {
        "Đã cài widget. Windows không tạo được lối tắt. Để mở lại, nhấn Windows + R và nhập:`n%LOCALAPPDATA%\DemNguocTet\DemNguocTet.exe"
    }
    [void][Windows.Forms.MessageBox]::Show($message, 'Đếm ngược Tết', 'OK', 'Information')

} catch {
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Không thể cài Đếm ngược Tết', 'OK', 'Error')
    exit 1
} finally {
    if ($null -ne $stage -and [IO.Directory]::Exists($stage)) {
        Remove-Item -LiteralPath $stage -Force -Recurse -ErrorAction SilentlyContinue
    }
}
