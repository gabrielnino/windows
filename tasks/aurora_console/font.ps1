[CmdletBinding()]
param([switch]$Remove)
$ErrorActionPreference='Stop'
$key='HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$name='JetBrainsMonoNL Nerd Font Mono Regular (TrueType)'
$font=Join-Path $PSScriptRoot 'artifacts/fonts/JetBrainsMonoNLNerdFontMono-Regular.ttf'
$statePath=Join-Path $PSScriptRoot 'backups/font.json'
if (-not ('Aurora.FontApi' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace Aurora { public static class FontApi {
[DllImport("gdi32.dll",CharSet=CharSet.Unicode)] public static extern int AddFontResourceW(string path);
[DllImport("gdi32.dll",CharSet=CharSet.Unicode)] public static extern bool RemoveFontResourceW(string path);
[DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeoutW(IntPtr h,uint m,IntPtr w,IntPtr l,uint flags,uint timeout,out IntPtr result);
} }
'@
}
if ($Remove) {
    if (Test-Path $statePath) {
        $state=Get-Content $statePath -Raw | ConvertFrom-Json
        if ($state.Existed) { Set-ItemProperty $key $name $state.Value }
        else { Remove-ItemProperty $key $name -ErrorAction SilentlyContinue }
        [Aurora.FontApi]::RemoveFontResourceW($font) | Out-Null
    }
} else {
    New-Item -ItemType Directory -Force (Split-Path $font) | Out-Null
    if (-not (Test-Path $font)) {
        Invoke-WebRequest 'https://raw.githubusercontent.com/ryanoasis/nerd-fonts/33db50390a1b173e6f19ecc2119248d2ec166a11/patched-fonts/JetBrainsMono/NoLigatures/JetBrainsMonoNLNerdFontMono-Regular.ttf' -OutFile $font
        Invoke-WebRequest 'https://raw.githubusercontent.com/ryanoasis/nerd-fonts/33db50390a1b173e6f19ecc2119248d2ec166a11/patched-fonts/JetBrainsMono/NoLigatures/OFL.txt' -OutFile (Join-Path (Split-Path $font) 'OFL.txt')
    }
    if (-not (Test-Path $key)) { New-Item $key -Force | Out-Null }
    if (-not (Test-Path $statePath)) {
        $prior=(Get-ItemProperty $key).PSObject.Properties[$name].Value
        @{Existed=($null -ne $prior);Value=$prior;Font=$font} | ConvertTo-Json | Set-Content $statePath
    }
    Set-ItemProperty $key $name $font
    if ([Aurora.FontApi]::AddFontResourceW($font) -eq 0) { throw 'Font registration failed' }
}
$result=[IntPtr]::Zero
[Aurora.FontApi]::SendMessageTimeoutW([IntPtr]0xffff,0x001D,[IntPtr]::Zero,[IntPtr]::Zero,2,1000,[ref]$result) | Out-Null
