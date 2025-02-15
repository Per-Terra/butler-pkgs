[CmdletBinding()]
param (
  [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
  [Alias('FullName')]
  [string]$ManifestPath,
  [switch]$Force
)

begin {
  # 依存モジュールのインストール
  $scriptDependencies = @('7Zip4Powershell', 'powershell-yaml')
  foreach ($dependency in $scriptDependencies) {
    if (-not (Get-Module -Name $dependency -ListAvailable)) {
      try {
        Install-Module -Name $dependency -Force -Repository PSGallery -Scope CurrentUser
      }
      catch {
        throw "依存モジュールのインストールに失敗しました: $($_.Exception.Message)"
      }
    }
  }

  # モジュールのインポート
  Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath './modules/ConvertTo-ManifestYaml.psm1')
  Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath './modules/Get-WebFile.psm1')
  Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath './modules/Get-FileSHA256Hash.psm1')
  Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath './modules/Test-PackageManifest.psm1')

  # 初期化
  $ScriptVersion = '0.3.0'
  $ManifestVersion = '0.3.0'
  $WorkingDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'tmp'

  # 拡張子の定義
  $ArchiveExtensions = @('.zip', '.7z')
  $PluginExtensions = @('.exe', '.dll', '.auf', '.aui', '.auo', '.auc', '.aul', '.ini')
  $ScriptExtensions = @('.anm', '.obj', '.scn', '.cam', '.tra', '.lua')
  $ConfExtensions = @('.ini', '.stg', '.xml')

  function Get-FilesInArchive {
    param (
      [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
      [Alias('FullName')]
      [string]$ArchiveFileName,
      [Parameter(Mandatory)]
      [string]$TargetPath,
      [AllowNull()]
      [object]$PreviousFiles
    )

    Write-Host "アーカイブを展開しています: $ArchiveFileName"
    Expand-7Zip -ArchiveFileName $ArchiveFileName -TargetPath $TargetPath

    $files = Get-ChildItem -LiteralPath $TargetPath -Recurse -File
    $script:installedSize += ($files | Measure-Object -Property Length -Sum).Sum

    $filesInArchive = @()

    foreach ($fileInArchive in $files) {
      $relativePath = $fileInArchive.FullName.Replace($TargetPath, '').Replace('\', '/') -replace '^/', ''
      $file = @{
        Path   = $relativePath
        SHA256 = $fileInArchive | Get-FileSHA256Hash
      }

      if ($PreviousFiles) {
        $previousFile =  $PreviousFiles | Where-Object { $_.Path -eq $file.Path }
      }

      if ($previousFile) {
        if ($previousFile.Install) {
          $file.Add('Install', $previousFile.Install)
        }
        elseif ($previousFile.Files) {
          $file.Add('Files', ($fileInArchive | Get-FilesInArchive -TargetPath $expandPath -PreviousFiles $previousFile.Files))
        }
      }
      # hebiiro氏用の例外
      elseif ($Url.StartsWith('https://github.com/hebiiro/')) {
        if ($fileInArchive.Extension -in $PluginExtensions -or ($relativePath -match '/' -and ($fileInArchive.Extension -ne '.wav'))) {
          if ($fileInArchive.Extension -in $ConfExtensions -and -not ($relativePath -match '/Skin/')) {
            $file.Add('Install', @{
                TargetPath = ($relativePath -replace '^', 'plugins/')
                ConfFile   = $true
              })
          }
          else {
            $file.Add('Install', @{
                TargetPath = ($relativePath -replace '^', 'plugins/')
              })
          }
        }
      }
      # oov/aviutl_ffmpeg_input用の例外
      elseif ($Url.StartsWith('https://github.com/oov/aviutl_ffmpeg_input') -and $relativePath.StartsWith('ffmpeg64/')) {
        $file.Add('Install', @{
            TargetPath = $relativePath
          })
      }
      # oov/aviutl_gcmzdrops用の例外
      elseif ($Url.StartsWith('https://github.com/oov/aviutl_gcmzdrops') -and $relativePath.StartsWith('GCMZDrops/')) {
        $file.Add('Install', @{
            TargetPath = $relativePath
          })
      }
      # oov/PSDToolKit用の例外
      elseif ($Url.StartsWith('https://github.com/oov/aviutl_psdtoolkit')) {
        if ($relativePath.StartsWith('GCMZDrops/')) {
          # ignore
        }
        elseif ($relativePath.StartsWith('PSDToolKit/')) {
          $file.Add('Install', @{
              TargetPath = $relativePath
            })
        }
        elseif ($relativePath.StartsWith('PSDToolKitDocs/')) {
          # ignore
        }
        elseif ($relativePath.StartsWith('script/PSDToolKit')) {
          $file.Add('Install', @{
              TargetPath = $relativePath
            })
        }
        elseif ($relativePath.StartsWith('かんしくん')) {
          # ignore
        }
        else {
          if ($relativePath -eq 'PSDToolKit.auf') {
            $file.Add('Install', @{
                TargetPath = $relativePath
              })
          }
        }
      }
      # それらしいディレクトリに配置されている場合は尊重
      elseif ($relativePath -match '^(?:[^/]+/)?((?:plugins|script|exe_files)/.+)$') {
        if ($fileInArchive.Extension -in $ConfExtensions) {
          $file.Add('Install', @{
              TargetPath = $Matches[1]
              ConfFile   = $true
            })
        }
        else {
          $file.Add('Install', @{
              TargetPath = $Matches[1]
            })
        }
      }
      else {
        if ($fileInArchive.Extension -in $PluginExtensions) {
          if ($fileInArchive.Extension -in $ConfExtensions) {
            $file.Add('Install', @{
                TargetPath = ($relativePath -replace '^([^/]+/)*', 'plugins/')
                ConfFile   = $true
              })
          }
          else {
            $file.Add('Install', @{
                TargetPath = ($relativePath -replace '^([^/]+/)*', 'plugins/')
              })
          }
        }
        elseif ($fileInArchive.Extension -in $ScriptExtensions) {
          $file.Add('Install', @{
              TargetPath = ($relativePath -replace '^([^/]+/)*', 'script/')
            })
        }
        elseif ($fileInArchive.Extension -in $ConfExtensions) {
          $file.Add('Install', @{
              TargetPath = $relativePath
              ConfFile   = $true
            })
        }
        elseif ($fileInArchive.Extension -eq '.exa') {
          # サブディレクトリまで保持
          $path = $relativePath
          $path = $path -split '/'
          $path = if ($path[-2]) { $path[-2] + '/' + $path[-1] } else { $path[-1] }
          $file.Add('Install', @{
              TargetPath = $path
            })
        }
        elseif ($fileInArchive.Extension -in $ArchiveExtensions) {
          $expandDirectory = Join-Path -Path $fileInArchive.DirectoryName -ChildPath (Split-Path -Path $fileInArchive.FullName -LeafBase)
          if (Test-Path -LiteralPath $expandDirectory -PathType Container) {
            Remove-Item -LiteralPath $expandDirectory -Recurse -Force
          }
          $file.Add('Files', ($fileInArchive | Get-FilesInArchive -TargetPath $expandDirectory))
        }
        # exeファイルはコピー
        if ($file.Install -and (-not $file.Install.ConfFile) -and ($file.Install.TargetPath -match '\.exe$')) {
          $file.Install.Add('Method', 'Copy')
        }
      }

      # プラグインファイルの情報を取得
      if ($file.Install -and ($fileInArchive.Extension -in '.auf', '.aui', '.auo', '.auc')) {
        $pluginInfos = $fileInArchive | . (Join-Path -Path $PSScriptRoot -ChildPath './Get-PluginInfo.ps1')
        foreach ($pluginInfo in $pluginInfos) {
          $plugin = @{ Name = $pluginInfo.Name }
          if ($pluginInfo.Information) {
            $plugin.Add('Information', $pluginInfo.Information)
          }
          switch ($fileInArchive.Extension) {
            '.auf' { $plugin.Add('Type', 'Filter') }
            '.aui' { $plugin.Add('Type', 'Input') }
            '.auo' { $plugin.Add('Type', 'Output') }
            '.auc' { $plugin.Add('Type', 'Color') }
          }
          $plugin.Add('InstallPath', $file.Install.TargetPath)
          $script:plugins += $plugin
        }
      }

      $filesInArchive += $file
      Write-Progress -Activity 'アーカイブ内のファイルの情報を取得しています' -Status "処理中: $relativePath" -PercentComplete (($filesInArchive.Count / $files.Count) * 100)
    }

    Write-Progress -Activity 'アーカイブ内のファイルの情報を取得しています' -Completed
    $filesInArchive
  }

  function Get-SourceFile {
    param (
      [Parameter(Mandatory, ValueFromPipeline)]
      [string]$Url,
      [Parameter(Mandatory)]
      [string]$WorkingDirectory,
      [AllowNull()]
      [object]$PreviousFile
    )

    if ($Url -match 'https://drive.google.com/file/d/([^/]+)') {
      Write-Host "Google Drive のリンクを検出しました: $Url"
      $Url = "https://drive.google.com/uc?id=$($Matches[1])"
    }

    $sourceFile = Get-WebFile -Uri $Url -OutDirectory $WorkingDirectory -Force:$Force

    Write-Host "ファイルの情報を取得しています: $($sourceFile.FullName)"
    $file = @{
      SourceUrl = $Url
      SHA256    = $sourceFile | Get-FileSHA256Hash
    }
    if ($sourceFile.Name -ne (Split-Path -Path $Url -Leaf)) {
      $file.Add('FileName', $sourceFile.Name)
    }

    # if ($PreviousFile) {
    #   if ($PreviousFile.SHA256 -eq $file.SHA256) {
    #     throw "ファイルが変更されていません: $Url"
    #   }
    # }

    if ($sourceFile.Extension -in $ArchiveExtensions) {
      $expandDirectory = Join-Path -Path $sourceFile.DirectoryName -ChildPath (Split-Path -Path $sourceFile.FullName -LeafBase)
      if (Test-Path -LiteralPath $expandDirectory -PathType Container) {
        Remove-Item -LiteralPath $expandDirectory -Recurse -Force
      }
      $file.Add('Files', ($sourceFile | Get-FilesInArchive -TargetPath $expandDirectory -PreviousFiles $PreviousFile.Files))
    }
    else {
      $script:installedSize += $sourceFile.Length
      if ($PreviousFile.Install) {
        $file.Add('Install', $PreviousFile.Install)
      }
      elseif ($sourceFile.Extension -in $PluginExtensions) {
        $file.Add('Install', @{
            TargetPath = ($sourceFile.Name -replace '^', 'plugins/')
          })
      }
      elseif ($sourceFile.Extension -in $ScriptExtensions) {
        $file.Add('Install', @{
            TargetPath = ($sourceFile.Name -replace '^', 'script/')
          })
      }
      elseif ($sourceFile.Extension -in $ConfExtensions) {
        $file.Add('Install', @{
            TargetPath = $sourceFile.Name
            ConfFile   = $true
          })
      }
      else {
        $file.Add('Install', @{
            TargetPath = $sourceFile.Name
          })
      }
      # exeファイルはコピー
      if ($file.Install -and (-not $file.Install.ConfFile) -and ($file.Install.TargetPath -match '.exe$')) {
        $file.Install.Add('Method', 'Copy')
      }
      # プラグインファイルの情報を取得
      if ($sourceFile.Extension -in '.auf', '.aui', '.auo', '.auc') {
        $pluginInfos = $sourceFile | . (Join-Path -Path $PSScriptRoot -ChildPath './Get-PluginInfo.ps1')
        foreach ($pluginInfo in $pluginInfos) {
          $plugin = @{ Name = $pluginInfo.Name }
          if ($pluginInfo.Information) {
            $plugin.Add('Information', $pluginInfo.Information)
          }
          switch ($sourceFile.Extension) {
            '.auf' { $plugin.Add('Type', 'Filter') }
            '.aui' { $plugin.Add('Type', 'Input') }
            '.auo' { $plugin.Add('Type', 'Output') }
            '.auc' { $plugin.Add('Type', 'Color') }
          }
          $plugin.Add('InstallPath', $file.Install.TargetPath)
          $script:plugins += $plugin
        }
      }
    }

    $file
  }
}

process {
  if (-not (Test-Path -Path $ManifestPath -PathType Leaf)) {
    throw "マニフェストファイルが見つかりません: $ManifestPath"
  }

  try {
    $oldManifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Yaml
  }
  catch {
    throw "マニフェストファイルの読み込みに失敗しました: $($_.Exception.Message)"
  }

  [ulong]$script:installedSize = 0
  $newFiles = @()
  $script:plugins = @()

  foreach ($oldFile in $oldManifest.Files) {
    $newFiles += $oldFile.SourceUrl | Get-SourceFile -WorkingDirectory $WorkingDirectory -PreviousFile $oldFile
  }

  $newManifest = [ordered]@{
    Identifier      = [string]$oldManifest.Identifier
    DisplayName     = [string]$oldManifest.DisplayName
    Version         = [string]$oldManifest.Version
    ReleaseDate     = [string]$oldManifest.ReleaseDate
    Section         = [string]$oldManifest.Section
    Architecture    = [string]$oldManifest.Architecture
    Depends         = [string[]]$oldManifest.Depends
    Recommends      = [string[]]$oldManifest.Recommends
    Suggests        = [string[]]$oldManifest.Suggests
    Enhances        = [string[]]$oldManifest.Enhances
    Breaks          = [string[]]$oldManifest.Breaks
    Conflicts       = [string[]]$oldManifest.Conflicts
    Provides        = [string[]]$oldManifest.Provides
    Replaces        = [string[]]$oldManifest.Replaces
    InstalledSize   = [ulong]$script:installedSize
    Developer       = [string[]]$oldManifest.Developer
    Description     = [string]$oldManifest.Description
    Website         = [string[]]$oldManifest.Website
    Files           = @($newFiles)
    ConfFiles       = @($oldManifest.ConfFiles)
    Plugins         = @($script:plugins)
    ManifestVersion = [string]$ManifestVersion
  }

  foreach ($field in [array]$newManifest.Keys) {
    if ([string]::IsNullOrEmpty($newManifest[$field])) {
      $newManifest.Remove($field)
    }
  }

  if (-not (Test-PackageManifest -Manifest $newManifest)) {
    throw "マニフェストファイルの検証に失敗しました"
  }

  $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath "../manifests/$($newManifest['Developer'][0])/$($newManifest.Identifier)/$($newManifest.Version).yaml"
  Write-Host "マニフェストを作成しています: $manifestPath"

  $Header = @"
# Created using UpdateManifest.ps1 v$ScriptVersion
# yaml-language-server: `$schema=https://raw.githubusercontent.com/Per-Terra/butler-pkgs/main/schemas/JSON/manifest/$ManifestVersion.json

"@

  try {
  ($newManifest | ConvertTo-ManifestYaml -Header $Header) -replace "`r`n", "`n" |
      Out-File -FilePath $manifestPath -Encoding utf8NoBOM -Force -NoNewline
  }
  catch {
    Write-Error "マニフェストの作成に失敗しました: $($_.Exception.Message)"
    exit 1
  }
}
