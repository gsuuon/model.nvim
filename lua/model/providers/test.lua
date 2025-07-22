local juice = require('model.util.juice')
local util = require('model.util')

---@type Provider
local foo_bar_provider = {
  request_completion = function(handlers, params, options)
    vim.defer_fn(function()
      handlers.on_partial('foo')

      vim.defer_fn(function()
        handlers.on_partial('bar')

        vim.defer_fn(function()
          handlers.on_finish()
        end, 100)
      end, 100)
    end, 100)
  end,
}

---@type Provider
local spinner_provider = {
  request_completion = function(handlers)
    local stop, update, seg = juice.spinner({
      label = 'spinning',
      position = util.position.row_below(handlers.segment.get_span().stop),
    })

    seg.data.info = ''

    local run = true

    local count = 0
    local function add()
      vim.defer_fn(function()
        count = count + 1
        seg.data.info = seg.data.info .. count
        update('spinning ' .. count)

        if run then
          add()
        end
      end, 500)
    end

    add()
    handlers.on_partial('')

    return function()
      run = false
      stop()
    end

    -- vim.defer_fn(function()
    --   seg.data.info = seg.data.info .. 'foo'

    --   vim.defer_fn(function()
    --     seg.data.info = seg.data.info .. 'bar'

    --     vim.defer_fn(function()
    --       handlers.on_finish()
    --     end, 100)
    --   end, 100)
    -- end, 100)
  end,
}

return {
  foo_bar_provider = foo_bar_provider,
  spinner_provider = spinner_provider,
}
