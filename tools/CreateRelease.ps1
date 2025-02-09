[CmdletBinding()]
param (
  [string]$ReleaseDirectory = (Join-Path -Path $PSScriptRoot -ChildPath '../release'),
  [datetime]$Date = [datetime](git -C $PSScriptRoot log -1 --format=%cI)
)

# powershell-yaml のインストール
if (-not (Get-Module -Name 'powershell-yaml' -ListAvailable)) {
  try {
    Install-Module -Name 'powershell-yaml' -Force -Repository PSGallery -Scope CurrentUser
  }
  catch {
    throw "powershell-yaml のインストールに失敗しました: $(($_.Exception.Message))"
  }
}

$ManifestVersion = '0.2.0'

Write-Host -NoNewline 'YAMLファイルを探しています...'
$manifests = Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../manifests') -Filter '*.yaml' -Recurse -File
Write-Host " $($manifests.Count) 件のYAMLファイルが見つかりました"

$packages = [ordered]@{}
$developers = [ordered]@{}

Write-Host -NoNewline 'YAMLファイルを読み込んでいます...'
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
Write-Host ' 完了'

Write-Host -NoNewline 'YAMLファイルをソートしています...'

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

Write-Host ' 完了'

$contents = [ordered]@{
  Date            = $Date.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  Packages        = $sortedPackages
  Developers      = $developers
  ManifestVersion = $ManifestVersion
}

Write-Host -NoNewline 'JSONに変換しています...'
$json = ($contents | ConvertTo-Json -Depth 100 -Compress) + "`n"
Write-Host ' 完了'

Write-Host -NoNewline 'JSONを圧縮しています...'
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
$stream = [System.IO.MemoryStream]::new()
$gzip = [System.IO.Compression.GzipStream]::new($stream, [System.IO.Compression.CompressionLevel]::SmallestSize)
$gzip.Write($bytes, 0, $bytes.Length)
$gzip.Close()
$stream.Close()
Write-Host ' 完了'

Write-Host -NoNewline 'SHA256ハッシュ値を計算しています...'
$hash = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $hash.ComputeHash($stream.ToArray())
$hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
Write-Host ' 完了'

if (-not (Test-Path -LiteralPath $ReleaseDirectory -PathType Container)) {
  Write-Host -NoNewline 'ディレクトリを作成しています...'
  $null = New-Item -Path $ReleaseDirectory -ItemType Directory -Force
  Write-Host ' 完了'
}

Write-Host -NoNewline 'contents-all.json.gz を書き込んでいます...'
$stream.ToArray() | Set-Content -LiteralPath (Join-Path -Path $ReleaseDirectory -ChildPath 'contents-all.json.gz') -Force -AsByteStream
Write-Host ' 完了'

Write-Host -NoNewline 'release.yaml を書き込んでいます...'
$release = [ordered]@{
  Date  = $Date.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  Files = @( [ordered]@{
      Name   = 'contents-all.json.gz'
      Sha256 = $hashString
    })
}
($release | ConvertTo-Yaml) -replace "`r`n", "`n" |
  Out-File -FilePath (Join-Path -Path $ReleaseDirectory -ChildPath 'release.yaml') -Encoding utf8NoBOM -Force -NoNewline
Write-Host ' 完了'
