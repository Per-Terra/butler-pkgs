### original: https://github.com/microsoft/winget-pkgs/blob/4e76aed0d59412f0be0ecfefabfa14b5df05bec4/Tools/YamlCreate.ps1#L135-L149
# Installs `powershell-yaml` as a dependency for parsing yaml content
if (-not(Get-Module -ListAvailable -Name 'powershell-yaml')) {
  try {
    Install-Module -Name 'powershell-yaml' -Force -Repository PSGallery -Scope CurrentUser
  }
  catch {
    # If there was an exception while installing powershell-yaml, pass it as an InternalException for further debugging
    throw [UnmetDependencyException]::new("'powershell-yaml' unable to be installed successfully", $_.Exception)
  }
  finally {
    # Double check that it was installed properly
    if (-not(Get-Module -ListAvailable -Name powershell-yaml)) {
      throw [UnmetDependencyException]::new("'powershell-yaml' is not found")
    }
  }
}
###

$begin = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ' -AsUTC

$contents = [ordered]@{ '$manifestVersion' = 0 }

# get all manifests
$manifests = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '../manifests') -Filter '*.yaml' -Recurse

# parse manifests
foreach ($manifest in $manifests) {
  if ($manifest.Name -eq 'developer.yaml') {
    $developer = Get-Content -Path $manifest.FullName -Raw | ConvertFrom-Yaml -Ordered
    $identifier = $developer.Identifier
    $developer.Remove('Identifier')
    $developer.Remove('ManifestVersion')
    if ($contents[$identifier]) {
      $contents[$identifier].Add('$developer', $developer)
    }
    else {
      $contents[$identifier] = [ordered]@{ '$developer' = $developer }
    }
  }
  else {
    $package = Get-Content -Path $manifest.FullName -Raw | ConvertFrom-Yaml -Ordered
    $identifier = $package.Identifier
    $version = $package.Version
    $developer = $package.Developer[0]
    $package.Remove('Identifier')
    $package.Remove('Version')
    $package.Remove('ManifestVersion')
    if ($contents[$developer]) {
      if ($contents[$developer][$identifier]) {
        $contents[$developer][$identifier].Add($version, $package)
      }
      else {
        $contents[$developer][$identifier] = [ordered]@{ $version = $package }
      }
    }
    else {
      $contents[$developer] = [ordered]@{ $identifier = [ordered]@{ $version = $package } }
    }
  }
}

# sort by name
$contents = $contents | Sort-Object -Property Name

# sort by release date
foreach ($developer in [array]$contents.Keys) {
  foreach ($identifier in [array]$contents[$developer].Keys) {
    $sortedPackages = [ordered]@{}
    $contents[$developer][$identifier].GetEnumerator() |
    Sort-Object -Property @{
      Expression = {
        if ($null -ne $_.Value.ReleaseDate) {
          [datetime]::ParseExact($_.Value.ReleaseDate, 'yyyy-MM-dd', $null)
        }
        else {
          [datetime]::MinValue
        }
      }
      Descending = $true
    } |
    ForEach-Object {
      $sortedPackages.Add($_.Key, $_.Value)
    }
    $contents[$developer][$identifier] = $sortedPackages
  }
}

# convert to json
$json = ($contents | ConvertTo-Json -Depth 100 -Compress) + "`n"

# gzip compress
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
$stream = [System.IO.MemoryStream]::new()
$gzip = [System.IO.Compression.GzipStream]::new($stream, [System.IO.Compression.CompressionMode]::Compress)
$gzip.Write($bytes, 0, $bytes.Length)
$gzip.Close()
$stream.Close()

# get sha256 hash
$hash = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $hash.ComputeHash($stream.ToArray())
$hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()

# write contents.json.gz
$stream.ToArray() | Set-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '../contents.json.gz') -Force -AsByteStream

# create release.yaml
$release = [ordered]@{
  Date    = $begin
  SHA256  = $hashString
}

# write release.yaml
($release | ConvertTo-Yaml) -replace "`r`n", "`n" |
Out-File -FilePath (Join-Path -Path $PSScriptRoot -ChildPath '../release.yaml') -Encoding utf8NoBOM -Force -NoNewline
