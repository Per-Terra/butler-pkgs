filter Test-UrlFormat {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [string[]]$Url
  )

  $Url | ForEach-Object {
    Write-Verbose -Message "URLの形式を検証しています: $_"
    try {
      if ([System.Uri]::IsWellFormedUriString($_, [System.UriKind]::Absolute)) {
        Write-Verbose -Message "正しい形式のURLです: $_"
        if (([System.Uri]$_).Scheme -match '^https?$') {
          Write-Verbose -Message "スキームはhttpまたはhttpsです: $_"
          return $true
        }
        else {
          Write-Verbose -Message "スキームがhttpまたはhttpsではありません: $_"
        }
      }
      else {
        Write-Verbose -Message "URLの形式が正しくありません: $_"
      }
    }
    catch {
      Write-Verbose -Message "URLの形式の検証に失敗しました: $_"
    }
    return $false
  }
}
