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

    Write-Verbose "Trying to get file name from url: $_"

    $extension = Split-Path -Path $_ -Extension
    $response = $null

    if ($_ -match 'https://hazumurhythm\.com/php/amazon_download\.php\?name=(.+)') {
      $id = $Matches[1]
      $response = Invoke-WebRequest -Uri $_ -Method Head -Headers @{ Referer = "https://hazumurhythm.com/wev/amazon/?script=$id" }
    }
    elseif ($extension -and $extension -notmatch '^\.(php)') {
      Write-Verbose "Found file extension in url: $_"
      return Split-Path -Path $_ -Leaf
    }
    else {
      Write-Verbose "No file extension found in url: $_"
      Write-Verbose "Trying to get file name from 'Content-Disposition' header..."
      $response = Invoke-WebRequest -Uri $_ -Method Head
    }

    # $response.Headers['Content-Disposition']は配列なので最初の要素を取得
    if ($response.Headers['Content-Disposition'][0]) {
      if ($response.Headers['Content-Disposition'][0] -match 'filename="(.+)"') {
        Write-Verbose "Found file name from 'Content-Disposition' header: $($Matches[1])"
        return $Matches[1]
      }
      Write-Verbose "No file name found from 'Content-Disposition' header."
    }
    Write-Verbose "No 'Content-Disposition' header found."
  }
}
