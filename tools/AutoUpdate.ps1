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

$yamls = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath "../auto-update") -Filter '*.yaml' -Recurse -File

$targets = @()

$yamls | ForEach-Object {
  $_ | Get-Content -Raw | ConvertFrom-Yaml | ForEach-Object {
    $targets += $_
  }
}

function Get-GitHubReleases {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$Owner,
    [Parameter(Mandatory = $true)]
    [string]$Repo,
    [Parameter(Mandatory = $false)]
    [switch]$Latest
  )

  # https://docs.github.com/ja/rest/releases/releases?apiVersion=2022-11-28#list-releases
  $uri = "https://api.github.com/repos/$Owner/$Repo/releases"
  if ($Latest) {
    $uri += '/latest'
  }

  try {
    $response = Invoke-RestMethod -Uri $uri -Method Get -ContentType 'application/json'
  }
  catch {
    throw "GitHub API へのリクエストに失敗しました: $_"
  }

  if ($response) {
    return $response
  }
  else {
    throw "GitHub API からのレスポンスが空です: $uri"
  }
}

foreach ($target in $targets) {
  if ($target.Enable) {
    Write-Host -Object "更新中: $($target.Developer)/$($target.Identifier)"
  }
  else {
    Write-Host -Object "無効: $($target.Developer)/$($target.Identifier)"
    continue
  }

  switch ($target.Type) {
    'GitHub' {
      Write-Host -Object "GitHubからリリースを取得しています: $($target.Owner)/$($target.Repository)"
      $releases = Get-GitHubReleases -Owner $target.Owner -Repo $target.Repository
      foreach ($release in $releases) {
        $asset = $release.assets | Where-Object { $_.name -match $target.Asset } | Select-Object -First 1
        $url = $asset.browser_download_url
        if ([string]::IsNullOrEmpty($url)) {
          Write-Warning -Message "Assetが見つかりません: $($target.Owner)/$($target.Repository)"
          Write-Warning -Message "Assetの正規表現: $($target.Asset)"
          Write-Warning -Message "URL: $($release.html_url)"
          continue
        }

        $versionFrom = $target.Version.from.Split('.')
        if ($versionFrom[0] -eq 'asset') {
          $version = $asset.($versionFrom[1])
        }
        else {
          $version = $release.($versionFrom[0])
        }
        if ($target.Version.regex -and $version -match $target.Version.regex.find) {
          $version = $version -replace $target.Version.regex.find, $target.Version.regex.replace
        }
        if ([string]::IsNullOrEmpty($version)) {
          Write-Warning -Message "バージョンが見つかりません: $($target.Developer)/$($target.Identifier)"
          Write-Warning -Message "バージョンの取得元: $($target.Version.from)"
          Write-Warning -Message "バージョンの正規表現: s/$($target.Version.regex.find)/$($target.Version.regex.replace)/"
          Write-Warning -Message "URL: $($release.html_url)"
          continue
        }

        $date = $asset.updated_at.ToString('yyyy-MM-dd')

        $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath "../manifests/$($target.Developer)/$($target.Identifier)/$version.yaml"

        if (Test-Path -Path $manifestPath) {
          $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Yaml
          if ($manifest.ReleaseDate -ge $date) {
            Write-Host -Object "該当するバージョンのより新しいマニフェストが既に存在します: $($target.Developer)/$($target.Identifier) ($version)"
            Write-Host -Object "作成中のマニフェストのリリース日: $($date)"
            Write-Host -Object "既存のマニフェストのリリース日: $($manifest.ReleaseDate)"
            Write-Warning -Message "マニフェストの作成はスキップされました"
            continue
          }
        }

        try {
          . (Join-Path -Path $PSScriptRoot -ChildPath "./CreateManifest.ps1") -Update -SourceUrl $url -Identifier $target.Identifier -Version $version -ReleaseDate $date.toString('yyyy-MM-dd') -Developer $target.Developer -SkipPrompt -Force
        }
        catch {
          Write-Warning -Message "マニフェストは作成されませんでした: $_"
        }
      }
    }
    default {
      throw "未対応のタイプです: $($target.Type)"
    }
  }
}