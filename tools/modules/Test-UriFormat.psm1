function Test-UriFormat {
  [CmdletBinding()]
  [OutputType([bool])]
  param (
    [Parameter(Mandatory, ValueFromPipeline)]
    [string[]]$Uri
  )

  process {
    foreach ($item in $Uri) {
      Write-Verbose -Message "URIの形式を検証しています: $item"
      if ([System.Uri]::IsWellFormedUriString($item, [System.UriKind]::Absolute)) {
        Write-Verbose -Message "正しい形式のURIです: $item"
        $true
      }
      else {
        Write-Verbose -Message "正しい形式のURIではありません: $item"
        $false
      }
    }
  }
}
