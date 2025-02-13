<#
  Get-PluginInfo.ps1

  AviUtlのプラグインファイルから、プラグインの name と information を取得します。
  フィルタプラグインの場合、information が null であることがあります。

  引数
    [string]$TargetFile
      対象となる(フィルタ|入力|出力|色変換)プラグインファイルへのパスを指定します。
    [switch]$RetAsJson
      結果をJSON形式の文字列として返すようにします。

  戻り値
    @(@{ [string]Name; [string]Information }, ...)
    ここで Name と Information とは、プラグイン構造体の name と information の内容です。

    $TargetFile がプラグインファイルとして無効であった場合は、代わりに $null を返します。

    $RetAsJson が指定された場合は、これらを ConvertTo-Json で変換したものを返します。
    これは ConvertFrom-Json で PSObject に復元できます。


  Copyright (c) 2024 ePi
  License: MIT; See below
#>

#Requires -Version 5
using namespace System
using namespace System.IO
using namespace System.Diagnostics
using namespace System.Threading.Tasks
using namespace System.Runtime.InteropServices

[CmdletBinding()]
param(
  [Parameter(Mandatory, ValueFromPipeline)]
  [string]$TargetFile,
  [Parameter()]
  [switch]$RetAsJson
)

if ([Environment]::Is64BitProcess) {
  function Invoke-32bitPowerShell {
    [CmdletBinding()]
    param (
      [Parameter(Mandatory)]
      [string]$Path,
      [Parameter()]
      [string[]]$ArgumentList
    )
    $process = [Process]::new()
    if ($process -ne $null) {
      try {
        $si = $process.StartInfo
        $si.FileName = "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
        $si.Arguments = @('-ExecutionPolicy', 'Bypass', '-NonInteractive', '-File', $Path) + $ArgumentList
        $si.UseShellExecute = $false
        $si.CreateNoWindow = $true
        $si.UseShellExecute = $false
        $si.RedirectStandardOutput = $true
        $si.RedirectStandardError = $true

        $null= $process.Start()
        $taskStdOut = $process.StandardOutput.ReadToEndAsync()
        $taskStdErr = $process.StandardError.ReadToEndAsync()
        $null= $process.WaitForExit()

        [Task]::WaitAll($taskStdOut, $taskStdErr)

        return [PSCustomObject]@{
          ExitCode = $process.ExitCode
          StdOut = $taskStdOut.Result
          StdErr = $taskStdErr.Result
        }
      }
      finally {
        $process.Close()
      }
    }
  }

  $ret = Invoke-32bitPowerShell -Path $MyInvocation.MyCommand.Path -ArgumentList '-TargetFile', $TargetFile, '-RetAsJson'
  if ($ret.StdErr.Length -gt 0) {
    Write-Error $ret.StdErr
  }
  if ($ret.ExitCode -ne 0) { exit $ret.ExitCode }
  if ($RetAsJson) {
    $ret.StdOut
  }
  else {
    ConvertFrom-Json $ret.StdOut
  }
  return
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace BUtler {
  public class GetPluginInfo {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    public static extern IntPtr LoadLibrary(string lpFileName);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi, ExactSpelling = true)]
    public static extern IntPtr GetProcAddress(IntPtr hModule, string procedureName);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool FreeLibrary(IntPtr hModule);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    public delegate IntPtr AviUtlGetPluginTableDelegate();
  }
}
'@ -Language CSharp -ErrorAction Stop

filter LoadInfo {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)]
    [hashtable]$Offset,
    [Parameter(Mandatory, ValueFromPipeline)]
    [IntPtr]$Plugin
  )

  $name = [Marshal]::PtrToStringAnsi([Marshal]::ReadIntPtr($Plugin, $Offset.Name))
  if ($Offset.InformationCondition) {
    $flag = [Marshal]::ReadInt32($Plugin + $Offset.InformationCondition.Flag)
    if (($flag -band $Offset.InformationCondition.FlagMask) -eq 0) {
      return [PSCustomObject]@{ Name = $name; Information = $null }
    }
  }
  $info = [Marshal]::PtrToStringAnsi([Marshal]::ReadIntPtr($Plugin, $Offset.Information))
  return [PSCustomObject]@{ Name = $name; Information = $info }
}

function GetPluginTable {
  param(
    [Parameter(Mandatory)]
    [IntPtr]$Module,
    [Parameter(Mandatory)]
    [hashtable]$ProcName
  )

  if ($ProcName.Multi) {
    $proc = [BUtler.GetPluginInfo]::GetProcAddress($Module, $ProcName.Multi)
    if ($proc -ne [IntPtr]::Zero) {
      $plugins = [Marshal]::GetDelegateForFunctionPointer($proc, [BUtler.GetPluginInfo+AviUtlGetPluginTableDelegate]).Invoke()

      $ret = @()
      $i = 0
      while ($true) {
        $plugin = [Marshal]::ReadIntPtr($plugins, $i * 4)
        if ($plugin -eq [IntPtr]::Zero) { break }
        $ret += $plugin
        $i++
      }
      return $ret
    }
  }

  $proc = [BUtler.GetPluginInfo]::GetProcAddress($Module, $ProcName.Single)
  if ($proc -eq [IntPtr]::Zero) { return $null }

  $plugin = [Marshal]::GetDelegateForFunctionPointer($proc, [BUtler.GetPluginInfo+AviUtlGetPluginTableDelegate]).Invoke()

  return @($plugin)
}

function GetPluginInfo {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [string]$TargetFile
  )

  $mod = [BUtler.GetPluginInfo]::LoadLibrary($TargetFile)
  if ($mod -eq [IntPtr]::Zero) { return $null }
  try {
    switch ([Path]::GetExtension($TargetFile)) {
      '.auf' {
        $prm = @{
          ProcName = @{ Single = 'GetFilterTable'; Multi = 'GetFilterTableList' }
          Offset = @{ Name = 12; Information = 84; InformationCondition = @{ Flag = 0; FlagMask = 1 -shl 18 } }
        }
      }
      '.auo' {
        $prm = @{
          ProcName = @{ Single = 'GetOutputPluginTable'}
          Offset = @{ Name = 4; Information = 12 }
        }
      }
      '.aui' {
        $prm = @{
          ProcName = @{ Single = 'GetInputPluginTable' }
          Offset = @{ Name = 4; Information = 12 }
        }
      }
      '.auc' {
        $prm = @{
          ProcName = @{ Single = 'GetColorPluginTable' }
          Offset = @{ Name = 4; Information = 8 }
        }
      }
      default { return $null }
    }

    $plugins = GetPluginTable $mod $prm.ProcName
    if ($null -eq $plugins) { return $null }
    return $plugins | LoadInfo $prm.Offset
  }
  finally {
    $null= [BUtler.GetPluginInfo]::FreeLibrary($mod)
  }
}

$ret = GetPluginInfo $TargetFile
if ($RetAsJson) {
  ConvertTo-Json $ret -Compress
}
else {
  $ret
}

<#
Copyright (c) 2024 ePi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>
