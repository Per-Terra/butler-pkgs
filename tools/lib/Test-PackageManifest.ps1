$ManifestVersion = '0.1.0'

try {
  $Schema = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath "../../schemas/JSON/manifests/$ManifestVersion.json") -Raw -ErrorAction Stop | ConvertFrom-Json
}
catch {
  throw "Failed to load schema for manifest version $ManifestVersion"
}

$Patterns = @{
  Identifier      = $Schema.definitions.Identifier.pattern
  DisplayName     = $Schema.definitions.DisplayName.pattern
  Version         = $Schema.definitions.Identifier.pattern
  ReleaseDate     = $Schema.definitions.FullDate.pattern
  Section         = $Schema.definitions.Section.enum
  Architecture    = $Schema.definitions.Architecture.enum
  Depends         = $Schema.definitions.PackageRelationship.pattern
  Recommends      = $Schema.definitions.PackageRelationship.pattern
  Suggests        = $Schema.definitions.PackageRelationship.pattern
  Enhances        = $Schema.definitions.PackageRelationship.pattern
  Breaks          = $Schema.definitions.PackageRelationship.pattern
  Conflicts       = $Schema.definitions.PackageRelationship.pattern
  Provides        = $Schema.definitions.PackageRelationship.pattern
  Replaces        = $Schema.definitions.PackageRelationship.pattern
  Developer       = $Schema.definitions.Identifier.pattern
  Website         = $Schema.definitions.Url.pattern
  ConfFiles       = $Schema.definitions.Path.pattern
  ManifestVersion = 0
}

function Test-PackageManifest {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $false,
      ValueFromPipeline = $true)]
    [object]$Manifest,
    [Parameter(Mandatory = $false)]
    [string]$Field,
    [Parameter(Mandatory = $false)]
    [AllowNull()]
    [AllowEmptyString()]
    [string]$Value
  )

  function Test-Install {
    [CmdletBinding()]
    param (
      [Parameter(Mandatory = $true,
        ValueFromPipeline = $true)]
      [object]$Install
    )

    $isValid = $true

    if ($null -eq $Install.TargetPath) {
      Write-Warning -Message "Missing required field 'TargetPath'"
      $isValid = $false
    }
    elseif ($Install.TargetPath -notmatch $Schema.definitions.Path.pattern) {
      Write-Warning -Message "Invalid value '$($Install.TargetPath)' for field 'TargetPath'"
      Write-Warning -Message "Valid pattern is: $($Schema.definitions.Path.pattern)"
      $isValid = $false
    }
    if ($null -eq $Install.Method) {
      # do nothing
    }
    elseif ($Schema.definitions.InstallMethod.enum -notcontains $Install.Method) {
      Write-Warning -Message "Invalid value '$($Install.Method)' for field 'Method'"
      Write-Warning -Message "Valid values are: $($Schema.definitions.InstallMethod.enum -join ', ')"
      $isValid = $false
    }

    return $isValid
  }

  function Test-FileInArchive {
    param (
      [Parameter(Mandatory = $true,
        ValueFromPipeline = $true)]
      [object]$File
    )

    $isValid = $true

    if ($null -eq $File.Path) {
      Write-Warning -Message "Missing required field 'Path'"
      $isValid = $false
    }
    elseif ($File.Path -notmatch $Schema.definitions.Path.pattern) {
      Write-Warning -Message "Invalid value '$($File.Path)' for field 'Path'"
      Write-Warning -Message "Valid pattern is: $($Schema.definitions.Path.pattern)"
      $isValid = $false
    }
    if ($null -eq $File.SHA256) {
      Write-Warning -Message "Missing required field 'SHA256'"
      $isValid = $false
    }
    elseif ($File.SHA256 -notmatch $Patterns.Sha256) {
      Write-Warning -Message "Invalid value '$($File.SHA256)' for field 'SHA256'"
      Write-Warning -Message "Valid pattern is: $($Patterns.Sha256)"
      $isValid = $false
    }
    if ($File.Files -and $File.Install) {
      Write-Warning -Message "File cannot have both 'Files' and 'Install' fields"
      $isValid = $false
    }
    if ($File.Files) {
      foreach ($file in $File.Files) {
        $isValid = $isValid -and (Test-FileInArchive -File $file)
      }
    }
    if ($File.Install) {
      $isValid = $isValid -and (Test-Install -Install $File.Install)
    }

    return $isValid
  }

  $isValid = $true

  if ($Manifest) {
    foreach ($field in $Schema.properties.psobject.Properties.Name) {
      $value = $Manifest[$field]
      if ([string]::IsNullOrEmpty($value)) {
        if ($Schema.required -contains $field) {
          Write-Warning -Message "Missing required field '$field'"
          $isValid = $false
        }
        continue
      }
      if ($Patterns.ContainsKey($field)) {
        $pattern = $Patterns[$field]
        if ($value -is [string]) {
          if ($pattern -is [array]) {
            if ($pattern -notcontains $value) {
              Write-Warning -Message "Invalid value '$value' for field '$field'"
              Write-Warning -Message "Valid values are: $($pattern -join ', ')"
              $isValid = $false
            }
          }
          elseif ($value -notmatch $pattern) {
            Write-Warning -Message "Invalid value '$value' for field '$field'"
            Write-Warning -Message "Valid pattern is: $pattern"
            $isValid = $false
          }
        }
        elseif ($value -is [array]) {
          foreach ($item in $value) {
            if ($item -is [string]) {
              if ($pattern -is [array]) {
                if ($pattern -notcontains $item) {
                  Write-Warning -Message "Invalid value '$item' for field '$field'"
                  Write-Warning -Message "Valid values are: $($pattern -join ', ')"
                  $isValid = $false
                }
              }
              elseif ($item -notmatch $pattern) {
                Write-Warning -Message "Invalid value '$item' for field '$field'"
                Write-Warning -Message "Valid pattern is: $pattern"
                $isValid = $false
              }
            }
            else {
              Write-Warning -Message "Invalid value '$item' for field '$field'"
              Write-Warning -Message "Value must be a string"
              $isValid = $false
            }
          }
        }
      }
      elseif ($field -eq 'Description') {
        continue
      }
      elseif ($field -eq 'Files') {
        $files = $Manifest[$field]
        if ($files) {
          for ($index = 0; $index -lt $files.Count; $index++) {
            $file = $files[$index]
            if ($null -eq $file.SourceUrl) {
              Write-Warning -Message "Missing required field 'SourceUrl' for file $index"
              $isValid = $false
            }
            elseif ($file.SourceUrl -notmatch $Patterns.Url) {
              Write-Warning -Message "Invalid value '$($file.SourceUrl)' for field 'SourceUrl' for file $index"
              Write-Warning -Message "Valid pattern is: $($Patterns.Url)"
              $isValid = $false
            }
            if ($FileName -and ($FileName -notmatch $Schema.definitions.FileName.pattern)) {
              Write-Warning -Message "Invalid value '$($file.FileName)' for field 'FileName' for file $index"
              Write-Warning -Message "Valid pattern is: $($Schema.definitions.FileName.pattern)"
              $isValid = $false
            }
            if ($null -eq $file.SHA256) {
              Write-Warning -Message "Missing required field 'SHA256' for file $index"
              $isValid = $false
            }
            elseif ($file.SHA256 -notmatch $Patterns.Sha256) {
              Write-Warning -Message "Invalid value '$($file.SHA256)' for field 'SHA256' for file $index"
              Write-Warning -Message "Valid pattern is: $($Patterns.Sha256)"
              $isValid = $false
            }
            if ($file.Files -and $file.Install) {
              Write-Warning -Message "File $index cannot have both 'Files' and 'Install' fields"
              $isValid = $false
            }
            if ($file.Files) {
              foreach ($file in $file.Files) {
                $isValid = $isValid -and (Test-FileInArchive -File $file)
              }
            }
            if ($file.Install) {
              $isValid = $isValid -and (Test-Install -Install $file.Install)
            }
          }
        }
      }
      elseif ($Schema.properties.psobject.Properties.Name -notcontains $field) {
        Write-Warning -Message "Invalid field '$field'"
        Write-Warning -Message "Valid fields are: $($Schema.properties.psobject.Properties.Name -join ', ')"
        $isValid = $false
      }
    }
  }

  if ($Field -and $Value) {
    if ($Patterns.ContainsKey($Field)) {
      $pattern = $Patterns[$Field]
      if ($Value) {
        if ($Value -is [string]) {
          if ($pattern -is [array]) {
            if ($pattern -notcontains $Value) {
              Write-Warning -Message "Invalid value '$Value' for field '$Field'"
              Write-Warning -Message "Valid values are: $($pattern -join ', ')"
              $isValid = $false
            }
          }
          elseif ($Value -notmatch $pattern) {
            Write-Warning -Message "Invalid value '$Value' for field '$Field'"
            Write-Warning -Message "Valid pattern is: $pattern"
            $isValid = $false
          }
        }
        elseif ($Value -is [array]) {
          foreach ($item in $Value) {
            if ($item -is [string]) {
              if ($pattern -is [array]) {
                if ($pattern -notcontains $item) {
                  Write-Warning -Message "Invalid value '$item' for field '$Field'"
                  Write-Warning -Message "Valid values are: $($pattern -join ', ')"
                  $isValid = $false
                }
              }
              elseif ($item -notmatch $pattern) {
                Write-Warning -Message "Invalid value '$item' for field '$Field'"
                Write-Warning -Message "Valid pattern is: $pattern"
                $isValid = $false
              }
            }
            else {
              Write-Warning -Message "Invalid value '$item' for field '$Field'"
              Write-Warning -Message "Value must be a string"
              $isValid = $false
            }
          }
        }
      }
      elseif ($Schema.required -contains $Field) {
        Write-Warning -Message "Value for required field '$Field' cannot be null"
        $isValid = $false
      }
    }
    elseif ($Field -eq 'Description') {
      continue
    }
    else {
      Write-Warning -Message "Invalid field '$Field'"
      Write-Warning -Message "Valid fields are: $($Schema.properties.psobject.Properties.Name -join ', ')"
      $isValid = $false
    }
  }

  return $isValid
}
