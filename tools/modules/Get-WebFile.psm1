Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Get-WebFileName.psm1')

function Get-WebFile {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory, ValueFromPipeline)]
    [string[]]$Uri,
    [string]$OutDirectory = $PWD,
    [switch]$Force
  )

  process {
    foreach ($item in $Uri) {
      Write-Verbose "ファイルをダウンロードしています: $item"
    }

    Write-Verbose "ファイル名を取得しています: $item"
    $fileName = Get-WebFileName -Uri $item

    if (-not $fileName) {
      Write-Verbose "ファイル名を取得できませんでした: $item"
      $fileName = [System.IO.Path]::GetRandomFileName() + '.tmp'
      Write-Verbose "ランダムなファイル名を生成しました: $fileName"
    }

    if (-not (Test-Path -LiteralPath $OutDirectory -PathType Container)) {
      Write-Verbose "出力先ディレクトリを作成しています: $OutDirectory"
      try {
        $null = New-Item -Path $OutDirectory -ItemType Directory -Force
      }
      catch {
        Write-Error "出力先ディレクトリの作成に失敗しました: $($_.Exception.Message)"
      }
    }

    $filePath = Join-Path -Path $OutDirectory -ChildPath $fileName
    Write-Verbose "ファイルの保存先: $filePath"

    if ((Test-Path -LiteralPath $filePath -PathType Leaf) -and (-not $Force)) {
      $answer = $Host.UI.PromptForChoice(
        "'$filePath' は既に存在します。",
        '上書きしますか?',
        (
          @('&Yes', 'はい'),
          @('&No', 'いいえ')
          | ForEach-Object { New-Object -TypeName System.Management.Automation.Host.ChoiceDescription -ArgumentList $_ }),
        1)

      if ($answer -eq 1) {
        return Get-Item -LiteralPath $filePath
      }
    }

    $params = @{
      Uri     = $item
      OutFile = $filePath
    }

    if ($item -match 'https://hazumurhythm\.com/php/amazon_download\.php\?name=(.+)') {
      Write-Verbose "アマゾンっぽい のダウンロードリンクを検出しました: $item"
      $id = $Matches[1]
      Write-Verbose "ファイルのID: $id"
      $params.Add('Headers', @{ Referer = "https://hazumurhythm.com/web/amazon/?script=$id" })
    }

    try {
      Invoke-WebRequest @params
    }
    catch {
      Write-Error "ファイルのダウンロードに失敗しました: $($_.Exception.Message)"
    }

    Get-Item -LiteralPath $filePath
  }
}
