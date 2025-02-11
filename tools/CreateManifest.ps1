[CmdletBinding()]
param (
  [switch]$Update,
  [string[]]$SourceUrl,
  [string]$Identifier,
  [AllowEmptyString()]
  [string]$DisplayName,
  [string]$Version,
  [AllowEmptyString()]
  [string]$ReleaseDate,
  [string]$Section,
  [string]$Architecture,
  [string[]]$Depends,
  [string[]]$Recommends,
  [string[]]$Suggests,
  [string[]]$Enhances,
  [string[]]$Breaks,
  [string[]]$Conflicts,
  [string[]]$Provides,
  [string[]]$Replaces,
  [string[]]$Developer,
  [string]$Description,
  [AllowEmptyString()]
  [string[]]$Website,
  [string[]]$ConfFiles,
  [switch]$SkipPrompt,
  [switch]$Force
)

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

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath './modules/ConvertTo-ManifestYaml.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath './modules/Get-WebFile.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath './modules/Get-FileSHA256Hash.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath './modules/Test-PackageManifest.psm1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath './modules/Test-Url.psm1')

$ScriptVersion = '0.3.0'
$ManifestVersion = '0.3.0'
$WorkingDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'tmp'

$ArchiveExtensions = @('.zip', '.7z')
$PluginExtensions = @('.exe', '.dll', '.auf', '.aui', '.auo', '.auc', '.aul', '.ini')
$ScriptExtensions = @('.anm', '.obj', '.scn', '.cam', '.tra', '.lua')
$ConfExtensions = @('.ini', '.stg', '.xml')

function Get-FilesInArchive {
  param (
    [Parameter(Mandatory, ValueFromPipeline)]
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

  Write-Host "アーカイブ内のファイルの情報を取得しています: $ArchiveFileName"
  $files | ForEach-Object {
    $relativePath = $_.FullName.Replace($TargetPath, '').Replace('\', '/') -replace '^/', ''
    $file = @{
      Path   = $relativePath
      SHA256 = Get-FileSHA256Hash -Path $_.FullName
    }

    if ($PreviousFiles) {
      $previousFile = $previousFiles | Where-Object { $_.Path -eq $file.Path }
    }

    if ($PreviousFile) {
      if ($PreviousFile.Install) {
        $file.Add('Install', $previousFile.Install)
      }
      elseif ($PreviousFile.Files) {
        $file.Add('Files', ($_.FullName | Get-FilesInArchive -TargetPath $expandPath -PreviousFiles $previousFile.Files))
      }
    }
    # hebiiro氏用の例外
    elseif ($Url.StartsWith('https://github.com/hebiiro/')) {
      if ($_.Extension -in $PluginExtensions -or ($relativePath -match '/' -and ($_.Extension -ne '.wav'))) {
        if ($_.Extension -in $ConfExtensions -and -not ($relativePath -match '/Skin/')) {
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
        # do nothing
      }
      elseif ($relativePath.StartsWith('PSDToolKit/')) {
        $file.Add('Install', @{
            TargetPath = $relativePath
          })
      }
      elseif ($relativePath.StartsWith('PSDToolKitDocs/')) {
        # do nothing
      }
      elseif ($relativePath.StartsWith('script/PSDToolKit')) {
        $file.Add('Install', @{
            TargetPath = $relativePath
          })
      }
      elseif ($relativePath.StartsWith('かんしくん')) {
        # do nothing
      }
      else {
        if ($relativePath -eq 'PSDToolKit.auf') {
          $file.Add('Install', @{
              TargetPath = $relativePath
            })
        }
      }
    }
    elseif ($relativePath -match '^(?:[^/]+/)?((?:plugins|script|exe_files)/.+)$') {
      if ($_.Extension -in $ConfExtensions) {
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
      if ($_.Extension -in $PluginExtensions) {
        if ($_.Extension -in $ConfExtensions) {
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
      elseif ($_.Extension -in $ScriptExtensions) {
        $file.Add('Install', @{
            TargetPath = ($relativePath -replace '^([^/]+/)*', 'script/')
          })
      }
      elseif ($_.Extension -in $ConfExtensions) {
        $file.Add('Install', @{
            TargetPath = $relativePath
            ConfFile   = $true
          })
      }
      elseif ($_.Extension -eq '.exa') {
        # サブディレクトリまで保持
        $path = $relativePath
        $path = $path -split '/'
        $path = if ($path[-2]) { $path[-2] + '/' + $path[-1] } else { $path[-1] }
        $file.Add('Install', @{
            TargetPath = $path
          })
      }
      elseif ($_.Extention -in $ArchiveExtensions) {
        $expandDirectory = Join-Path -Path (Split-Path -Path $_.FullName -Parent) -ChildPath (Split-Path -Path $_.FullName -LeafBase)
        if (Test-Path -LiteralPath $expandDirectory -PathType Container) {
          Remove-Item -LiteralPath $expandDirectory -Recurse -Force
        }
        $file.Add('Files', ($_.FullName | Get-FilesInArchive -TargetPath $expandDir))
      }
      if ($file.Install -and (-not $file.Install.ConfFile) -and ($file.Install.TargetPath -match '\.exe$')) {
        $file.Install.Add('Method', 'Copy')
      }
    }

    $filesInArchive += $file
  }

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

  $filePath = Get-WebFile -Uri $Url -OutDirectory $WorkingDirectory -Force:$Force
  $fileName = Split-Path -Path $filePath -Leaf

  Write-Host "ファイルの情報を取得しています: $filePath"
  $file = @{
    SourceUrl = $Url
    SHA256    = Get-FileSHA256Hash -Path $filePath
  }
  if ($fileName -ne (Split-Path -Path $Url -Leaf)) {
    $file.Add('FileName', $fileName)
  }

  if ($previousFile) {
    if ($previousFile.SHA256 -eq $file.SHA256) {
      throw "ファイルが変更されていません: $Url"
    }
  }

  $fileExtension = Split-Path -Path $filePath -Extension

  if ($fileExtension -in $ArchiveExtensions) {
    $expandDirectory = Join-Path -Path (Split-Path -Path $filePath -Parent) -ChildPath (Split-Path -Path $filePath -LeafBase)
    if (Test-Path -LiteralPath $expandDirectory -PathType Container) {
      Remove-Item -LiteralPath $expandDirectory -Recurse -Force
    }
    $file.Add('Files', ($filePath | Get-FilesInArchive -TargetPath $expandDirectory -PreviousFiles $previousFile.Files))
  }
  else {
    $script:installedSize += (Get-Item -LiteralPath $filePath).Length
    if ($previousFile.Install) {
      $file.Add('Install', $previousFile.Install)
    }
    elseif ($fileExtension -in $PluginExtensions) {
      $file.Add('Install', @{
          TargetPath = ($fileName -replace '^', 'plugins/')
        })
    }
    elseif ($fileExtension -in $ScriptExtensions) {
      $file.Add('Install', @{
          TargetPath = ($fileName -replace '^', 'script/')
        })
    }
    elseif ($fileExtension -in $ConfExtensions) {
      $file.Add('Install', @{
          TargetPath = $fileName
          ConfFile   = $true
        })
    }
    else {
      $file.Add('Install', @{
          TargetPath = $fileName
        })
    }
    if ($file.Install -and (-not $file.Install.ConfFile) -and ($file.Install.TargetPath -match '.exe$')) {
      $file.Install.Add('Method', 'Copy')
    }
  }

  $file
}

if (-not $SkipPrompt -and -not $Update) {
  $Update = $Host.UI.PromptForChoice(
    '確認',
    '既存のパッケージの情報を引き継ぎますか?',
    (
      @('&Yes', 'はい'),
      @('&No', 'いいえ')
      | ForEach-Object { New-Object -TypeName System.Management.Automation.Host.ChoiceDescription -ArgumentList $_ }
    ),
    0) -eq 0
}

if ($Update) {
  if ([string]::IsNullOrEmpty($Identifier) -or [string]::IsNullOrEmpty($Developer)) {
    do {
      $package = Read-Host -Prompt '更新するパッケージを Developer/Identifier の形式で入力してください'
    } while ([string]::IsNullOrEmpty($package))
    $manifestsDirectory = Join-Path -Path $PSScriptRoot -ChildPath "../manifests/$($package.Split('/')[0])/$($package.Split('/')[1])"
  }
  else {
    $manifestsDirectory = Join-Path -Path $PSScriptRoot -ChildPath "../manifests/$($Developer)/$($Identifier)"
  }

  if (-not (Test-Path -LiteralPath $manifestsDirectory -PathType Container)) {
    throw "マニフェストが見つかりません: $manifestsDir"
  }

  $manifests = Get-ChildItem -LiteralPath $manifestsDirectory -Filter '*.yaml' -Recurse -File | ForEach-Object {
    Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Yaml
  }

  if ($manifests.Count -eq 0) {
    throw "マニフェストが見つかりません: $manifestsDir"
  }

  # 最新のマニフェストを取得
  $manifest = $manifests | Sort-Object -Property @{
    # Version でソート
    Expression = {
      if ($null -ne $_.Version) {
        $_.Version
      }
      else {
        ''
      }
    }
    Descending = $true
  }, @{
    # ReleaseDate でソート
    Expression = {
      if ($null -ne $_.ReleaseDate) {
        [datetime]::ParseExact($_.ReleaseDate, 'yyyy-MM-dd', $null)
      }
      else {
        [datetime]::MinValue
      }
    }
    Descending = $true
  } | Select-Object -First 1

  $Identifier = $manifest.Identifier
  $DisplayName = $manifest.DisplayName
  $Section = $manifest.Section
  $Architecture = $manifest.Architecture
  $Depends = $manifest.Depends
  $Recommends = $manifest.Recommends
  $Suggests = $manifest.Suggests
  $Enhances = $manifest.Enhances
  $Breaks = $manifest.Breaks
  $Conflicts = $manifest.Conflicts
  $Provides = $manifest.Provides
  $Replaces = $manifest.Replaces
  $Developer = $manifest.Developer
  $Description = $manifest.Description
  $Website = $manifest.Website
  $previousFiles = @($manifest.Files)
  $ConfFiles = $manifest.ConfFiles
}

$sourceUrls = @()

if ([string]::IsNullOrEmpty($SourceUrl)) {
  do {
    Write-Host '[任意] ' -NoNewline
    $urls = Read-Host -Prompt 'ソースファイルのURLを入力してください (複数入力する場合はカンマで区切ってください)'
    $sourceUrls = $urls -split ','
    $isValid = $true
    foreach ($url in $sourceUrls) {
      $isValid = $isValid -and (Test-Url -Url $url)
    }
  } until ($isValid)
}
else {
  foreach ($url in $SourceUrl) {
    if (-not (Test-Url -Url $url)) {
      throw "URLの形式が正しくありません: $url"
    }
  }
}

[ulong]$script:installedSize = 0
$files = @()

if ($previousFiles) {
  for ($index = 0; $index -lt $sourceUrls.Count; $index++) {
    $files += $sourceUrls[$index] | Get-SourceFile -WorkingDirectory $WorkingDirectory -PreviousFile $previousFiles[$index]
  }
}
else {
  $sourceUrls | ForEach-Object {
    $files += $_ | Get-SourceFile -WorkingDirectory $WorkingDirectory
  }
}

$manifest = [ordered]@{
  Identifier      = [string]$Identifier
  DisplayName     = [string]$DisplayName
  Version         = [string]$Version
  ReleaseDate     = [string]$ReleaseDate
  Section         = [string]$Section
  Architecture    = [string]$Architecture
  Depends         = [string[]]$Depends
  Recommends      = [string[]]$Recommends
  Suggests        = [string[]]$Suggests
  Enhances        = [string[]]$Enhances
  Breaks          = [string[]]$Breaks
  Conflicts       = [string[]]$Conflicts
  Provides        = [string[]]$Provides
  Replaces        = [string[]]$Replaces
  InstalledSize   = [ulong]$script:installedSize
  Developer       = [string[]]$Developer
  Description     = [string]$Description
  Website         = [string[]]$Website
  Files           = @($files)
  ConfFiles       = @($ConfFiles)
  ManifestVersion = [string]$ManifestVersion
}

# Collection was modified; enumeration operation may not execute. というエラーが出るので、
# array にキャストしてから foreach で回す
foreach ($field in [array]$manifest.Keys) {
  if ([string]::IsNullOrEmpty($manifest[$field])) {
    $value = $null
    if ($field -eq 'Description') {
      Write-Host "'Description' はマニフェストの作成後に手動で編集してください"
      $manifest[$field] = "<enter description here>`n<enter description here>"
      continue
    }
    elseif ($field -eq 'ConfFiles') {
      continue
    }
    if ($Schema.required -contains $field) {
      if ($SkipPrompt) {
        throw "'$field' は必須項目です"
      }
      if ($Schema.properties.$field.type -eq 'array') {
        do {
          Write-Host -ForegroundColor Yellow -NoNewline '[必須] '
          $value = Read-Host -Prompt "'$field' を入力してください (複数入力する場合はカンマで区切ってください)"
          $value = $value -split ','
          $isValid = $true
          foreach ($item in $value) {
            if (-not (Test-PackageManifest -Field $field -Value $item)) {
              $isValid = $false
            }
          }
        } until ($value -and $isValid)
      }
      else {
        do {
          Write-Host -ForegroundColor Yellow -NoNewline '[必須] '
          $value = Read-Host -Prompt "'$field' を入力してください"
        } until ($value -and (Test-PackageManifest -Field $field -Value $value))
      }
    }
    elseif (-not $SkipPrompt) {
      if ($Schema.properties.$field.type -eq 'array') {
        do {
          Write-Host -NoNewline '[任意] '
          $value = Read-Host -Prompt "'$field' を入力してください (複数入力する場合はカンマで区切ってください)"
          $value = $value -split ','
          $isValid = $true
          foreach ($item in $value) {
            if (-not (Test-PackageManifest -Field $field -Value $item)) {
              $isValid = $false
            }
          }
        } until ($isValid)
      }
      else {
        do {
          Write-Host -NoNewline '[任意] '
          $value = Read-Host -Prompt "'$field' を入力してください"
        } until ((Test-PackageManifest -Field $field -Value $value))
      }
    }
    if ($value) {
      if ($Schema.properties.$field.type -eq 'array') {
        $manifest[$field] = @($value)
      }
      else {
        $manifest[$field] = $value
      }
    }
    else {
      $manifest.Remove($field)
    }
  }
}

if (-not (Test-PackageManifest -Manifest $manifest)) {
  throw 'パッケージマニフェストの検証に失敗しました'
}

$manifestPath = Join-Path -Path $PSScriptRoot -ChildPath "../manifests/$($manifest['Developer'][0])/$($manifest.Identifier)/$($manifest.Version).yaml"
if (-not (Test-Path -LiteralPath (Split-Path -Path $manifestPath -Parent) -PathType Container)) {
  $null = New-Item -Path (Split-Path -Path $manifestPath -Parent) -ItemType Directory
}

if (-not $Force) {
  if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $overwrite = $Host.UI.PromptForChoice(
      '確認',
      "'$manifestPath' は既に存在します。上書きしますか?",
      (
        @('&Yes', 'はい'),
        @('&No', 'いいえ')
        | ForEach-Object { New-Object -TypeName System.Management.Automation.Host.ChoiceDescription -ArgumentList $_ }
      ),
      0) -eq 0
    if (-not $overwrite) {
      Write-Host -ForegroundColor Yellow 'マニフェストの作成をキャンセルしました'
      exit 0
    }
  }
}

Write-Host "マニフェストを作成しています: $manifestPath"

$Header = @"
# Created using CreateManifest.ps1 v$ScriptVersion
# yaml-language-server: `$schema=https://raw.githubusercontent.com/Per-Terra/butler-pkgs/main/schemas/JSON/manifest/$ManifestVersion.json

"@

try {
  ($manifest | ConvertTo-ManifestYaml -Header $Header) -replace "`r`n", "`n" |
    Out-File -FilePath $manifestPath -Encoding utf8NoBOM -Force -NoNewline
}
catch {
  Write-Error -Message "マニフェストの作成に失敗しました: $($_.Exception.Message)"
  exit 1
}
