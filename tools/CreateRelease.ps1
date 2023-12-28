[CmdletBinding()]
param (
  [Parameter(Mandatory = $false)]
  [string]$ReleaseDirectory = (Join-Path -Path $PSScriptRoot -ChildPath '../release'),
  [Parameter(Mandatory = $false)]
  [string]$Date = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ' -AsUTC)
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

$ManifestVersion = '0.1.0'

$contents = [ordered]@{
  '$manifestVersion' = $ManifestVersion
  '$date'            = $Date
}

Write-Host -Object 'YAMLファイルを探しています...' -NoNewline
$manifests = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '../manifests') -Filter '*.yaml' -Recurse
Write-Host -Object " $($manifests.Count) 件のYAMLファイルが見つかりました"

Write-Host -Object 'YAMLファイルを読み込んでいます...' -NoNewline
$manifests | ForEach-Object {
  if ($_.Name -eq 'developer.yaml') {
    $developer = Get-Content -Path $_.FullName -Raw | ConvertFrom-Yaml -Ordered
    $identifier = $developer.Identifier
    $developer.Remove('Identifier')
    $developer.Remove('ManifestVersion')
    if ($contents[$identifier]) {
      $contents[$identifier].Add('$developer', $developer)
    }
    else {
      $contents[$identifier] = [ordered]@{ '$developer' = $developer }
    }
  }
  else {
    $package = Get-Content -Path $_.FullName -Raw | ConvertFrom-Yaml -Ordered
    $identifier = $package.Identifier
    $version = $package.Version
    $developer = $package.Developer[0]
    $package.Remove('Identifier')
    $package.Remove('Version')
    $package.Remove('ManifestVersion')
    if ($contents[$developer]) {
      if ($contents[$developer][$identifier]) {
        $contents[$developer][$identifier].Add($version, $package)
      }
      else {
        $contents[$developer][$identifier] = [ordered]@{ $version = $package }
      }
    }
    else {
      $contents[$developer] = [ordered]@{ $identifier = [ordered]@{ $version = $package } }
    }
  }
}
Write-Host -Object ' 完了'

Write-Host -Object 'YAMLファイルをソートしています...' -NoNewline
$contents = $contents | Sort-Object -Property Name

# ReleaseDate でソート
foreach ($developer in [array]$contents.Keys) {
  foreach ($identifier in [array]$contents[$developer].Keys) {
    $sortedPackages = [ordered]@{}
    $contents[$developer][$identifier].GetEnumerator() |
    Sort-Object -Property @{
      Expression = {
        if ($null -ne $_.Value.ReleaseDate) {
          [datetime]::ParseExact($_.Value.ReleaseDate, 'yyyy-MM-dd', $null)
        }
        else {
          [datetime]::MinValue
        }
      }
      Descending = $true
    } |
    ForEach-Object {
      $sortedPackages.Add($_.Key, $_.Value)
    }
    $contents[$developer][$identifier] = $sortedPackages
  }
}
Write-Host -Object ' 完了'

Write-Host -Object 'JSONに変換しています...' -NoNewline
$json = ($contents | ConvertTo-Json -Depth 100 -Compress) + "`n"
Write-Host -Object ' 完了'

Write-Host -Object 'JSONを圧縮しています...' -NoNewline
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
$stream = [System.IO.MemoryStream]::new()
$gzip = [System.IO.Compression.GzipStream]::new($stream, [System.IO.Compression.CompressionMode]::Compress)
$gzip.Write($bytes, 0, $bytes.Length)
$gzip.Close()
$stream.Close()
Write-Host -Object ' 完了'

Write-Host -Object 'SHA256ハッシュ値を計算しています...' -NoNewline
$hash = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $hash.ComputeHash($stream.ToArray())
$hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
Write-Host -Object ' 完了'

if (-not(Test-Path -Path $ReleaseDirectory)) {
  Write-Host -Object 'ディレクトリを作成しています...' -NoNewline
  New-Item -Path $ReleaseDirectory -ItemType Directory -Force | Out-Null
  Write-Host -Object ' 完了'
}

Write-Host -Object 'contents.json.gz を書き込んでいます...' -NoNewline
$stream.ToArray() | Set-Content -Path (Join-Path -Path $ReleaseDirectory -ChildPath 'contents.json.gz') -Force -AsByteStream
Write-Host -Object ' 完了'

Write-Host -Object 'release.yaml を書き込んでいます...' -NoNewline
$release = [ordered]@{
  Date            = $Date
  SHA256          = $hashString
  ManifestVersion = $ManifestVersion
}
($release | ConvertTo-Yaml) -replace "`r`n", "`n" |
Out-File -FilePath (Join-Path -Path $ReleaseDirectory -ChildPath 'release.yaml') -Encoding utf8NoBOM -Force -NoNewline
Write-Host -Object ' 完了'
