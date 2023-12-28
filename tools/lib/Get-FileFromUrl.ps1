. (Join-Path -Path $PSScriptRoot -ChildPath 'Get-FileNameFromUrl.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'Test-UrlFormat.ps1')

function Get-FileFromUrl {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [string]$Url,
    [Parameter(Mandatory = $false)]
    [string]$OutDirectory,
    [Parameter(Mandatory = $false)]
    [switch]$Force
  )

  Write-Verbose -Message "ファイルをダウンロードしています: $Url"

  if (-not (Test-UrlFormat -Url $Url)) {
    throw "URLの形式が正しくありません: $Url"
  }

  Write-Verbose -Message "ファイル名を取得しています: $Url"
  $fileName = Get-FileNameFromUrl -Url $Url

  if (-not $fileName) {
    Write-Verbose -Message "ファイル名を取得できませんでした: $Url"
    $fileName = [System.IO.Path]::GetRandomFileName() + '.tmp'
    Write-Verbose -Message "ランダムなファイル名を生成しました: $fileName"
  }

  if (-not (Test-Path -Path $OutDirectory)) {
    Write-Verbose -Message "出力先ディレクトリを作成しています: $OutDirectory"
    try {
      $null = New-Item -Path $OutDirectory -ItemType Directory -Force
    }
    catch {
      throw "出力先ディレクトリの作成に失敗しました: $OutDirectory"
    }
  }

  $filePath = Join-Path -Path $OutDirectory -ChildPath $fileName
  Write-Verbose -Message "ファイルの保存先: $filePath"

  if ((Test-Path -Path $filePath) -and (-not $Force)) {
    do {
      $overwrite = Read-Host -Prompt "'$filePath' は既に存在します。上書きしますか? [Y/n]"
    } until ([string]::IsNullOrEmpty($overwrite) -or ($overwrite -in @('Y', 'n')))
    if ($overwrite -eq 'n') {
      return $filePath
    }
  }

  $params = @{
    Uri     = $Url
    OutFile = $filePath
  }

  if ($_ -match 'https://hazumurhythm\.com/php/amazon_download\.php\?name=(.+)') {
    Write-Verbose -Message "Amazonっぽい のダウンロードリンクを検出しました: $_"
    $id = $Matches[1]
    Write-Verbose -Message "ファイルのID: $id"
    $params.Add('Headers', @{ Referer = "https://hazumurhythm.com/wev/amazon/?script=$id" })
  }

  try {
    Invoke-WebRequest @params
  }
  catch {
    throw "ファイルのダウンロードに失敗しました: $Url"
  }

  Write-Verbose -Message "ファイルをダウンロードしました: $Url"

  return $filePath
}
