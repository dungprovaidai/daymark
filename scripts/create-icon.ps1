# Development-only asset generator. The generated PNG is included in the project.
Add-Type -AssemblyName System.Drawing
$destination = Join-Path $PSScriptRoot '..\Daymark\Assets.xcassets\AppIcon.appiconset\AppIcon.png'
$bitmap = New-Object System.Drawing.Bitmap(1024, 1024, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb))
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#F3EFFB'))
$sunBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#F4BA72'))
$graphics.FillEllipse($sunBrush, 326, 237, 372, 372)
$rayPen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#F4BA72'), 20)
$rayPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$rayPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$graphics.DrawLine($rayPen, 512, 156, 512, 188)
$graphics.DrawLine($rayPen, 276, 234, 299, 257)
$graphics.DrawLine($rayPen, 748, 234, 725, 257)
$graphics.DrawLine($rayPen, 210, 420, 242, 420)
$graphics.DrawLine($rayPen, 814, 420, 782, 420)
function Fill-Hill([string]$hex, [single]$startY, [single]$control1Y, [single]$control2Y, [single]$endY) {
    $shape = New-Object System.Drawing.Drawing2D.GraphicsPath
    $shape.AddBezier([single]0, $startY, [single]320, $control1Y, [single]650, $control2Y, [single]1024, $endY)
    $shape.AddLine([single]1024, $endY, [single]1024, [single]1024)
    $shape.AddLine([single]1024, [single]1024, [single]0, [single]1024)
    $shape.CloseFigure()
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($hex))
    $graphics.FillPath($brush, $shape)
    $brush.Dispose()
    $shape.Dispose()
}
Fill-Hill '#C4B6E5' 592 392 710 520
Fill-Hill '#9680C7' 690 780 415 690
Fill-Hill '#65509F' 764 580 870 718
$bitmap.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
$sunBrush.Dispose()
$rayPen.Dispose()
Write-Output 'Created 1024x1024 opaque Daymark app icon.'
