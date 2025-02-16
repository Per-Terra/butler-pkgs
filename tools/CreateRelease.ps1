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
    throw "powershell-yaml のインストールに失敗しました: $($_.Exception.Message)"
  }
}

$ManifestVersion = '0.3.0'

Write-Host -NoNewline 'YAMLファイルを探しています...'
$manifests = Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../manifests') -Filter '*.yaml' -Recurse -File
Write-Host " $($manifests.Count) 件のYAMLファイルが見つかりました"

$packages = [ordered]@{}
$developers = [ordered]@{}

$RootPath = "$(Split-Path -Path $PSScriptRoot -Parent)\"
for ($i = 0; $i -lt $manifests.Count; $i++) {
  $manifest = Get-Content -LiteralPath $manifests[$i].FullName -Raw | ConvertFrom-Yaml -Ordered
  if ($manifests[$i].Name -eq 'developer.yaml') {
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
  $relativePath = $manifests[$i].FullName.Replace($RootPath, '')
  $completed = ($i / $manifests.Count) * 100
  Write-Progress -Activity 'YAMLファイルを読み込んでいます...' -Status $relativePath -PercentComplete $completed
}
Write-Progress -Activity 'YAMLファイルを読み込んでいます...' -Completed
Write-Host 'YAMLファイルの読み込みが完了しました'

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

if (-not (Test-Path -LiteralPath $ReleaseDirectory -PathType Container)) {
  Write-Host -NoNewline 'release ディレクトリを作成しています...'
  $null = New-Item -Path $ReleaseDirectory -ItemType Directory -Force
  Write-Host ' 完了'
}

$files = @()

Write-Host -NoNewline 'JSONに変換しています...'
$json = ($contents | ConvertTo-Json -Depth 100 -Compress) + "`n"
Write-Host ' 完了'

Write-Host -NoNewline 'SHA256ハッシュ値を計算しています...'
$hasher = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json))
$hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
Write-Host ' 完了'

Write-Host -NoNewline 'contents-all.json を書き込んでいます...'
$json | Out-File -FilePath (Join-Path -Path $ReleaseDirectory -ChildPath 'contents-all.json') -Encoding utf8NoBOM -Force -NoNewline
$files += [ordered]@{
  Name   = 'contents-all.json'
  SHA256 = $hashString
}
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
# $hasher = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $hasher.ComputeHash($stream.ToArray())
$hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
Write-Host ' 完了'

Write-Host -NoNewline 'contents-all.json.gz を書き込んでいます...'
$stream.ToArray() | Set-Content -LiteralPath (Join-Path -Path $ReleaseDirectory -ChildPath 'contents-all.json.gz') -Force -AsByteStream
$files += [ordered]@{
  Name   = 'contents-all.json.gz'
  SHA256 = $hashString
}
Write-Host ' 完了'

Write-Host -NoNewline 'release.yaml を書き込んでいます...'
$release = [ordered]@{
  Date  = $Date.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  Files = $files
}
($release | ConvertTo-Yaml) -replace "`r`n", "`n" |
  Out-File -FilePath (Join-Path -Path $ReleaseDirectory -ChildPath 'release.yaml') -Encoding utf8NoBOM -Force -NoNewline
Write-Host ' 完了'
