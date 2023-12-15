local tty = vim.loop.new_tty(2, false)

if tty == nil then error('oh no') end

local osc, csi, write do
  write = function(x)
    tty:write(x)
  end

  osc = function(code_seq)
    write('\x1b]' .. code_seq .. '\07')
  end

  csi = function(code_seq)
    write('\x1b[' .. code_seq)
  end
end

local function notify(text)
  osc('9;' .. text)
end

local cursor = {
  move = function(row, col)
    if row == 0 then
      error('row')
    end

    if col == 0 then
      error('col')
    end

    csi(row.. ';' .. col  .. 'H')
  end,
  save = function()
    -- csi('s')
    write('\x1b7')
  end,
  reset = function()
    -- csi('u')
    write('\x1b8')
  end
}

local function iterm_img(row, col, b64)
  if row == 0 or col == 0 then return end

  -- this doesn't work
  -- theory is that neovim uses this save position
  -- calling it here overwrites where it would've been
  -- so i need to get cursor position via query
  -- other option is to force a complete redraw every time
  -- vim.cmd.mode()
  cursor.save()
  -- but it seems to work a lot better if i don't do the move, just the save and reset
  cursor.move(row, col)
  osc('1337;File=;inline=1:' .. b64)
  cursor.reset()
end

local ns = vim.api.nvim_create_namespace('boopity')

local observe do
  ---@type table<number, {start: number, stop: number, cb: (fun():nil), disabled: boolean }[]> bufnr to region
  local regions = {}
  ---@type table<number, {top: number, bot: number}>
  local wins = {}

  local has_dirty = false

  local function mark_region(region)
    has_dirty = true
    region.dirty = true
  end

  vim.api.nvim_set_decoration_provider(
    ns,
    {
      on_win = function(_, winnr, bufnr, top, bot_guess)
        local observed_regions = regions[bufnr]

        if not observed_regions then
          return false
        end

        local win = wins[winnr]
        if win then
          if win.top ~= top then
            -- top moved
            for _,region in ipairs(observed_regions) do
              if region.stop > top and region.start <= bot_guess then
                mark_region(region)
              end
            end

            win.top = top
            win.bot = bot_guess

            return false -- don't care about line changes
          end
        else
          -- first draw
          wins[winnr] = {
            top = top,
            bot = bot_guess
          }
        end

        -- if top moves in one of the regions we care about, need to redraw
      end,
      on_line = function(_, _, bufnr, row)
        local observed_region = regions[bufnr]

        if observed_region then
          for _,region in ipairs(observed_region) do
            if not region.disabled and row >= region.start and row <= region.stop then
              mark_region(region)
            end
          end
        end
      end,
      on_end = function()
        if has_dirty then
          for _,buf_regions in pairs(regions) do
            for _,region in ipairs(buf_regions) do
              if not region.disabled and region.dirty then
                vim.defer_fn(region.cb, 10) -- why does this number matter?
                  -- without a high enough delay, render starts glitching
                  -- i guess that means after on_end other things still happen
                  -- which use cursor position?
                  -- TODO FIXME figure out the right place to put the render callbacks
                region.dirty = false
              end
            end
          end
          -- call cbs
        end
        has_dirty = false
      end
    }
  )

  ---The buffer number and 0-indexed lines (line number column shows 1-index)
  ---@param bufnr number buffer number of interest, 0 for current 
  ---@param start number 0-indexed start
  ---@param stop number 0-indexed stop
  ---@param cb fun():nil
  observe = function(bufnr, start, stop, cb)
    bufnr = (bufnr == 0 and vim.fn.bufnr()) or bufnr

    regions[bufnr] = regions[bufnr] or {}

    local buf_regions = regions[bufnr]
    local region = {
      start = start,
      stop = stop,
      cb = cb,
    }

    buf_regions[#buf_regions+1] = region

    return function()
      region.disabled = true
    end
  end
end

local function draw_img_win_space(row, col, img)
  observe(0, row, row + 1, function()
    local win = vim.fn.getwininfo(vim.fn.win_getid())[1]

    if win == nil then error('no window') end

    local draw_row = row - win.topline - win.winbar + win.winrow
    local draw_col = col + win.wincol

    -- TODO bounds checking
    -- win.height
    -- win.width
    -- print(draw_row .. ':' .. draw_col)

    iterm_img(draw_row, draw_col, img)
  end)
end

-- notify('hi there')
-- csi('10Afoobar'

local test_image = [[iVBORw0KGgoAAAANSUhEUgAAABgAAAAXCAYAAAARIY8tAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAANOSURBVEhL7ZX7T1NnHIf9e2a2f2BmJrNzNzUIm2LtKLcOUZCLKFPZzbmpLEtEWS2yOKci2CIoOuMG1Fpm5SKtUOh6ma1AaRFbirYdFx2Pb00w53i8ZMn2w5Kd5Mk5J+d9P8/7/Z435yzZpK3g3+R/wUtZUqKrQsrW/N2ye13WNjQFn/Ntg5nvjl9Cu/kLcjTlsjFPz5GiEKT4OKuCjI1lZHz6A/u7xnDFoWUkidGfxHkPah1TrKtuJk1bSa4Y96yMRRQCdcnXdIwkOBWEGtcs+r4Q1VY/hZYJNgn2X/VzuCfIAcd9LtyFQSHUbN0ry5CiENS7Z0kd5lsRKq+OU26Lsrs3RllfglJBZU+M4t+iHLLfZWIqTigxT6V1QpYhRSHQnR3GdN3NeDSOd/oBBiEs6kmgsSXZcC3JZzf/pDP8AFs4SZU1QMYZB6t/sssypCgEhcabGLt9WIZHGY9MMzc3z+3EQ1rG5rFM/oUjMkNVd5jlzW5UjYNo21xk1HfJMqQoBNp6C6b+ADb3GL7wFKFYksTM3OO2eWMzvN7i47VGL6pWL2mi2o/a3KzVd8gypCgEqd1xsncUizOAJzTFnekkk/dnWFhYoGYoyiunxcrP3eKtsx7STE6yRQXp+k5ZhhSFYM0OPbXXR7nY52bw9h2CkXuEUwJRwWFXjFeNPlaK1a9uHuYD0wC6C6JFhy7JMqQoBKsK9vCNJUDjFTtmTwh7OM7vkSSz4l1874ywtMnLG+f9vNvqJsvYT/n5AdYdvCjLkKIQrFWXkf9rkNK2AQw9I7QPBbnhCxOdjnPUEWbZcTvvNzlZccbFCtGm3HNO1AazLEOKQpCpLqH4WozCI5fZd6KThs4B0S4/ntFJ6vrGUB3rZf2JXrLqzOQbOkhvn2RlzS+yDCkKQVcgikf0e48jTq7oc3VrP/pWG+03vByx+kiv7UAndprOOMj6RgeqkgNki0U9nbOIQqDO2Ua2oY23cz7hvQ+3oNp7ms0tw/xo/YOG7gDqpiHSTUO8KYI3ZhbJ5j4LhWCRwuwdbN/+FXkV+3hHXcqaKgN5dT+zvOBLNJnFT8alvqR/62talLfz8VmzoYga3xz59ZefPCvO2yW7flHwIs+t4J/iv/7LrOARTfB8KuCRi2sAAAAASUVORK5CYII=]]

draw_img_win_space(20, 20, test_image)

-- iterm_img(10, 20, test_image)
