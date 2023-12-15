local system = require('model.util.system')
local util = require('model.util')
local uv = vim.loop

local function draw()
  local tty = uv.new_tty(2, false)

  if tty == nil then error('oh no') end

  local function write(x)
    tty:write(x)
  end

  local function osc(code_seq)
    return '\x1b]' .. code_seq .. '\07'
  end

  local function csi(code_seq)
    return '\x1b[' .. code_seq
  end

  write(csi('10Afoobar'))
end

draw()

local function pwsh(script, on_finish)
  local output = ''

  return system(
    'pwsh',
    { '-noprofile', '-noninteractive', '-c', script },
    nil,
    function(out)
      if out then
        output = output .. out
      end
    end,
    util.eshow,
    function()
      on_finish(output)
    end
  )
end

-- assuming windows for now, unixs should be easier
return {
  file_b64 = function(filename, resolve)
    pwsh([[
      $bytes = Get-Content -AsByteStream "]] .. filename .. [["
      [System.Convert]::ToBase64String($bytes)]],
      resolve
    )
  end,
  clipboard_b64 = function(resolve)
    pwsh([=[
      Add-Type -AssemblyName System.Drawing
      Add-Type -AssemblyName System.Windows.Forms

      $converter = New-Object System.Drawing.ImageConverter
      $bytes = $converter.ConvertTo(
        [System.Windows.Forms.Clipboard]::GetImage(),
        [System.Byte[]]
      )
      [System.Convert]::ToBase64String($bytes) ]=],
      resolve
    )
  end
}
