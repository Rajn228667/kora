# Renders the KORA "K" mark: three rounded capsules with a diagonal
# lavender→violet linear gradient.
param([string]$OutDir = 'C:\Users\User\kora\app\assets\brand')

Add-Type -AssemblyName System.Drawing

function New-KoraK([int]$size, [bool]$transparent, [double]$padFrac) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    if ($transparent) {
        $g.Clear([System.Drawing.Color]::Transparent)
    } else {
        $g.Clear([System.Drawing.Color]::White)
    }

    $rect = New-Object System.Drawing.RectangleF(0, 0, $size, $size)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::FromArgb(0xC4, 0xB5, 0xFD),
        [System.Drawing.Color]::FromArgb(0x5B, 0x21, 0xB6),
        [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal
    )

    $pad = [double]$size * $padFrac
    $u = ([double]$size - 2 * $pad) / 1024.0
    $penWidth = [float](268.0 * $u)
    $pen = New-Object System.Drawing.Pen($brush, $penWidth)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

    # Points in a 1024-unit box.
    $lines = @(
        @(270, 240, 270, 784),   # stem
        @(392, 500, 740, 152),   # upper arm
        @(392, 524, 740, 872)    # lower leg
    )
    foreach ($l in $lines) {
        $g.DrawLine(
            $pen,
            [float]($pad + $l[0] * $u),
            [float]($pad + $l[1] * $u),
            [float]($pad + $l[2] * $u),
            [float]($pad + $l[3] * $u)
        )
    }

    $pen.Dispose(); $brush.Dispose(); $g.Dispose()
    return $bmp
}

$icon = New-KoraK -size 1024 -transparent $false -padFrac 0.0
$icon.Save("$OutDir\kora_logo.png", [System.Drawing.Imaging.ImageFormat]::Png)
$icon.Dispose()

$fg = New-KoraK -size 1024 -transparent $true -padFrac 0.17
$fg.Save("$OutDir\kora_logo_fg.png", [System.Drawing.Imaging.ImageFormat]::Png)
$fg.Dispose()

$mark = New-KoraK -size 512 -transparent $true -padFrac 0.02
$mark.Save("$OutDir\kora_logo_k.png", [System.Drawing.Imaging.ImageFormat]::Png)
$mark.Dispose()

'done'
