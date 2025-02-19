[CmdletBinding()]
param (
  [Parameter(Mandatory)]
  [string]$FromManifestPath,
  [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
  [Alias('FullName')]
  [string[]]$ToManifestPath,
  [switch]$ReturnCriticalChange
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

  # Load the schema file
  $ManifestVersion = '0.3.0'
  $schemaPath = Join-Path -Path $PSScriptRoot -ChildPath "../schemas/JSON/manifest/$ManifestVersion.json"
  try {
    $Schema = Get-Content -LiteralPath $schemaPath -Raw -ErrorAction Stop | ConvertFrom-Json
  }
  catch {
    throw "Failed to parse the schema file '$schemaPath'."
  }

  # Check if the from manifest path exists
  if (-not (Test-Path -Path $FromManifestPath)) {
    throw "The path '$FromManifestPath' does not exist."
  }

  # Load the from manifest file
  try {
    $fromManifest = Get-Content -LiteralPath $FromManifestPath -Raw | ConvertFrom-Yaml -Ordered
  }
  catch {
    throw "Failed to parse the from manifest file '$FromManifestPath'."
  }

  # Check if the from manifest is null or empty
  if ($null -eq $fromManifest) {
    throw "The content of the from manifest file '$FromManifestPath' is null or empty."
  }

  $criticalChange = $false
}

process {
  foreach ($path in $ToManifestPath) {
    # Check if the path exists
    if (-not (Test-Path -Path $path)) {
      Write-Error "The path '$path' does not exist."
      continue
    }

    # Load the manifest file
    try {
      $toManifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Yaml -Ordered
    }
    catch {
      Write-Error "Failed to parse the manifest file '$path'."
      continue
    }

    # Check if the manifest is null or empty
    if ($null -eq $toManifest) {
      Write-Error "The content of the manifest file '$path' is null or empty."
      continue
    }

    Write-Host "Comparing manifest files '$FromManifestPath' and '$path'..."
    foreach ($field in $Schema.properties.psobject.Properties.Name) {
      if ($null -eq $fromManifest[$field] -and $null -eq $toManifest[$field]) {
        Write-Verbose "Field '$field' is not defined."
        continue
      }
      if ($Schema.properties.$field.type -eq 'array') {
        switch ($field) {
          Files {
            Write-Verbose 'Comparing Files...'
            if ($null -eq $fromManifest[$field] -and $null -ne $toManifest[$field]) {
              Write-Host -NoNewline -ForegroundColor Red '[Critical] '
              Write-Host -NoNewline "Field '$field' is added: "
              Write-Host -NoNewline -ForegroundColor Red 'N/A'
              Write-Host -NoNewline ' -> '
              Write-Host -ForegroundColor Green (($toManifest[$field] | ForEach-Object { $_.SourceUrl }) -join ', ')
              $criticalChange = $true
            }
            elseif ($null -ne $fromManifest[$field] -and $null -eq $toManifest[$field]) {
              Write-Host -NoNewline -ForegroundColor Red '[Critical] '
              Write-Host -NoNewline "Field '$field' is removed: "
              Write-Host -NoNewline (($fromManifest[$field] | ForEach-Object { $_.SourceUrl }) -join ', ')
              Write-Host -NoNewline ' -> '
              Write-Host -ForegroundColor Red 'N/A'
              $criticalChange = $true
            }
            else {
              if ($fromManifest[$field].Count -ne $toManifest[$field].Count) {
                Write-Host -NoNewline -ForegroundColor Red '[Critical] '
                Write-Host "Field '$field' is changed: Number of Files is different."
                Write-Warning 'Comparing Files is skipped.'
                $criticalChange = $true
              }
              else {
                for ($i = 0; $i -lt $fromManifest[$field].Count; $i++) {
                  $fromFile = $fromManifest[$field][$i].Files
                  $toFile = $toManifest[$field][$i].Files
                  $diff = Compare-Object -ReferenceObject $fromFile -DifferenceObject $toFile -Property Path -PassThru
                  if ($null -eq $diff) {
                    Write-Verbose 'No Files are Added or Removed.'
                  }
                  else {
                    Write-Host "Some Files are Added or Removed:"
                    $removed = $diff.Where({ $_.SideIndicator -eq '<=' })
                    $added = $diff.Where({ $_.SideIndicator -eq '=>' })
                    if ($removed) {
                      Write-Host -NoNewline "  Removed Files: `n    "
                      Write-Host -ForegroundColor Red (($removed | ForEach-Object { $_.Path }) -join "`n    ")
                    }
                    if ($added) {
                      Write-Host -NoNewline -ForegroundColor Red '  [Critical] '
                      Write-Host -NoNewline "Added Files: `n    "
                      Write-Host -ForegroundColor Green (($added | ForEach-Object { $_.Path }) -join "`n    ")
                      $criticalChange = $true
                    }
                  }
                }
              }
            }
          }
          Plugins {
            Write-Verbose 'Comparing Plugins...'
            if ($null -eq $fromManifest[$field] -and $null -ne $toManifest[$field]) {
              Write-Host -NoNewline -ForegroundColor Red '[Critical] '
              Write-Host -NoNewline "Field '$field' is added: "
              Write-Host -NoNewline -ForegroundColor Red 'N/A'
              Write-Host -NoNewline ' -> '
              Write-Host -ForegroundColor Green (($toManifest[$field] | ForEach-Object { "$($_.Name) ($($_.InstallPath))" }) -join ', ')
              $criticalChange = $true
            }
            elseif ($null -ne $fromManifest[$field] -and $null -eq $toManifest[$field]) {
              Write-Host -NoNewline -ForegroundColor Red '[Critical] '
              Write-Host -NoNewline "Field '$field' is removed: "
              Write-Host -NoNewline (($fromManifest[$field] | ForEach-Object { "$($_.Name) ($($_.InstallPath))" }) -join ', ')
              Write-Host -NoNewline ' -> '
              Write-Host -ForegroundColor Red 'N/A'
              $criticalChange = $true
            }
            else {
              $diff = Compare-Object -ReferenceObject $fromManifest[$field] -DifferenceObject $toManifest[$field] -Property InstallPath -PassThru
              if ($null -eq $diff) {
                Write-Verbose 'No Plugins are Added or Removed.'
              }
              else {
                Write-Host -NoNewline -ForegroundColor Red '[Critical] '
                Write-Host "Some Plugins are Added or Removed:"
                $removed = $diff.Where({ $_.SideIndicator -eq '<=' })
                $added = $diff.Where({ $_.SideIndicator -eq '=>' })
                if ($removed) {
                  Write-Host -NoNewline '  Removed Plugins: '
                  Write-Host -ForegroundColor Red (($removed | ForEach-Object { "$($_.Name) ($($_.InstallPath))" }) -join ', ')
                }
                if ($added) {
                  Write-Host -NoNewline '  Added Plugins: '
                  Write-Host -ForegroundColor Green (($added | ForEach-Object { "$($_.Name) ($($_.InstallPath))" }) -join ', ')
                }
                $criticalChange = $true
              }
            }
          }
          default {
            if ($null -eq $fromManifest[$field] -and $null -ne $toManifest[$field]) {
              Write-Host -NoNewline -ForegroundColor Red '[Critical] '
              Write-Host -NoNewline "Field '$field' is added: "
              Write-Host -NoNewline -ForegroundColor Red 'N/A'
              Write-Host -NoNewline ' -> '
              Write-Host -ForegroundColor Green ($toManifest[$field] -join ', ')
              $criticalChange = $true
            }
            elseif ($null -ne $fromManifest[$field] -and $null -eq $toManifest[$field]) {
              Write-Host -NoNewline -ForegroundColor Red '[Critical] '
              Write-Host -NoNewline "Field '$field' is removed: "
              Write-Host -NoNewline ($fromManifest[$field] -join ', ')
              Write-Host -NoNewline ' -> '
              Write-Host -ForegroundColor Red 'N/A'
              $criticalChange = $true
            }
            else {
              $diff = Compare-Object -ReferenceObject $fromManifest[$field] -DifferenceObject $toManifest[$field]
              if ($null -eq $diff) {
                Write-Verbose "Field '$field' is the same: $($fromManifest[$field])"
              }
              else {
                Write-Host "Field '$field' is changed:"
                $removed = $diff.Where({ $_.SideIndicator -eq '<=' }).InputObject
                $added = $diff.Where({ $_.SideIndicator -eq '=>' }).InputObject
                if ($null -ne $removed) {
                  Write-Host -NoNewline '  Removed: '
                  Write-Host -ForegroundColor Red ($removed -join ', ')
                }
                if ($null -ne $added) {
                  Write-Host -NoNewline '  Added: '
                  Write-Host -ForegroundColor Green ($added -join ', ')
                }
              }
            }
          }
        }
      }
      else {
        if ($fromManifest[$field] -eq $toManifest[$field]) {
          Write-Verbose "Field '$field' is the same: $($fromManifest[$field])"
        }
        elseif ($null -eq $fromManifest[$field] -and $null -ne $toManifest[$field]) {
          Write-Host -NoNewline -ForegroundColor Red '[Critical] '
          Write-Host -NoNewline "Field '$field' is added: "
          Write-Host -NoNewline -ForegroundColor Red 'N/A'
          Write-Host -NoNewline ' -> '
          Write-Host -ForegroundColor Green $toManifest[$field]
          $criticalChange = $true
        }
        elseif ($null -ne $fromManifest[$field] -and $null -eq $toManifest[$field]) {
          Write-Host -NoNewline -ForegroundColor Red '[Critical] '
          Write-Host -NoNewline "Field '$field' is removed: "
          Write-Host -NoNewline $fromManifest[$field]
          Write-Host -NoNewline ' -> '
          Write-Host -ForegroundColor Red 'N/A'
          $criticalChange = $true
        }
        else {
          Write-Host -NoNewline "Field '$field' is changed: "
          Write-Host -NoNewline $fromManifest[$field]
          Write-Host -NoNewline ' -> '
          Write-Host -ForegroundColor Green $toManifest[$field]
        }
      }
    }
  }
}

end {
  if ($criticalChange) {
    Write-Host -ForegroundColor Red "There are critical changes in the manifest files."
  }
  else {
    Write-Host -ForegroundColor Green "There are no critical changes in the manifest files."
  }

  if ($ReturnCriticalChange) {
    $criticalChange
  }
}
