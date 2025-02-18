[CmdletBinding()]
param (
  [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
  [Alias('FullName')]
  [string[]]$ManifestPath
)

begin {
  # Install powershell-yaml if not installed
  if (-not (Get-Module -Name 'powershell-yaml' -ListAvailable)) {
    try {
      Install-Module -Name 'powershell-yaml' -Force -Repository PSGallery -Scope CurrentUser
    }
    catch {
      throw "Failed to install powershell-yaml: $($_.Exception.Message)"
    }
  }

  Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath './modules/Test-PackageManifest.psm1')
  $invalidManifests = @()
}

process {
  foreach ($path in $ManifestPath) {
    # Check if the path exists
    if (-not (Test-Path -Path $path)) {
      Write-Error "The path '$path' does not exist."
      $invalidManifests += $path
      continue
    }

    # Load the manifest file
    try {
      $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Yaml -Ordered
    }
    catch {
      Write-Error "Failed to parse the manifest file '$path'."
      $invalidManifests += $path
      continue
    }

    # Check if the manifest is null or empty
    if ($null -eq $manifest) {
      Write-Error "The content of the manifest file '$path' is null or empty."
      $invalidManifests += $path
      continue
    }

    # Check if the manifest is valid
    Write-Host "Checking manifest file '$path'..."
    if (-not (Test-PackageManifest -Manifest $manifest)) {
      Write-Error "The manifest file '$path' is invalid."
      $invalidManifests += $path
      continue
    }

    # Check Filename matches the Version value in the manifest
    $filename = [System.IO.Path]::GetFileNameWithoutExtension($path)
    if ($filename -ne $manifest.Version) {
      Write-Warning "The filename '$filename' does not match the Version value in the manifest."
      $invalidManifests += $path
      continue
    }
  }
}

end {
  if ($invalidManifests) {
    Write-Error 'The manifest file(s) is/are invalid.'
    foreach ($invalid in $invalidManifests) {
      Write-Error "Invalid manifest: $invalid"
    }
    exit 1
  }

  Write-Host -ForegroundColor Green 'The manifest file(s) is/are valid.'
  exit 0
}
