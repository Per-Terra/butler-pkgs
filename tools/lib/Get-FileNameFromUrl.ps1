. (Join-Path -Path $PSScriptRoot -ChildPath 'Test-UrlFormat.ps1')

filter Get-FileNameFromUrl {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [string[]]$Url
  )

  $Url | ForEach-Object {
    Write-Verbose -Message "URLからファイル名を取得しています: $_"

    if (-not (Test-UrlFormat -Url $_)) {
      throw "URLの形式が正しくありません: $_"
    }

    $extension = Split-Path -Path $_ -Extension
    $response = $null

    if ($_ -match 'https://hazumurhythm\.com/php/amazon_download\.php\?name=(.+)') {
      Write-Verbose -Message "Amazonっぽい のダウンロードリンクを検出しました: $_"
      $id = $Matches[1]
      Write-Verbose -Message "ファイルのID: $id"
      Write-Verbose -Message "ヘッダーを取得しています: $_"
      try {
        $response = Invoke-WebRequest -Uri $_ -Method Head -Headers @{ Referer = "https://hazumurhythm.com/wev/amazon/?script=$id" }
      }
      catch {
        Write-Verbose -Message "ヘッダーの取得に失敗しました: $_"
      }
    }
    elseif ($extension -and $extension -notmatch '^\.(php)') {
      Write-Verbose -Message "URLにファイル名が含まれています: $_"
      $fileName = Split-Path -Path $_ -Leaf
      Write-Verbose -Message "ファイル名を取得しました: $fileName"
      return $fileName
    }
    else {
      Write-Verbose -Message "URLにファイル名が含まれていません: $_"
      Write-Verbose -Message "ヘッダーを取得しています: $_"
      try {
        $response = Invoke-WebRequest -Uri $_ -Method Head
      }
      catch {
        Write-Verbose -Message "ヘッダーの取得に失敗しました: $_"
      }
    }

    # $response.Headers['Content-Disposition'] は配列なので最初の要素を取得
    if ($response.Headers['Content-Disposition'][0]) {
      Write-Verbose -Message "Content-Dispositionヘッダーを検出しました: $($response.Headers['Content-Disposition'][0])"
      if ($response.Headers['Content-Disposition'][0] -match 'filename="(.+)"') {
        Write-Verbose -Message "ファイル名を取得しました: $($Matches[1])"
        return $Matches[1]
      }
    }

    Write-Verbose -Message "ファイル名を取得できませんでした: $_"
  }
}
