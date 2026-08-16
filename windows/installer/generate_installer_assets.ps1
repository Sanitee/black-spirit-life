[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$OutputRoot = Join-Path $PSScriptRoot 'assets'
if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputRoot | Out-Null
}

function Write-InstallerTexture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    $sourceImage = [System.Drawing.Image]::FromFile($Source)
    $bitmap = New-Object System.Drawing.Bitmap(
        920,
        920,
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    )
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CompositingMode =
            [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality =
            [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode =
            [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode =
            [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode =
            [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.DrawImage(
            $sourceImage,
            [System.Drawing.Rectangle]::new(0, 0, 920, 920)
        )
        $jpegEncoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
            Where-Object { $_.MimeType -eq 'image/jpeg' } |
            Select-Object -First 1
        if ($null -eq $jpegEncoder) {
            throw 'The Windows JPEG encoder is unavailable.'
        }
        $encoderParameters = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $encoderParameters.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
            [System.Drawing.Imaging.Encoder]::Quality,
            [long]88
        )
        try {
            $bitmap.Save($Destination, $jpegEncoder, $encoderParameters)
        }
        finally {
            $encoderParameters.Dispose()
        }
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
        $sourceImage.Dispose()
    }
}

Write-InstallerTexture `
    -Source (Join-Path $ProjectRoot 'assets\sakura\materials\blackened-cedar.png') `
    -Destination (Join-Path $OutputRoot 'blackened-cedar-installer.jpg')
Write-InstallerTexture `
    -Source (Join-Path $ProjectRoot 'assets\sakura\materials\charcoal-plum-lacquer.png') `
    -Destination (Join-Path $OutputRoot 'charcoal-plum-lacquer-installer.jpg')

Get-ChildItem -LiteralPath $OutputRoot -Filter '*-installer.jpg' -File |
    Sort-Object Name |
    ForEach-Object {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
        Write-Host "$($_.Name): $($_.Length) bytes, SHA-256 $hash"
    }
