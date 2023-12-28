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

### original: https://github.com/microsoft/winget-pkgs/blob/4e76aed0d59412f0be0ecfefabfa14b5df05bec4/Tools/YamlCreate.ps1#L135-L149
# powershell-yaml のインストール
if (-not(Get-Module -ListAvailable -Name 'powershell-yaml')) {
  try {
    Install-Module -Name 'powershell-yaml' -Force -Repository PSGallery -Scope CurrentUser
  }
  catch {
    throw "'powershell-yaml' のインストールに失敗しました"
  }
  finally {
    # Double check that it was installed properly
    if (-not(Get-Module -ListAvailable -Name powershell-yaml)) {
      throw "'powershell-yaml' が見つかりません"
    }
  }
}
###

. (Join-Path -Path $PSScriptRoot -ChildPath './lib/ConvertTo-ManifestYaml.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath './lib/Get-FileFromUrl.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath './lib/Get-SHA256.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath './lib/Test-PackageManifest.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath './lib/Test-UrlFormat.ps1')

$ScriptVersion = '0.1.0'
$ManifestVersion = '0.1.0'
$WorkingDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'tmp'

$ArchiveExtensions = @('.zip', '.7z')
$PluginExtensions = @('.exe', '.dll', '.auf', '.aui', '.auo', '.auc', '.aul', '.ini')
$ScriptExtensions = @('.anm', '.obj', '.scn', '.cam', '.tra', '.lua')
$ConfExtensions = @('.ini')

function Get-FilesInArchive {
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [string]$ArchiveFileName,
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,
    [Parameter(Mandatory = $false)]
    [AllowNull()]
    [object]$PreviousFile
  )

  Write-Host -Object "アーカイブを展開しています: $ArchiveFileName"
  Expand-7Zip -ArchiveFileName $ArchiveFileName -TargetPath $TargetPath

  $files = Get-ChildItem -Path $TargetPath -Recurse -File
  $script:installedSize += [math]::Ceiling(($files | Measure-Object -Property Length -Sum).Sum / 1024)

  $filesInArchive = @()

  Write-Host -Object "アーカイブ内のファイルの情報を取得しています: $ArchiveFileName"
  $files | ForEach-Object {
    $file = @{
      Path   = $_.FullName.Replace($TargetPath, '').Replace('\', '/') -replace '^/', ''
      SHA256 = $_.FullName | Get-SHA256
    }

    if ($PreviousFile) {
      $previousFileInArchive = $PreviousFile.Files | Where-Object { $_.Path -eq $file.Path }
    }

    if ($_.Extension -in $PluginExtensions) {
      if ($previousFileInArchive) {
        if ($previousFileInArchive.Install) {
          $file.Add('Install', $previousFileInArchive.Install)
        }
      }
      else {
        $file.Add('Install', @{
            TargetPath = ($_.FullName.Replace($TargetPath, '').Replace('\', '/') -replace '^/([^/]+/)*', '{{plugins}}/')
          })
      }
    }
    elseif ($_.Extension -in $ScriptExtensions) {
      if ($previousFileInArchive) {
        if ($previousFileInArchive.Install) {
          $file.Add('Install', $previousFileInArchive.Install)
        }
      }
      else {
        $file.Add('Install', @{
            TargetPath = ($_.FullName.Replace($TargetPath, '').Replace('\', '/') -replace '^/([^/]+/)*', '{{script}}/')
          })
      }
    }
    elseif ($_.Extension -eq '.exa') {
      if ($previousFileInArchive) {
        if ($previousFileInArchive.Install) {
          $file.Add('Install', $previousFileInArchive.Install)
        }
      }
      else {
        # サブディレクトリまで保持
        $path = $_.FullName.Replace($TargetPath, '').Replace('\', '/')
        $path = $path -split '/'
        $path = if ($path[-2]) { $path[-2] + '/' + $path[-1] } else { $path[-1] }
        $file.Add('Install', @{
            TargetPath = $path
          })
      }
    }
    elseif ($_.Extention -in $ArchiveExtensions) {
      $file.Add('Files', ($_.FullName | Get-FilesInArchive -TargetPath $TargetPath -PreviousFile $previousFileInArchive))
    }

    $filesInArchive += $file
  }

  return $filesInArchive
}

function Get-SourceFileFromUrl {
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [string]$Url,
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,
    [parameter(Mandatory = $false)]
    [AllowNull()]
    [object]$PreviousFile
  )

  if ($Url -match 'https://drive.google.com/file/d/([^/]+)') {
    Write-Host -Object "Google Drive のリンクを検出しました: $Url"
    $Url = "https://drive.google.com/uc?id=$($Matches[1])"
  }

  $filePath = $Url | Get-FileFromUrl -OutDirectory $WorkingDirectory -Force:$Force
  $fileName = Split-Path -Path $filePath -Leaf

  if ($previousFile) {
    if ($previousFile.SHA256 -eq ($filePath | Get-SHA256)) {
      throw "ファイルが変更されていません: $Url"
    }
  }

  Write-Host -Object "ファイルの情報を取得しています: $Url"
  $file = @{
    SourceUrl = $Url
    SHA256    = $filePath | Get-SHA256
  }
  if ($fileName -ne (Split-Path -Path $Url -Leaf)) {
    $file.Add('FileName', $fileName)
  }

  if (-not ((Split-Path -Path $filePath -Extension) -in $ArchiveExtensions)) {
    $script:installedSize += [math]::Ceiling((Get-Item -Path $filePath).Length / 1024)
    if ($previousFile) {
      if ($previousFile.Install) {
        $file.Add('Install', $previousFile.Install)
      }
    }
    else {
      $file.Add('Install', @{
          TargetPath = $fileName
        })
    }

    return $file
  }

  $expandPath = Join-Path -Path (Split-Path -Path $filePath -Parent) -ChildPath (Split-Path -Path $filePath -LeafBase)
  if (Test-Path $expandPath) {
    Remove-Item -Path $expandPath -Recurse -Force
  }
  $file.Add('Files', ($filePath | Get-FilesInArchive -TargetPath $expandPath -PreviousFile $previousFile))

  return $file
}

function Get-ConfFiles {
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [object]$File
  )

  $confFiles = @()

  if ($File.Install.Path) {
    if ((Split-Path -Path $File.Install.Path -Extension) -in $ConfExtensions) {
      $confFiles += $File.Install.Path
    }
  }

  if ($File.Files) {
    $File.Files | ForEach-Object {
      $confFiles += $_ | Get-ConfFiles
    }
  }

  return $confFiles
}

if (-not $Update) {
  do {
    $answer = Read-Host -Prompt '既存のパッケージを更新しますか? [Y/n]'
  } until ([string]::IsNullOrEmpty($answer) -or ($answer -in @('Y', 'n')))
  if ($answer -eq 'n') {
    $Update = $false
  }
  else {
    $Update = $true
  }
}

if ($Update) {
  if ([string]::IsNullOrEmpty($Identifier) -or [string]::IsNullOrEmpty($Developer)) {
    do {
      $package = Read-Host -Prompt '更新するパッケージを Developer/Identifier の形式で入力してください'
    } while ([string]::IsNullOrEmpty($package))
    $manifestsPath = Join-Path -Path $PSScriptRoot -ChildPath "../manifests/$($package.Split('/')[0])/$($package.Split('/')[1])"
  }
  else {
    $manifestsPath = Join-Path -Path $PSScriptRoot -ChildPath "../manifests/$($Developer)/$($Identifier)"
  }

  if (-not (Test-Path -Path $manifestsPath)) {
    throw "マニフェストが見つかりません: $manifestsPath"
  }

  $manifests = Get-ChildItem -Path $manifestsPath -Filter '*.yaml' -Recurse
  if ($manifests.Count -eq 0) {
    throw "マニフェストが見つかりません: $manifestsPath"
  }

  # ReleaseDate が最新のマニフェストを取得
  $manifest = $manifests | Sort-Object -Property Name | ForEach-Object {
    $manifest = Get-Content -Path $_.FullName -Raw | ConvertFrom-Yaml -Ordered
    if ($manifest.ReleaseDate) {
      $manifest
    }
  } | Sort-Object -Property ReleaseDate -Descending | Select-Object -First 1

  if (-not $manifest) {
    throw "マニフェストが見つかりません: $manifestsPath"
  }

  if ($manifest.Files -and $manifest.Files.Count -gt 2) {
    throw "マニフェストに複数のファイルが含まれています: $manifestsPath"
  }

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
  $previousFile = $manifest.Files
  $ConfFiles = $manifest.ConfFiles
}

$sourceUrls = @()

if ([string]::IsNullOrEmpty($SourceUrl)) {
  do {
    Write-Host -Object '[任意] ' -NoNewline
    $urls = Read-Host -Prompt 'ソースファイルのURLを入力してください (複数入力する場合はカンマで区切ってください)'
    $sourceUrls = $urls -split ','
    $isValid = $true
    foreach ($url in $sourceUrls) {
      if (-not (Test-UrlFormat -Url $url)) {
        $isValid = $false
      }
    }
  } until ($isValid)
}
else {
  $sourceUrls = $SourceUrl
  foreach ($url in $sourceUrls) {
    if (-not (Test-UrlFormat -Url $url)) {
      throw "URLの形式が正しくありません: $url"
    }
  }
}

$script:installedSize = 0
$files = @()

$sourceUrls | ForEach-Object {
  Write-Host -Object "ファイルをダウンロードしています: $_"
  $files += $_ | Get-SourceFileFromUrl -WorkingDirectory $WorkingDirectory -PreviousFile $previousFile
}

if ($null -eq $ConfFiles) {
  $ConfFiles = $files | ForEach-Object { $_ | Get-ConfFiles }
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
  InstalledSize   = [uint]$script:installedSize
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
      Write-Host -Object "'Description' はマニフェストの作成後に手動で編集してください"
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
          Write-Host -ForegroundColor Yellow -Object '[必須] ' -NoNewline
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
          Write-Host -ForegroundColor Yellow -Object '[必須] ' -NoNewline
          $value = Read-Host -Prompt "'$field' を入力してください"
        } until ($value -and (Test-PackageManifest -Field $field -Value $value))
      }
    }
    elseif (-not $SkipPrompt) {
      if ($Schema.properties.$field.type -eq 'array') {
        do {
          Write-Host -Object '[任意] ' -NoNewline
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
          Write-Host -Object '[任意] ' -NoNewline
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
if (-not (Test-Path -Path (Split-Path -Path $manifestPath -Parent))) {
  $null = New-Item -Path (Split-Path -Path $manifestPath -Parent) -ItemType Directory
}

if (-not $Force) {
  if (Test-Path -Path $manifestPath) {
    do {
      $overwrite = Read-Host -Prompt "'$manifestPath' は既に存在します。上書きしますか? [Y/n]"
    } until ([string]::IsNullOrEmpty($overwrite) -or ($overwrite -in @('Y', 'n')))
    if ($overwrite -eq 'n') {
      exit 0
    }
  }
}

Write-Host -Object "マニフェストを作成しています: $manifestPath"

$Header = @"
# Created using CreateManifest.ps1 v$ScriptVersion
# yaml-language-server: `$schema=https://raw.githubusercontent.com/Per-Terra/butler-pkgs/main/schemas/JSON/manifests/$ManifestVersion.json

"@

try {
  ($manifest |
  ConvertTo-ManifestYaml -Header $Header) -replace "`r`n", "`n" |
  Out-File -FilePath $manifestPath -Encoding utf8NoBOM -Force -NoNewline
}
catch {
  Write-Error -Message $_.Exception.Message
  exit 1
}
