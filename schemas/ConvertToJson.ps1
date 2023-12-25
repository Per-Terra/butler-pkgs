### original: https://github.com/microsoft/winget-pkgs/blob/4e76aed0d59412f0be0ecfefabfa14b5df05bec4/Tools/YamlCreate.ps1#L135-L149
# powershell-yaml のインストール
if (-not(Get-Module -ListAvailable -Name 'powershell-yaml')) {
  try {
    Install-Module -Name 'powershell-yaml' -Force -Repository PSGallery -Scope CurrentUser
  }
  catch {
    throw "'powershell-yaml' のインストールに失敗しました"
  }
  finally {
    # Double check that it was installed properly
    if (-not(Get-Module -ListAvailable -Name powershell-yaml)) {
      throw "'powershell-yaml' が見つかりません"
    }
  }
}
###

$yamlDirectory = Join-Path -Path $PSScriptRoot -ChildPath YAML
Write-Host -Object "YAMLファイルのディレクトリ: $yamlDirectory"
$jsonDirectory = Join-Path -Path $PSScriptRoot -ChildPath JSON
Write-Host -Object "JSONファイルのディレクトリ: $jsonDirectory"

if (-not (Test-Path $jsonDirectory)) {
  Write-Host -Object "JSONファイルのディレクトリを作成しています: $jsonDirectory"
  try {
    $null = New-Item -Path $jsonDirectory -ItemType Directory
  }
  catch {
    throw "JSONファイルのディレクトリの作成に失敗しました: $jsonDirectory"
  }
}

Write-Host -Object 'YAMLファイルを探しています...' -NoNewline
$yamlFiles = Get-ChildItem -Path $yamlDirectory -Filter '*.yaml' -Recurse -File
Write-Host -Object " $($yamlFiles.Count) 件のYAMLファイルが見つかりました"

Write-Host -Object 'YAMLファイルをJSONファイルに変換しています...' -NoNewline
$yamlFiles | ForEach-Object {
  $jsonPath = $_.FullName.Replace($yamlDirectory, $jsonDirectory).Replace('.yaml', '.json')
  if (-not (Test-Path (Split-Path -Path $jsonPath -Parent))) {
    $null = New-Item -Path (Split-Path -Path $jsonPath -Parent) -ItemType Directory
  }

  try {
    ((Get-Content -Path $_.FullName -Raw |
      ConvertFrom-Yaml -Ordered |
      ConvertTo-JSON -Depth 100) + "`n") -replace "`r`n", "`n" |
    Out-File -FilePath $jsonPath -Encoding utf8NoBOM -Force -NoNewline
  }
  catch {
    throw "YAMLファイルの変換に失敗しました: $_"
  }
}

Write-Host -Object ' 完了'
