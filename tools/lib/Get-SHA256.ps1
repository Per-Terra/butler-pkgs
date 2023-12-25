filter Get-SHA256 {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true,
      ValueFromPipeline = $true)]
    [string[]]$Path
  )

  $Path | ForEach-Object {
    Write-Verbose -Message "ファイルのSHA256ハッシュ値を計算しています: $_"
    if (Test-Path -Path $_) {
      try {
        $hash = (Get-FileHash -Path $_ -Algorithm SHA256).Hash.ToLower()
        Write-Verbose -Message "ファイルのSHA256ハッシュ値を計算しました: $hash"
        return $hash
      }
      catch {
        throw "ファイルのSHA256ハッシュ値の計算に失敗しました: $_"
      }
    }
    else {
      throw [System.IO.FileNotFoundException]::new("指定されたファイルが見つかりません: $_")
    }
  }
}
