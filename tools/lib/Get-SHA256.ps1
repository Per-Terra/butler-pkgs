filter Get-SHA256 {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [string[]]$Path
  )

  $Path | ForEach-Object {
    Write-Verbose -Message "Getting SHA256 hash for: $_"
    if (Test-Path -Path $_) {
      try {
        return (Get-FileHash -Path $_ -Algorithm SHA256).Hash.ToLower()
      }
      catch {
        Write-Error -Message "Failed to get SHA256 hash for: $_"
      }
    }
    else {
      Write-Error -Message "Path does not exist: $_"
    }
  }
}
