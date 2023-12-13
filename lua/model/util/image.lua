local system = require('model.util.system')

return {
  clipboard_b64 = function(resolve)
    local image_b64 = ''

    -- assuming windows for now
    system(
      'pwsh',
      { '-noprofile', '-noninteractive', '-c', [=[
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$converter = New-Object System.Drawing.ImageConverter
$image = [System.Windows.Forms.Clipboard]::GetImage()
$bytes = $converter.ConvertTo($image, [System.Byte[]])
[System.Convert]::ToBase64String($bytes)
]=] },
      nil,
      function(out)
        if out then
          image_b64 = image_b64 .. out
        end
      end,
      error,
      function()
        resolve(image_b64)
      end
    )
  end
}
