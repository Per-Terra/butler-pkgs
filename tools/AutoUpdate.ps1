[CmdletBinding()]
param (
  [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
  [Alias('FullName')]
  [string[]]$YamlPath,
  [string]$Identifier,
  [string]$Developer
)

begin {
  # powershell-yaml のインストール
  if (-not (Get-Module -Name 'powershell-yaml' -ListAvailable)) {
    try {
      Install-Module -Name 'powershell-yaml' -Force -Repository PSGallery -Scope CurrentUser
    }
    catch {
      throw "powershell-yaml のインストールに失敗しました: $($_.Exception.Message)"
    }
  }

  function Get-GitHubReleases {
    [CmdletBinding()]
    param (
      [Parameter(Mandatory)]
      [string]$Owner,
      [Parameter(Mandatory)]
      [string]$Repo,
      [ValidateRange(1, 100)]
      [uint]$PerPage = 30,
      [uint]$Page = 1,
      [switch]$Latest
    )

    # https://docs.github.com/ja/rest/releases/releases?apiVersion=2022-11-28#list-releases
    $releasesUrl = "https://api.github.com/repos/$Owner/$Repo/releases"
    if ($Latest) {
      $releasesUrl += '/latest'
    }
    else {
      $releasesUrl += "?per_page=$PerPage&page=$Page"
    }

    try {
      if ($env:GH_TOKEN) {
        $response = Invoke-RestMethod -Uri $releasesUrl -Authentication Bearer -Token (ConvertTo-SecureString -String $env:GH_TOKEN -AsPlainText -Force)
      }
      else {
        $response = Invoke-RestMethod -Uri $releasesUrl
      }
    }
    catch {
      throw "GitHub API へのリクエストに失敗しました: $($_.Exception.Message)"
    }

    if ($response) {
      $response
    }
    else {
      throw "GitHub API からのレスポンスが空です: $releasesUrl"
    }
  }
}

process {
  if ([string]::IsNullOrEmpty($YamlPath)) {
    Write-Host 'auto-update ディレクトリ内の YAML ファイルを読み込んでいます'
    $YamlPath = Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "../auto-update") -Filter '*.yaml' -Recurse -File | Select-Object -ExpandProperty FullName
  }

  $targets = @()

  foreach ($path in $YamlPath) {
    try {
      $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Yaml
      if ($data) {
        $targets += $data
      }
      else {
        Write-Warning "YAML ファイルの内容が空です: $path"
      }
    }
    catch {
      Write-Warning "YAML ファイルの読み込みに失敗しました: $path"
      Write-Warning "エラー: $($_.Exception.Message)"
    }
  }

  if ($Identifier) {
    $targets = $targets | Where-Object { $_.Identifier -eq $Identifier }
  }

  if ($Developer) {
    $targets = $targets | Where-Object { $_.Developer -eq $Developer }
  }

  if (-not $targets) {
    Write-Warning '処理対象が見つかりませんでした'
    return
  }

  Write-Host "$(@($targets).Count) 件の処理を開始します"

  # Rate limit対策用のStopWatch
  $watch = New-Object System.Diagnostics.StopWatch
  $elapsed = 500

  foreach ($target in $targets) {
    if ($target.Disabled) {
      Write-Host "無効: $($target.Developer)/$($target.Identifier)"
      continue
    }

    Write-Host "処理中: $($target.Developer)/$($target.Identifier)"

    $sources = @()

    switch ($target.Type) {
      'GitHub' {
        Write-Host "GitHubからリリースを取得しています: $($target.Owner)/$($target.Repository)"
        $page = 1
        $skipped = $false
        do {
          $sleep = 500 - $elapsed
          if ($sleep -gt 0) {
            Write-Debug "Rate limit対策のため $sleep ミリ秒待機します"
            Start-Sleep -Milliseconds $sleep
          }
          $watch.Reset()
          $watch.Start()

          $releases = Get-GitHubReleases -Owner $target.Owner -Repo $target.Repository -PerPage 100 -Page $page
          foreach ($release in $releases) {
            if ($target.IgnoreOlderThan -and $release.published_at -lt [datetime]::ParseExact($target.IgnoreOlderThan, 'yyyy-MM-dd', $null)) {
              Write-Host "古いリリースをスキップします: $($release.published_at.ToString('yyyy-MM-dd')) ($($release.tag_name))"
              $skipped = $true
              continue
            }
            $asset = $release.assets | Where-Object { $_.name -match $target.Asset } | Select-Object -First 1
            $url = $asset.browser_download_url
            if ([string]::IsNullOrEmpty($url)) {
              Write-Warning "Assetが見つかりません: $($target.Owner)/$($target.Repository)"
              Write-Warning "Assetの正規表現: $($target.Asset)"
              Write-Warning "URL: $($release.html_url)"
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
            if ($target.Version.script) {
              Invoke-Expression -Command $target.Version.script
            }
            if ([string]::IsNullOrEmpty($version)) {
              Write-Warning "バージョンが見つかりません: $($target.Developer)/$($target.Identifier)"
              Write-Warning "バージョンの取得元: $($target.Version.from)"
              Write-Warning "バージョンの正規表現: s/$($target.Version.regex.find)/$($target.Version.regex.replace)/"
              Write-Warning "URL: $($release.html_url)"
              continue
            }

            $date = $asset.updated_at.ToString('yyyy-MM-dd')

            $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath "../manifests/$($target.Developer)/$($target.Identifier)/$version.yaml"

            if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
              $null = (Get-Content -LiteralPath $manifestPath -Raw) -match "`nReleaseDate: (.*)`n"
              $releaseDate = $Matches[1]
              if ($releaseDate -and $releaseDate -ge $date) {
                Write-Host "該当するバージョンのより新しいマニフェストが既に存在します: $($target.Developer)/$($target.Identifier) ($version)"
                Write-Debug "作成中のマニフェストのリリース日: $date"
                Write-Debug "既存のマニフェストのリリース日: $releaseDate"
                Write-Debug "マニフェストの作成はスキップされました"
                $skipped = $true
                continue
              }
            }

            $sources += @{
              SourceUrl   = $url
              Identifier  = $target.Identifier
              Version     = $version
              ReleaseDate = $date
              Developer   = $target.Developer
            }
          }
          $page++

          $watch.Stop()
          $elapsed = $watch.ElapsedMilliseconds
        } while ($releases.Count -eq 100 -and -not $skipped)
      }
      default {
        throw "未対応のタイプです: $($target.Type)"
      }
    }

    if ($sources) {
      Write-Host "$($sources.Count) 件のマニフェストが作成されます: $($target.Developer)/$($target.Identifier)"

      # 古いバージョンから順にマニフェストを作成する
      $sources = $sources | Sort-Object -Property @{
        Expression = {
          if ($null -ne $_.Version) {
            $_.Version
          }
          else {
            ''
          }
        }
      }, @{
        Expression = {
          if ($null -ne $_.ReleaseDate) {
            [datetime]::ParseExact($_.ReleaseDate, 'yyyy-MM-dd', $null)
          }
          else {
            [datetime]::MinValue
          }
        }
      }

      foreach ($source in $sources) {
        try {
          . (Join-Path -Path $PSScriptRoot -ChildPath "./CreateManifest.ps1") -Update -SourceUrl $source.SourceUrl -Identifier $source.Identifier -Version $source.Version -ReleaseDate $source.ReleaseDate -Developer $source.Developer -SkipPrompt -Force
        }
        catch {
          Write-Warning "マニフェストは作成されませんでした: $($_.Exception.Message)"
        }
      }
    }
    else {
      Write-Host "マニフェストは作成されませんでした: $($target.Developer)/$($target.Identifier)"
    }
  }
}
