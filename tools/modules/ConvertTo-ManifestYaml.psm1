# powershell-yaml のインストール
if (-not (Get-Module -Name 'powershell-yaml' -ListAvailable)) {
  try {
    Install-Module -Name 'powershell-yaml' -Force -Repository PSGallery -Scope CurrentUser
  }
  catch {
    throw "powershell-yaml のインストールに失敗しました: $(($_.Exception.Message))"
  }
}

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Test-PackageManifest.psm1')

$ManifestVersion = '0.3.0'
$schemaPath = Join-Path -Path $PSScriptRoot -ChildPath "../../schemas/JSON/manifest/$ManifestVersion.json"

try {
  $Schema = Get-Content -LiteralPath $schemaPath -Raw -ErrorAction Stop | ConvertFrom-Json
}
catch {
  throw "スキーマの読み込みに失敗しました: $(($_.Exception.Message))"
}

function ConvertTo-ManifestYaml {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory, ValueFromPipeline)]
    [object]$Manifest,
    [string]$Header
  )

  if (-not (Test-PackageManifest -Manifest $Manifest)) {
    throw "パッケージマニフェストの検証に失敗しました"
  }

  $orderedManifest = [ordered]@{}

  function Get-OrderedInstall {
    param (
      [Parameter(Mandatory)]
      [object]$Install
    )

    $orderedInstall = [ordered]@{}

    foreach ($key in $Schema.definitions.Install.properties.psobject.Properties.Name) {
      if ($Install[$key]) {
        $orderedInstall.Add($key, $Install[$key])
      }
    }

    $orderedInstall
  }

  function Get-OrderedFilesInArchive {
    param (
      [Parameter(Mandatory)]
      [object]$FilesInArchive
    )

    $orderedFilesInArchive = @()

    foreach ($file in $FilesInArchive) {
      $orderedFile = [ordered]@{}
      foreach ($key in $Schema.definitions.FileInArchive.properties.psobject.Properties.Name) {
        if ($file[$key]) {
          if ($key -eq 'Files') {
            $orderedFile.Add($key, (Get-OrderedFilesInArchive -FilesInArchive $file[$key]))
            continue
          }
          elseif ($key -eq 'Install') {
            $orderedFile.Add($key, (Get-OrderedInstall -Install $file[$key]))
            continue
          }
          $orderedFile.Add($key, $file[$key])
        }
      }
      $orderedFilesInArchive += $orderedFile
    }

    $orderedFilesInArchive
  }

  function Get-OrderedPlugins {
    param (
      [Parameter(Mandatory)]
      [object]$Plugins
    )

    $orderedPlugins = @()

    foreach ($plugin in $Plugins) {
      $orderedPlugin = [ordered]@{}
      foreach ($key in $Schema.definitions.Plugin.properties.psobject.Properties.Name) {
        if ($plugin[$key]) {
          $orderedPlugin.Add($key, $plugin[$key])
        }
      }
      $orderedPlugins += $orderedPlugin
    }

    $orderedPlugins
  }

  foreach ($key in $Schema.properties.psobject.Properties.Name) {
    if ($null -ne $Manifest[$key]) {
      if ($key -eq 'Files') {
        $orderedManifest[$key] = @()
        foreach ($file in $Manifest[$key]) {
          $orderedFile = [ordered]@{}
          foreach ($fileKey in $Schema.definitions.File.properties.psobject.Properties.Name) {
            if ($file[$fileKey]) {
              switch ($fileKey) {
                'FileName' {
                  if ($file[$fileKey] -eq (Split-Path -Path $file['SourceUrl'] -Leaf)) {
                  }
                  else {
                    $orderedFile.Add($fileKey, $file[$fileKey])
                  }
                }
                'Files' {
                  $orderedFile.Add($fileKey, @((Get-OrderedFilesInArchive -FilesInArchive $file[$fileKey])))
                }
                'Install' {
                  $orderedFile.Add($fileKey, (Get-OrderedInstall -Install $file[$fileKey]))
                }
                default {
                  $orderedFile.Add($fileKey, $file[$fileKey])
                }
              }
            }
          }
          $orderedManifest[$key] += $orderedFile
        }
      }
      elseif ($key -eq 'Install') {
        $orderedManifest.Add($key, (Get-OrderedInstall -Install $Manifest[$key]))
      }
      elseif ($key -eq 'Plugins') {
        $orderedManifest[$key] = @()
        foreach ($plugin in $Manifest[$key]) {
          $orderedManifest[$key] += (Get-OrderedPlugins -Plugins $plugin)
        }
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

  $yaml = $orderedManifest | ConvertTo-Yaml

  if ($Header) {
    $yaml = $Header + "`n" + $yaml
  }

  $yaml = $yaml -replace "`r`n", "`n"

  $yaml
}
