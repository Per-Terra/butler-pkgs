[CmdletBinding()]
param (
  [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
  [Alias('FullName')]
  [string[]]$YamlPath,
  [string]$Identifier,
  [string]$Developer,
  [switch]$ReturnSources
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

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
      Write-Error 'gh コマンドが見つかりません'
      Write-Error 'GitHub CLI をインストールしてください: https://cli.github.com/'
      exit 1
    }

    $command = 'gh api --method GET -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28"'
    $endpoint = "/repos/$Owner/$Repo/releases"
    $options = @()

    if ($Latest) {
      $endpoint += '/latest'
    }
    else {
      if ($PerPage -ne 30) {
        $options += "-F per_page=$PerPage"
      }
      if ($Page -ne 1) {
        $options += "-F page=$Page"
      }
    }

    try {
      $originalEncoding = [System.Console]::OutputEncoding
      [System.Console]::OutputEncoding = [Text.Encoding]::UTF8
      $response = Invoke-Expression "$command $endpoint $options"
      [System.Console]::OutputEncoding = $originalEncoding
    }
    catch {
      throw "GitHub API へのリクエストに失敗しました: $($_.Exception.Message)"
    }

    if ($response) {
      $response | ConvertFrom-Json
    }
    else {
      throw "GitHub API からのレスポンスが空です: $endpoint"
    }
  }
}

process {
  # YamlPath が指定されていない場合は、auto-update ディレクトリ内の YAML ファイルを読み込む
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

  # Identifier でフィルタリング
  if ($Identifier) {
    $targets = $targets | Where-Object { $_.Identifier -eq $Identifier }
  }

  # Developer でフィルタリング
  if ($Developer) {
    $targets = $targets | Where-Object { $_.Developer -eq $Developer }
  }

  if (-not $targets) {
    Write-Warning '処理対象が見つかりませんでした'
    return
  }

  Write-Host "$(@($targets).Count) 件の処理を開始します"

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
        } while ($releases.Count -eq 100 -and -not $skipped)
      }
      default {
        throw "未対応のタイプです: $($target.Type)"
      }
    }

    if ($sources) {
      Write-Host "$($sources.Count) 件の更新が見つかりました: $($target.Developer)/$($target.Identifier)"

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

      if ($ReturnSources) {
        # , (単項配列演算子) を使って配列そのものを返す
        # 例えば '.\AutoUpdate.ps1 -ReturnSources | ForEach-Object { $_ | ConvertTo-Json -AsArray }' とするとパッケージごとに配列をJSON形式で出力できる
        # ref: https://stackoverflow.com/questions/29973212/pipe-complete-array-objects-instead-of-array-items-one-at-a-time
        # ref: https://learn.microsoft.com/ja-jp/powershell/module/microsoft.powershell.core/about/about_operators?view=powershell-7.5#comma-operator-
        ,$sources
        continue
      }

      Write-Host "マニフェストを作成しています: $($target.Developer)/$($target.Identifier)"
      foreach ($source in $sources) {
        try {
          & (Join-Path -Path $PSScriptRoot -ChildPath './CreateManifest.ps1') -Update -SourceUrl $source.SourceUrl -Identifier $source.Identifier -Version $source.Version -ReleaseDate $source.ReleaseDate -Developer $source.Developer -SkipPrompt -Force
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
