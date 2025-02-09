function Get-FileSHA256Hash {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias("FullName")] # Get-ChildItem などからのパイプライン入力に対応
    [string[]]$Path
  )

  begin {
    $hasher = [System.Security.Cryptography.SHA256]::Create()
  }

  process {
    foreach ($filePath in $Path) {
      if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        Write-Error "ファイルが見つかりません: $filePath"
        continue
      }

      Write-Verbose "ハッシュ値を計算しています: $filePath"
      try {
        $stream = [System.IO.File]::OpenRead($filePath)
        try {
          $hashBytes = $hasher.ComputeHash($stream)
          [BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
        }
        finally {
          $stream.Dispose()
        }
      }
      catch {
        Write-Error "ハッシュ値の計算に失敗しました: $($_.Exception.Message)"
        continue
      }
    }
  }

  end {
    $hasher.Dispose()
  }
}
