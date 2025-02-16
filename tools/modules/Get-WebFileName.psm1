function Get-WebFileName {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory, ValueFromPipeline)]
    [string[]]$Uri
  )

  process {
    foreach ($item in $Uri) {
      Write-Verbose "ファイル名を取得しています: $item"

      if ($item -match 'https://scrapbox.io/files/(?:.+)\?title=(.+)') {
        Write-Verbose "Cosense のリンクを検出しました: $item"
        return $Matches[1]
      }

      if (-not ($item -contains 'https://storage.googleapis.com/')) {
        Write-Verbose "Google Cloud Storage のリンクを検出しました: $item"
      }
      else {
        $extension = Split-Path -Path $item -Extension
        if ($extension -and ($extension -notmatch '^\.(php)')) {
          Write-Verbose "URIにファイル名が含まれています: $item"
          return Split-Path -Path $item -Leaf
        }
      }

      $params = @{
        Uri    = $item
        Method = 'Head'
      }

      if ($item -match 'https://hazumurhythm\.com/php/amazon_download\.php\?name=(.+)') {
        Write-Verbose "アマゾンっぽい のリンクを検出しました: $item"
        $id = $Matches[1]
        Write-Verbose "ファイルのID: $id"
        $params.Add('Headers', @{ Referer = "https://hazumurhythm.com/wev/amazon/?script=$id" })
      }

      Write-Verbose "ヘッダーを取得しています: $item"

      try {
        $response = Invoke-WebRequest @params
      }
      catch {
        Write-Verbose "ヘッダーの取得に失敗しました: $($_.Exception.Message)"
      }

      # $response.Headers['Content-Disposition'] は配列なので最初の要素を取得
      $contentDisposition = $response.Headers['Content-Disposition'][0]
      if ($contentDisposition) {
        Write-Verbose "Content-Dispositionヘッダーを検出しました: $contentDisposition"
        if ($contentDisposition -match "filename\*=UTF-8''(.+);?") {
          $fileName = [System.Web.HttpUtility]::UrlDecode($Matches[1])
          return $fileName
        }
        elseif ($contentDisposition -match 'filename="(.+)"') {
          $fileName = $Matches[1]

          # 一部のサイトでファイル名が文字化けする問題を修正
          if (
            $item.StartsWith('https://drive.google.com/') -or
            $item.StartsWith('https://hazumurhythm.com/')
          ) {
            Write-Verbose "ファイル名をデコードしています: $fileName"
            $fileName = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::GetEncoding('iso-8859-1').GetBytes($fileName))
          }

          return $fileName
        }
        else {
          Write-Verbose "Content-Dispositionヘッダーにファイル名が含まれていません: $contentDisposition"
        }
      }
      else {
        Write-Verbose "Content-Dispositionヘッダーがありません: $item"
      }

      Write-Verbose "ファイル名を取得できませんでした: $item"
    }
  }
}
