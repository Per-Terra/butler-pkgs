filter Test-Url {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [string[]]$Url
  )

  $Url | ForEach-Object {
    Write-Verbose -Message "Testing Url: $_"
    try {
      if ([System.Uri]::IsWellFormedUriString($_, [System.UriKind]::Absolute)) {
        if (([System.Uri]$_).Scheme -eq 'http' -or ([System.Uri]$_).Scheme -eq 'https') {
          return $true
        }
        else {
          Write-Verbose -Message "Url scheme is not http or https: $_"
        }
      }
      else {
        Write-Verbose -Message "Url is not well formed: $_"
      }
    }
    catch {
      Write-Verbose -Message "Url is not well formed: $_"
    }
    return $false
  }
}
