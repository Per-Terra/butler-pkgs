$ManifestVersion = '0.3.0'
$schemaPath = Join-Path -Path $PSScriptRoot -ChildPath "../../schemas/JSON/manifest/$ManifestVersion.json"

try {
  $Schema = Get-Content -LiteralPath $schemaPath -Raw -ErrorAction Stop | ConvertFrom-Json
}
catch {
  throw "スキーマファイルの読み込みに失敗しました: $schemaPath"
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
  ManifestVersion = $Schema.properties.ManifestVersion.enum
}

function Test-PackageManifest {
  [CmdletBinding()]
  param (
    [object]$Manifest,
    [string]$Field,
    [AllowNull()]
    [AllowEmptyString()]
    [string]$Value
  )

  function Test-Install {
    [CmdletBinding()]
    param (
      [Parameter(Mandatory)]
      [object]$Install
    )

    $isValid = $true

    if ($null -eq $Install.TargetPath) {
      Write-Warning "必須フィールドがありません: 'TargetPath'"
      $isValid = $false
    }
    elseif ($Install.TargetPath -notmatch $Schema.definitions.Path.pattern) {
      Write-Warning "フィールド 'TargetPath' の値が正しくありません: $($Install.TargetPath)"
      Write-Warning "次の正規表現に一致する必要があります: $($Schema.definitions.Path.pattern)"
      $isValid = $false
    }

    if ($null -eq $Install.Method) {
      # do nothing
    }
    elseif ($Schema.definitions.InstallMethod.enum -notcontains $Install.Method) {
      Write-Warning "フィールド 'Method' の値が正しくありません: $($Install.Method)"
      Write-Warning "次の値のいずれかに一致する必要があります: $($Schema.definitions.InstallMethod.enum -join ', ')"
      $isValid = $false
    }

    $isValid
  }

  function Test-FileInArchive {
    param (
      [Parameter(Mandatory)]
      [object]$File
    )

    $isValid = $true

    if ($null -eq $File.Path) {
      Write-Warning "必須フィールドがありません: 'Path'"
      $isValid = $false
    }
    elseif ($File.Path -notmatch $Schema.definitions.Path.pattern) {
      Write-Warning "フィールド 'Path' の値が正しくありません: $($File.Path)"
      Write-Warning "次の正規表現に一致する必要があります: $($Schema.definitions.Path.pattern)"
      $isValid = $false
    }

    if ($null -eq $File.SHA256) {
      Write-Warning "必須フィールドがありません: 'SHA256'"
      $isValid = $false
    }
    elseif ($File.SHA256 -notmatch $Schema.definitions.SHA256.pattern) {
      Write-Warning "フィールド 'SHA256' の値が正しくありません: $($File.SHA256)"
      Write-Warning "次の正規表現に一致する必要があります: $($Schema.definitions.SHA256.pattern)"
      $isValid = $false
    }

    if ($File.Files -and $File.Install) {
      Write-Warning "フィールド 'Files' と 'Install' は同時に指定できません"
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

    $isValid
  }

  $isValid = $true

  if ($Manifest) {
    foreach ($field in $Schema.properties.psobject.Properties.Name) {
      $v = $Manifest[$field]
      if ([string]::IsNullOrEmpty($v)) {
        if ($Schema.required -contains $field) {
          Write-Warning "必須フィールドがありません: '$field'"
          $isValid = $false
        }
        continue
      }

      if ($Patterns.ContainsKey($field)) {
        $pattern = $Patterns[$field]
        if ($v -is [string]) {
          if ($pattern -is [array]) {
            if ($pattern -notcontains $v) {
              Write-Warning "フィールド '$field' の値が正しくありません: $v"
              Write-Warning "次の値のいずれかに一致する必要があります: $($pattern -join ', ')"
              $isValid = $false
            }
          }
          elseif ($v -notmatch $pattern) {
            Write-Warning "フィールド '$field' の値が正しくありません: $v"
            Write-Warning "次の正規表現に一致する必要があります: $pattern"
            $isValid = $false
          }
        }
        elseif ($v -is [array]) {
          foreach ($item in $v) {
            if ($item -is [string]) {
              if ($pattern -is [array]) {
                if ($pattern -notcontains $item) {
                  Write-Warning "フィールド '$field' の値が正しくありません: $item"
                  Write-Warning "次の値のいずれかに一致する必要があります: $($pattern -join ', ')"
                  $isValid = $false
                }
              }
              elseif ($item -notmatch $pattern) {
                Write-Warning "フィールド '$field' の値が正しくありません: $item"
                Write-Warning "次の正規表現に一致する必要があります: $pattern"
                $isValid = $false
              }
            }
            else {
              Write-Warning "フィールド '$field' の値が正しくありません: $item"
              Write-Warning "値は string である必要があります"
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
              Write-Warning "Files[$index] の必須フィールドがありません: 'SourceUrl'"
              $isValid = $false
            }
            elseif ($file.SourceUrl -notmatch $Patterns.Url) {
              Write-Warning "Files[$index] のフィールド 'SourceUrl' の値が正しくありません: $($file.SourceUrl)"
              Write-Warning "次の正規表現に一致する必要があります: $($Patterns.Url)"
              $isValid = $false
            }
            if ($file.FileName -and ($file.FileName -notmatch $Schema.definitions.FileName.pattern)) {
              Write-Warning "Files[$index] のフィールド 'FileName' の値が正しくありません: $($file.FileName)"
              Write-Warning "次の正規表現に一致する必要があります: $($Schema.definitions.FileName.pattern)"
              $isValid = $false
            }
            if ($null -eq $file.SHA256) {
              Write-Warning "Files[$index] の必須フィールドがありません: 'SHA256'"
              $isValid = $false
            }
            elseif ($file.SHA256 -notmatch $Schema.definitions.SHA256.pattern) {
              Write-Warning "Files[$index] のフィールド 'SHA256' の値が正しくありません: $($file.SHA256)"
              Write-Warning "次の正規表現に一致する必要があります: $($Schema.definitions.SHA256.pattern)"
              $isValid = $false
            }
            if ($file.Files -and $file.Install) {
              Write-Warning "Files[$index] のフィールド 'Files' と 'Install' は同時に指定できません"
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
      elseif ($field -eq 'Plugins') {
        $plugins = $Manifest[$field]
        if ($plugins) {
          for ($index = 0; $index -lt $plugins.Count; $index++) {
            $plugin = $plugins[$index]
            if ($null -eq $Plugin.Name) {
              Write-Warning "Plugins[$index] の必須フィールドがありません: 'Name'"
              $isValid = $false
            }
            if ($null -eq $Plugin.Type) {
              Write-Warning "Plugins[$index] の必須フィールドがありません: 'Type'"
              $isValid = $false
            }
            elseif ($Plugin.Type -notin $Schema.definitions.Plugin.properties.Type.enum) {
              Write-Warning "Plugins[$index] のフィールド 'Type' の値が正しくありません: $($Plugin.Type)"
              Write-Warning "次の値のいずれかに一致する必要があります: $($Schema.definitions.Plugin.properties.Type.enum -join ', ')"
              $isValid = $false
            }
            if ($null -eq $Plugin.InstallPath) {
              Write-Warning "Plugins[$index] の必須フィールドがありません: 'InstallPath'"
              $isValid = $false
            }
            elseif ($Plugin.InstallPath -notmatch $Schema.definitions.Path.pattern) {
              Write-Warning "Plugins[$index] のフィールド 'InstallPath' の値が正しくありません: $($Plugin.InstallPath)"
              Write-Warning "次の正規表現に一致する必要があります: $($Schema.definitions.Path.pattern)"
              $isValid = $false
            }
          }
        }
      }
      elseif ($Schema.properties.psobject.Properties.Name -notcontains $field) {
        Write-Warning "フィールド '$field' は定義されていません"
        Write-Warning "定義されているフィールドは次の通りです: $($Schema.properties.psobject.Properties.Name -join ', ')"
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
              Write-Warning "フィールド '$Field' の値が正しくありません: $Value"
              Write-Warning "次の値のいずれかに一致する必要があります: $($pattern -join ', ')"
              $isValid = $false
            }
          }
          elseif ($Value -notmatch $pattern) {
            Write-Warning "フィールド '$Field' の値が正しくありません: $Value"
            Write-Warning "次の正規表現に一致する必要があります: $pattern"
            $isValid = $false
          }
        }
        elseif ($Value -is [array]) {
          foreach ($item in $Value) {
            if ($item -is [string]) {
              if ($pattern -is [array]) {
                if ($pattern -notcontains $item) {
                  Write-Warning "フィールド '$Field' の値が正しくありません: $item"
                  Write-Warning "次の値のいずれかに一致する必要があります: $($pattern -join ', ')"
                  $isValid = $false
                }
              }
              elseif ($item -notmatch $pattern) {
                Write-Warning "フィールド '$Field' の値が正しくありません: $item"
                Write-Warning "次の正規表現に一致する必要があります: $pattern"
                $isValid = $false
              }
            }
            else {
              Write-Warning "フィールド '$Field' の値が正しくありません: $item"
              Write-Warning "値は string である必要があります"
              $isValid = $false
            }
          }
        }
      }
      elseif ($Schema.required -contains $Field) {
        Write-Warning "必須フィールドがありません: '$Field'"
        $isValid = $false
      }
    }
    elseif ($Field -eq 'Description') {
      continue
    }
    else {
      Write-Warning "フィールド '$Field' は定義されていません"
      Write-Warning "定義されているフィールドは次の通りです: $($Schema.properties.psobject.Properties.Name -join ', ')"
      $isValid = $false
    }
  }

  $isValid
}
