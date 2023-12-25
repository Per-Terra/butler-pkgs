. (Join-Path -Path $PSScriptRoot -ChildPath 'Test-PackageManifest.ps1')

### original: https://github.com/microsoft/winget-pkgs/blob/4e76aed0d59412f0be0ecfefabfa14b5df05bec4/Tools/YamlCreate.ps1#L135-L149
### modified: Remove the NuGet installation and throw without type
# Installs `powershell-yaml` as a dependency for parsing yaml content
if (-not(Get-Module -ListAvailable -Name 'powershell-yaml')) {
  try {
    Install-Module -Name 'powershell-yaml' -Force -Repository PSGallery -Scope CurrentUser
  }
  catch {
    # If there was an exception while installing powershell-yaml, pass it as an InternalException for further debugging
    throw "'powershell-yaml' unable to be installed successfully"
  }
  finally {
    # Double check that it was installed properly
    if (-not(Get-Module -ListAvailable -Name powershell-yaml)) {
      throw "'powershell-yaml' is not found"
    }
  }
}
###

$ManifestVersion = '0.1.0'

try {
  $Schema = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath "../../schemas/JSON/manifests/$ManifestVersion.json") -Raw -ErrorAction Stop | ConvertFrom-Json
}
catch {
  throw "Failed to load schema for manifest version $ManifestVersion"
}

function ConvertTo-ManifestYaml {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [object]$Manifest
  )

  if (-not (Test-PackageManifest -Manifest $Manifest)) {
    throw "Invalid manifest"
  }

  $orderedManifest = [ordered]@{}

  function Get-OrderedInstall {
    param (
      [Parameter(Mandatory = $true,
        ValueFromPipeline = $true)]
      [object]$Install
    )

    $orderedInstall = [ordered]@{}

    foreach ($key in $Schema.definitions.Install.properties.psobject.Properties.Name) {
      if ($Install[$key]) {
        $orderedInstall.Add($key, $Install[$key])
      }
    }

    return $orderedInstall
  }

  function Get-OrderedFilesInArchive {
    param (
      [Parameter(Mandatory = $true,
        ValueFromPipeline = $true)]
      [object]$FilesInArchive
    )

    $orderedFilesInArchive = @()

    foreach ($file in $FilesInArchive) {
      $orderedFile = [ordered]@{}
      foreach ($fileKey in $Schema.definitions.FileInArchive.properties.psobject.Properties.Name) {
        if ($file[$fileKey]) {
          if ($fileKey -eq 'Files') {
            $orderedFile.Add($fileKey, (Get-OrderedFilesInArchive -FilesInArchive $file[$fileKey]))
            continue
          }
          elseif ($fileKey -eq 'Install') {
            $orderedFile.Add($fileKey, (Get-OrderedInstall -Install $file[$fileKey]))
            continue
          }
          $orderedFile.Add($fileKey, $file[$fileKey])
        }
      }
      $orderedFilesInArchive += $orderedFile
    }

    return $orderedFilesInArchive
  }

  foreach ($key in $Schema.properties.psobject.Properties.Name) {
    if ($null -ne $Manifest[$key]) {
      if ($key -eq 'Files') {
        $orderedManifest[$key] = @()
        foreach ($file in $Manifest[$key]) {
          $orderedFile = [ordered]@{}
          foreach ($fileKey in $Schema.definitions.File.properties.psobject.Properties.Name) {
            if ($file[$fileKey]) {
              if ($fileKey -eq 'FileName' -and ($file[$fileKey] -eq (Split-Path -Path $file['SourceUrl'] -Leaf))) {
                continue
              }
              elseif ($fileKey -eq 'Files') {
                $orderedFile.Add($fileKey, (Get-OrderedFilesInArchive -FilesInArchive $file[$fileKey]))
                continue
              }
              elseif ($fileKey -eq 'Install') {
                $orderedFile.Add($fileKey, (Get-OrderedInstall -Install $file[$fileKey]))
                continue
              }
              $orderedFile.Add($fileKey, $file[$fileKey])
            }
          }
          $orderedManifest[$key] += $orderedFile
        }
      }
      elseif ($key -eq 'Install') {
        $orderedManifest.Add($key, (Get-OrderedInstall -Install $Manifest[$key]))
      }
      else {
        if ($Schema.properties.$key.type -eq 'array') {
          if ($Manifest[$key]) {
            $orderedManifest[$key] = @()
            foreach ($item in $Manifest[$key]) {
              $orderedManifest[$key] += $item
            }
          }
        }
        else {
          $orderedManifest.Add($key, $Manifest[$key])
        }
      }
    }
  }

  $Header = @"
# Created using CreateManifest.ps1 v$ScriptVersion
# yaml-language-server: `$schema=https://raw.githubusercontent.com/Per-Terra/butler-pkgs/main/schemas/JSON/manifests/$ManifestVersion.json

"@

  $yaml = ($Header + "`n" + ($orderedManifest | ConvertTo-Yaml)) -replace "`r`n", "`n"

  return $yaml
}
