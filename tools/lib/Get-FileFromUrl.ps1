. (Join-Path -Path $PSScriptRoot -ChildPath 'Get-FileNameFromUrl.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'Test-Url.ps1')

function Get-FileFromUrl {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [string]$Url,
    [Parameter(Mandatory = $false)]
    [string]$OutDirectory
  )

  Write-Verbose "Downloading '$Url'..."

  if (-not (Test-Url -Url $Url)) {
    throw "Invalid Url: $Url"
  }

  $fileName = Get-FileNameFromUrl -Url $Url

  if (-not $fileName) {
    Write-Verbose "No file name found in url: $Url"
    $fileName = [System.IO.Path]::GetRandomFileName() + '.tmp'
    Write-Verbose "Generated random file name: $fileName"
  }

  $filePath = Join-Path -Path $OutDirectory -ChildPath $fileName
  Write-Verbose "File path: $filePath"

  if (-not (Test-Path -Path $filePath)) {
    Invoke-WebRequest -Uri $Url -OutFile $filePath
    Write-Verbose "Downloaded '$Url' to '$filePath'."
  }
  else {
    Write-Information -MessageData "'$filePath' already exists." -InformationAction Continue
  }

  return $filePath
}
