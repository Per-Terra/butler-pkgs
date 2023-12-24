param (
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

. (Join-Path -Path $PSScriptRoot -ChildPath './lib/ConvertTo-ManifestYaml.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath './lib/Get-FileFromUrl.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath './lib/Get-SHA256.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath './lib/Test-PackageManifest.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath './lib/Test-Url.ps1')

$ScriptVersion = '0.1.0'
$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
$WorkingDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'tmp'

# $test = @{
#   Identifier      = 'test-package'
#   DisplayName     = 'Test Package'
#   Version         = '1.0.0'
#   ReleaseDate     = Get-Date -Format 'yyyy-MM-dd'
#   Section         = 'Core'
#   Architecture    = 'x86'
#   Depends         = @('test-dependency')
#   InstalledSize   = 100
#   Developer       = @('test-developer')
#   Description     = @('test-description')
#   Website         = @('https://example.com')
#   Files           = @(
#     @{
#       SourceUrl = 'https://example.com'
#       SHA256    = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
#       Files     = @(
#         @{
#           Path    = 'test'
#           SHA256  = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
#           Install = @{
#             TargetPath = 'test'
#             Method     = 'Copy'
#           }
#         }
#       )
#     }
#   )
#   ConfFiles       = @('test')
#   ManifestVersion = 0
# }

# ConvertTo-ManifestYaml -Manifest $test
# exit 0

### original: https://github.com/microsoft/winget-pkgs/blob/4e76aed0d59412f0be0ecfefabfa14b5df05bec4/Tools/YamlCreate.ps1#L135-L149
### modified: Remove the NuGet installation and throw without type
# Installs `7Zip4Powershell` as a dependency for parsing yaml content
if (-not(Get-Module -ListAvailable -Name '7Zip4Powershell')) {
  try {
    Install-Module -Name '7Zip4Powershell' -Force -Repository PSGallery -Scope CurrentUser
  }
  catch {
    # If there was an exception while installing 7Zip4Powershell, pass it as an InternalException for further debugging
    throw "'7Zip4Powershell' unable to be installed successfully"
  }
  finally {
    # Double check that it was installed properly
    if (-not(Get-Module -ListAvailable -Name 7Zip4Powershell)) {
      throw "'7Zip4Powershell' is not found"
    }
  }
}
###

function Get-FilesInArchive {
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [string]$ArchiveFileName,
    [Parameter(Mandatory = $true)]
    [string]$TargetPath
  )

  Write-Information -MessageData "アーカイブを展開しています: $ArchiveFileName" -InformationAction Continue
  Expand-7Zip -ArchiveFileName $ArchiveFileName -TargetPath $TargetPath

  $files = Get-ChildItem -Path $TargetPath -Recurse -File
  $script:installedSize += [math]::Ceiling(($files | Measure-Object -Property Length -Sum).Sum / 1024)

  $filesInArchive = @()

  Write-Information -MessageData "アーカイブ内のファイルのSHA256ハッシュ値を計算しています: $ArchiveFileName" -InformationAction Continue
  $files | ForEach-Object {
    $file = @{
      Path   = $_.FullName.Replace($TargetPath, '').Replace('\', '/') -replace '^/', ''
      SHA256 = $_.FullName | Get-SHA256
    }
    if ($_.Extension -in @(
        '.exe', '.dll',
        '.auf', '.aui', '.auo', '.auc', '.aul',
        '.anm', '.obj', '.scn', '.cam', '.tra', '.lua',
        '.ini'
      )) {
      $file.Add('Install', @{
          TargetPath = ($_.FullName.Replace($TargetPath, '').Replace('\', '/') -replace '^/', '')
        })
    }
    elseif ($_.Extention -in @('.zip', '.7z')) {
      $file.Add('Files', ($_.FullName | Get-FilesInArchive -TargetPath $TargetPath))
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
    [string]$WorkingDirectory
  )

  $filePath = $Url | Get-FileFromUrl -OutDirectory $WorkingDirectory
  $fileName = Split-Path -Path $filePath -Leaf

  Write-Information -MessageData "ファイルのSHA256ハッシュ値を計算しています: $filePath" -InformationAction Continue
  $file = @{
    SourceUrl = $Url
    SHA256    = $filePath | Get-SHA256
  }
  if ($fileName -eq (Split-Path -Path $Url -Leaf)) {
    $file.Add('FileName', $fileName)
  }

  if (-not (Split-Path -Path $filePath -Extension) -in @('.zip', '.7z')) {
    $script:installedSize += [math]::Ceiling((Get-Item -Path $filePath).Length / 1024)
    $file.Add('Install', @{
        TargetPath = $fileName
      })

    return $file
  }

  $expandPath = Join-Path -Path (Split-Path -Path $filePath -Parent) -ChildPath (Split-Path -Path $filePath -LeafBase)
  if (Test-Path $expandPath) {
    Remove-Item -Path $expandPath -Recurse -Force
  }
  $file.Add('Files', ($filePath | Get-FilesInArchive -TargetPath $expandPath))

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
    if ((Split-Path -Path $File.Install.Path -Extension) -in @('.ini')) {
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

$sourceUrls = @()

if ([string]::IsNullOrEmpty($SourceUrl)) {
  do {
    Write-Host -ForegroundColor Yellow -Object '[任意] ' -NoNewline
    $urls = Read-Host -Prompt 'ソースファイルのURLを入力してください (複数入力する場合はカンマで区切ってください)'
    $sourceUrls = $urls -split ','
    $isValid = $true
    foreach ($url in $sourceUrls) {
      if (-not (Test-Url -Url $url)) {
        $isValid = $false
      }
    }
  } until ($isValid)
}
else {
  $sourceUrls = $SourceUrl
  foreach ($url in $sourceUrls) {
    if (-not (Test-Url -Url $url)) {
      throw "URLの形式が正しくありません: $url"
    }
  }
}

$script:installedSize = 0
$files = @()

$sourceUrls | ForEach-Object {
  Write-Information -MessageData "ファイルをダウンロードしています: $_" -InformationAction Continue
  $files += $_ | Get-SourceFileFromUrl -WorkingDirectory $WorkingDirectory
}

$confFiles = $files | ForEach-Object {
  $_ | Get-ConfFiles
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
  ConfFiles       = @($confFiles)
  ManifestVersion = 0
}

# Collection was modified; enumeration operation may not execute. というエラーが出るので、
# array にキャストしてから foreach で回す
foreach ($field in [array]$manifest.Keys) {
  if ([string]::IsNullOrEmpty($manifest[$field])) {
    if ($field -eq 'Description') {
      Write-Information -MessageData "'Description' はマニフェストの作成後に手動で編集してください" -InformationAction Continue
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

Write-Information -MessageData "マニフェストを作成しています: $manifestPath" -InformationAction Continue

try {
  $manifest | ConvertTo-ManifestYaml | Out-File -FilePath $manifestPath -Encoding $Utf8NoBomEncoding -NoNewline -Force
}
catch {
  Write-Error -MessageData $_.Exception.Message
  exit 1
}
