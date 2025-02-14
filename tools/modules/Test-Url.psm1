function Test-Url {
  [CmdletBinding()]
  [OutputType([bool])]
  param (
    [Parameter(Mandatory, ValueFromPipeline)]
    [string[]]$Url
  )

  process {
    foreach ($item in $Url) {
      Write-Verbose "URLの形式を検証しています: $item"
      if ([System.Uri]::IsWellFormedUriString($item, [System.UriKind]::Absolute)) {
        Write-Verbose "正しい形式のURLです: $item"
        if (([System.Uri]$item).Scheme -match '^https?$') {
          Write-Verbose "スキームはhttpまたはhttpsです: $item"
          $true
        }
        else {
          Write-Verbose "スキームがhttpまたはhttpsではありません: $item"
          $false
        }
      }
      else {
        Write-Verbose "正しい形式のURLではありません: $item"
        $false
      }
    }
  }
}
