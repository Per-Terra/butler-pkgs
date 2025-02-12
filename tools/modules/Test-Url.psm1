function Test-Url {
  [CmdletBinding()]
  [OutputType([bool])]
  param (
    [Parameter(Mandatory, ValueFromPipeline)]
    [string[]]$Url
  )

  process {
    foreach ($item in $Url) {
      Write-Verbose -Message "URLの形式を検証しています: $item"
      if ([System.Uri]::IsWellFormedUriString($item, [System.UriKind]::Absolute)) {
        Write-Verbose -Message "正しい形式のURLです: $item"
        if (([System.Uri]$item).Scheme -match '^https?$') {
          Write-Verbose -Message "スキームはhttpまたはhttpsです: $item"
          $true
        }
        else {
          Write-Verbose -Message "スキームがhttpまたはhttpsではありません: $item"
          $false
        }
      }
      else {
        Write-Verbose -Message "正しい形式のURLではありません: $item"
        $false
      }
    }
  }
}
