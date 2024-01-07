[CmdletBinding()]
param (
  [Parameter(Mandatory = $false)]
  [string]$ReleaseDirectory = (Join-Path -Path $PSScriptRoot -ChildPath '../release'),
  [Parameter(Mandatory = $false)]
  [datetime]$Date = [datetime](git -C $PSScriptRoot log -1 --format=%cI)
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

$ManifestVersion = '0.2.0'

Write-Host -Object 'YAMLファイルを探しています...' -NoNewline
$manifests = Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../manifests') -Filter '*.yaml' -Recurse -File
Write-Host -Object " $($manifests.Count) 件のYAMLファイルが見つかりました"

$packages = [ordered]@{}
$developers = [ordered]@{}

Write-Host -Object 'YAMLファイルを読み込んでいます...' -NoNewline
$manifests | ForEach-Object {
  $manifest = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Yaml -Ordered
  if ($_.Name -eq 'developer.yaml') {
    $developer = $manifest.Identifier
    $manifest.Remove('Identifier')
    $manifest.Remove('ManifestVersion')
    if ($developers[$developer]) {
      throw "開発者名が重複しています: $developer"
    }
    $developers.Add($developer, $manifest)
  }
  else {
    $identifier = $manifest.Identifier
    $version = $manifest.Version
    $manifest.Remove('Identifier')
    $manifest.Remove('Version')
    $manifest.Remove('ManifestVersion')
    if ($packages[$identifier]) {
      if ($packages[$identifier][$version]) {
        throw "バージョンが重複しています: $identifier ($version)"
      }
      $packages[$identifier].Add($version, $manifest)
    }
    else {
      $packages.Add($identifier, [ordered]@{ $version = $manifest })
    }
  }
}
Write-Host -Object ' 完了'

Write-Host -Object 'YAMLファイルをソートしています...' -NoNewline

$sortedPackages = [ordered]@{}
foreach ($identifier in ($packages.Keys | Sort-Object)) {
  $sortedPackages.Add($identifier, [ordered]@{})
  foreach ($version in ($packages[$identifier].Keys | Sort-Object -Property @{
        # Version でソート
        Expression = {
          if ($null -ne $packages[$identifier][$_].Version) {
            $packages[$identifier][$_].Version
          }
          else {
            ''
          }
        }
        Descending = $true
      }, @{
        # ReleaseDate でソート
        Expression = {
          if ($null -ne $packages[$identifier][$_].ReleaseDate) {
            [datetime]::ParseExact($packages[$identifier][$_].ReleaseDate, 'yyyy-MM-dd', $null)
          }
          else {
            [datetime]::MinValue
          }
        }
        Descending = $true
      })) {
    $sortedPackages[$identifier].Add($version, $packages[$identifier][$version])
  }
}

Write-Host -Object ' 完了'

$contents = [ordered]@{
  Date            = $Date.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  Packages        = $sortedPackages
  Developers      = $developers
  ManifestVersion = $ManifestVersion
}

Write-Host -Object 'JSONに変換しています...' -NoNewline
$json = ($contents | ConvertTo-Json -Depth 100 -Compress) + "`n"
Write-Host -Object ' 完了'

Write-Host -Object 'JSONを圧縮しています...' -NoNewline
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
$stream = [System.IO.MemoryStream]::new()
$gzip = [System.IO.Compression.GzipStream]::new($stream, [System.IO.Compression.CompressionLevel]::SmallestSize)
$gzip.Write($bytes, 0, $bytes.Length)
$gzip.Close()
$stream.Close()
Write-Host -Object ' 完了'

Write-Host -Object 'SHA256ハッシュ値を計算しています...' -NoNewline
$hash = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $hash.ComputeHash($stream.ToArray())
$hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
Write-Host -Object ' 完了'

if (-not (Test-Path -LiteralPath $ReleaseDirectory -PathType Container)) {
  Write-Host -Object 'ディレクトリを作成しています...' -NoNewline
  $null = New-Item -Path $ReleaseDirectory -ItemType Directory -Force
  Write-Host -Object ' 完了'
}

Write-Host -Object 'contents-all.json.gz を書き込んでいます...' -NoNewline
$stream.ToArray() | Set-Content -LiteralPath (Join-Path -Path $ReleaseDirectory -ChildPath 'contents-all.json.gz') -Force -AsByteStream
Write-Host -Object ' 完了'

Write-Host -Object 'release.yaml を書き込んでいます...' -NoNewline
$release = [ordered]@{
  Date  = $Date.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  Files = @( [ordered]@{
      Name   = 'contents-all.json.gz'
      Sha256 = $hashString
    })
}
($release | ConvertTo-Yaml) -replace "`r`n", "`n" |
Out-File -FilePath (Join-Path -Path $ReleaseDirectory -ChildPath 'release.yaml') -Encoding utf8NoBOM -Force -NoNewline
Write-Host -Object ' 完了'
