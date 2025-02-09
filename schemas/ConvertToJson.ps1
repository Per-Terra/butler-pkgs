# powershell-yaml のインストール
if (-not (Get-Module -Name 'powershell-yaml' -ListAvailable)) {
  try {
    Install-Module -Name 'powershell-yaml' -Force -Repository PSGallery -Scope CurrentUser
  }
  catch {
    throw "powershell-yaml のインストールに失敗しました: $(($_.Exception.Message))"
  }
}

$yamlDirectory = Join-Path -Path $PSScriptRoot -ChildPath YAML
Write-Host "YAMLファイルのディレクトリ: $yamlDirectory"
$jsonDirectory = Join-Path -Path $PSScriptRoot -ChildPath JSON
Write-Host "JSONファイルのディレクトリ: $jsonDirectory"

if (-not (Test-Path -LiteralPath $jsonDirectory -PathType Container)) {
  Write-Host "JSONファイルのディレクトリを作成しています: $jsonDirectory"
  try {
    $null = New-Item -Path $jsonDirectory -ItemType Directory
  }
  catch {
    throw "JSONファイルのディレクトリの作成に失敗しました: $(($_.Exception.Message))"
  }
}

Write-Host -NoNewline 'YAMLファイルを探しています...'
$yamlFiles = Get-ChildItem -LiteralPath $yamlDirectory -Filter '*.yaml' -Recurse -File
Write-Host " $($yamlFiles.Count) 件のYAMLファイルが見つかりました"

Write-Host -NoNewline 'YAMLファイルをJSONファイルに変換しています...'
$yamlFiles | ForEach-Object {
  $jsonPath = $_.FullName.Replace($yamlDirectory, $jsonDirectory).Replace('.yaml', '.json')
  if (-not (Test-Path -LiteralPath (Split-Path -Path $jsonPath -Parent) -PathType Container)) {
    $null = New-Item -Path (Split-Path -Path $jsonPath -Parent) -ItemType Directory
  }

  try {
    ((Get-Content -LiteralPath $_.FullName -Raw |
        ConvertFrom-Yaml -Ordered |
        ConvertTo-JSON -Depth 100) + "`n") -replace "`r`n", "`n" |
        Out-File -FilePath $jsonPath -Encoding utf8NoBOM -Force -NoNewline
      }
      catch {
        throw "YAMLファイルの変換に失敗しました: $(($_.Exception.Message))"
      }
    }

    Write-Host ' 完了'
