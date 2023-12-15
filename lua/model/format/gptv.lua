---Resolve path against root_dir if it's not absolute
local function resolve_path(path, root_dir)
  if path:sub(1,1) == '/' or path:sub(2,2) == ':' or path:sub(1,1) == '~' then
    return vim.fs.normalize(path)
  end

  return vim.fs.joinpath(root_dir, path)
end

---Base64 encodes a file using python base64
local function py_base64_encode(file_path)
  assert(
    vim.fn.filereadable(file_path),
    'Base64 encode source file not readable: ' .. file_path
  )

  local extension = vim.fn.fnamemodify(file_path, ':e')

  vim.cmd.py([[import base64]])

  local b64 = vim.fn.pyeval(
    [[base64.b64encode(open(r']] .. file_path .. [[', 'rb').read()).decode()]]
  )

  return {
    ext = extension,
    data = b64
  }
end

return {
  ---This parses out ![]() as image content. It always uses default detail level.
  ---@param messages ChatMessage[]
  ---@param config ChatConfig
  chat = function(messages, config)
    -- for each message, parse out if it contains a ![]()
    for _,message in ipairs(messages) do
      if message.role == 'user' then
        local images = {}

        for _, path in message.content:gmatch("!%[(.-)%]%((.-)%)") do
          -- ignoring name for now

          if path:match('^http') or path:match('^data:') then
            images[#images + 1] = {
              type = 'image_url',
              image_url = path
            }
          else
            local file_path = resolve_path(path, vim.fn.expand('%:p:h'))
            local encoded = py_base64_encode(file_path)

            images[#images + 1] = {
              type = 'image_url',
              image_url = 'data:image/'.. encoded.ext .. ';base64,' .. encoded.data
            }
          end
        end
      end
    end

    return {
      messages = {
      }
    }
  end
}
