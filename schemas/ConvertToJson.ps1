### original: https://github.com/microsoft/winget-pkgs/blob/4e76aed0d59412f0be0ecfefabfa14b5df05bec4/Tools/YamlCreate.ps1#L135-L149
# Installs `powershell-yaml` as a dependency for parsing yaml content
if (-not(Get-Module -ListAvailable -Name 'powershell-yaml')) {
  try {
    Install-Module -Name 'powershell-yaml' -Force -Repository PSGallery -Scope CurrentUser
  } catch {
    # If there was an exception while installing powershell-yaml, pass it as an InternalException for further debugging
    throw [UnmetDependencyException]::new("'powershell-yaml' unable to be installed successfully", $_.Exception)
  } finally {
    # Double check that it was installed properly
    if (-not(Get-Module -ListAvailable -Name powershell-yaml)) {
      throw [UnmetDependencyException]::new("'powershell-yaml' is not found")
    }
  }
}
###

$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false

$yamlFolder = Join-Path -Path $PSScriptRoot -ChildPath YAML
$jsonFolder = Join-Path -Path $PSScriptRoot -ChildPath JSON

if (-not (Test-Path $jsonFolder)) {
  New-Item -Path $jsonFolder -ItemType Directory
}

$yamlFiles = Get-ChildItem -Path $yamlFolder -Filter '*.yaml' -Recurse -File

$yamlFiles | ForEach-Object {
  $jsonPath = $_.FullName.Replace($yamlFolder, $jsonFolder).Replace('.yaml', '.json')
  if (-not (Test-Path (Split-Path -Path $jsonPath -Parent))) {
    $null = New-Item -Path (Split-Path -Path $jsonPath -Parent) -ItemType Directory
  }

  try {
    Get-Content -Path $_.FullName -Raw |
    ConvertFrom-Yaml -Ordered |
    ConvertTo-JSON -Depth 100 |
    Out-File -FilePath $jsonPath -Encoding $Utf8NoBomEncoding -Force
  } catch {
    throw "Failed to convert $_ to JSON"
  }
}
