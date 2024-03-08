local util = require('model.util')
local curl = require('model.util.curl')
local juice = require('model.util.juice')

---@type Provider
return {
  request_completion = function(handlers, params, options)
    local opts = vim.tbl_extend('force', {
      url = 'http://localhost:11434',
    }, options or {})
    local stop_marquee = juice.handler_marquee_or_notify(
      'ollama: ' .. params.model,
      handlers.segment,
      nil,
      20
    )

    return curl.stream({
      url = opts.url .. '/api/generate',
      headers = {
        ['Content-Type'] = 'application/json',
      },
      body = vim.tbl_extend(
        'force',
        { raw = true }, -- can override raw
        params,
        { stream = true } -- can't override stream
      ),
    }, function(data)
      stop_marquee()

      local item, error = util.json.decode(data)
      if item == nil then
        util.eshow(error)
        return
      end

      if item.response then
        handlers.on_partial(item.response)
      end

      if item.done then
        handlers.on_finish()
      end

      if item.error then
        handlers.on_error(item.error, 'ollama error')
      end
    end, function(err)
      stop_marquee()

      handlers.on_error(vim.inspect(err), 'Ollama provider error')
    end)
  end,
}
