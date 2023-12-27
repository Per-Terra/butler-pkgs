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

    if ($_ -match 'https://scrapbox.io/files/(?:.+)\?title=(.+)') {
      Write-Verbose -Message "Scrapbox のダウンロードリンクを検出しました: $_"
      $fileName = $Matches[1]
      Write-Verbose -Message "ファイル名を取得しました: $fileName"
      return $fileName
    }

    if ($extension -and ($extension -notmatch '^\.(php)')) {
      Write-Verbose -Message "URLにファイル名が含まれています: $_"
      $fileName = Split-Path -Path $_ -Leaf
      Write-Verbose -Message "ファイル名を取得しました: $fileName"
      return $fileName
    }

    $params = @{
      Uri    = $_
      Method = 'Head'
    }

    if ($_ -match 'https://hazumurhythm\.com/php/amazon_download\.php\?name=(.+)') {
      Write-Verbose -Message "Amazonっぽい のダウンロードリンクを検出しました: $_"
      $id = $Matches[1]
      Write-Verbose -Message "ファイルのID: $id"
      $params.Add('Headers', @{ Referer = "https://hazumurhythm.com/wev/amazon/?script=$id" })
    }
    else {
      Write-Verbose -Message "URLにファイル名が含まれていません: $_"
    }

    Write-Verbose -Message "ヘッダーを取得しています: $_"
    try {
      $response = Invoke-WebRequest @params
    }
    catch {
      Write-Verbose -Message "ヘッダーの取得に失敗しました: $_"
    }
    Write-Verbose -Message "ヘッダーの取得に成功しました: $_"

    # $response.Headers['Content-Disposition'] は配列なので最初の要素を取得
    if ($response.Headers['Content-Disposition'][0]) {
      Write-Verbose -Message "Content-Dispositionヘッダーを検出しました: $($response.Headers['Content-Disposition'][0])"
      if ($response.Headers['Content-Disposition'][0] -match "filename\*=UTF-8''(.+);?") {
        $fileName = [System.Web.HttpUtility]::UrlDecode($Matches[1])
        Write-Verbose -Message "ファイル名を取得しました: $fileName"
        return $fileName
      }
      elseif ($response.Headers['Content-Disposition'][0] -match 'filename="(.+)"') {
        $fileName = $Matches[1]
        Write-Verbose -Message "ファイル名を取得しました: $fileName"
        return $fileName
      }
    }
    else {
      Write-Verbose -Message "Content-Dispositionヘッダーを検出できませんでした: $_"
    }

    Write-Verbose -Message "ファイル名を取得できませんでした: $_"
  }
}
