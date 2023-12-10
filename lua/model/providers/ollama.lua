local util = require('model.util')
local curl = require('model.util.curl')

---@type Provider
return {
  request_completion = function (handler, params)
    return curl.stream(
      {
        url = 'http://localhost:11434/api/generate',
        headers = {
          ['Content-Type'] = 'application/json'
        },
        body = vim.tbl_extend(
          'force',
          { raw = true }, -- can override raw
          params,
          { stream = true } -- can't override stream
        )
      },
      function(data)
        local item, error = util.json.decode(data)
        if item == nil then
          util.eshow(error)
          return
        end

        if item.response then
          handler.on_partial(item.response)
        end

        if item.done then
          handler.on_finish()
        end

      end,
      function(err)
        handler.on_error(vim.inspect(err), 'Ollama provider error')
      end
    )
  end
}
