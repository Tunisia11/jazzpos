Add-Type -AssemblyName System.Drawing

$imgFile = "C:\Users\nourm\Desktop\jazzpos\windows\installer\assets\hero_official_virex_clean.png"
$bmp = [System.Drawing.Bitmap]::FromFile($imgFile)

Write-Host "Width: $($bmp.Width), Height: $($bmp.Height)"

# Inspect button bounds
$btnLeft = 9999; $btnRight = 0; $btnTop = 9999; $btnBottom = 0
for ($y = 1200; $y -lt 1320; $y++) {
    for ($x = 200; $x -lt 600; $x++) {
        $p = $bmp.GetPixel($x, $y)
        # Button background is pure white or very light (>250 in all channels)
        if ($p.R -gt 250 -and $p.G -gt 250 -and $p.B -gt 250) {
            if ($x -lt $btnLeft) { $btnLeft = $x }
            if ($x -gt $btnRight) { $btnRight = $x }
            if ($y -lt $btnTop) { $btnTop = $y }
            if ($y -gt $btnBottom) { $btnBottom = $y }
        }
    }
}

Write-Host "Button bounds: Left=$btnLeft, Right=$btnRight, Top=$btnTop, Bottom=$btnBottom (Width=$($btnRight-$btnLeft), Height=$($btnBottom-$btnTop))"
$bmp.Dispose()
