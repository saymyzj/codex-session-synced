$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot '..\..\Resources\AppIconSource.png'
$destination = Join-Path $PSScriptRoot '..\CodexSynced.Windows\Resources\AppIcon.ico'
$destinationDirectory = Split-Path -Parent $destination

New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
Add-Type -AssemblyName System.Drawing

$image = [System.Drawing.Image]::FromFile($source)
$bitmap = New-Object System.Drawing.Bitmap 256, 256
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$stream = New-Object System.IO.MemoryStream

try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.DrawImage($image, 0, 0, 256, 256)
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $png = $stream.ToArray()

    $bytes = New-Object System.Collections.Generic.List[byte]
    $bytes.AddRange([byte[]](0, 0, 1, 0, 1, 0))
    $bytes.AddRange([byte[]](0, 0, 0, 0))
    $bytes.AddRange([BitConverter]::GetBytes([uint16]1))
    $bytes.AddRange([BitConverter]::GetBytes([uint16]32))
    $bytes.AddRange([BitConverter]::GetBytes([uint32]$png.Length))
    $bytes.AddRange([BitConverter]::GetBytes([uint32]22))
    $bytes.AddRange($png)
    [System.IO.File]::WriteAllBytes($destination, $bytes.ToArray())
}
finally {
    $stream.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
    $image.Dispose()
}
