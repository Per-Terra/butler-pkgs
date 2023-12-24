. (Join-Path -Path $PSScriptRoot -ChildPath 'Test-Url.ps1')

filter Get-FileNameFromUrl {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [string[]]$Url
  )

  $Url | ForEach-Object {
    if (-not (Test-Url -Url $_)) {
      throw "Invalid Url: $_"
    }

    $fileName = if (Split-Path -Path $_ -Extension) {
      Write-Verbose "Found file extension in url: $_"
      Split-Path -Path $_ -Leaf
    }
    else {
      Write-Verbose "No file extension found in url: $_"
      Write-Verbose "Trying to get file name from 'Content-Disposition' header..."
      $response = Invoke-WebRequest -Uri $_ -Method Head
      if ($response.Headers['Content-Disposition']) {
        if ($response.Headers['Content-Disposition'] -match 'filename="(.+)"') {
          Write-Verbose "Found file name from 'Content-Disposition' header: $($Matches[1])"
          $Matches[1]
        }
        Write-Verbose "No file name found from 'Content-Disposition' header."
      }
      Write-Verbose "No 'Content-Disposition' header found."
    }

    return $fileName
  }
}
