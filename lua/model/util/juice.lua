local segment = require('model.util.segment')
local system = require('model.util.system')

local M = {}

M.can_say = false

function M.scroll(text, rate, set, size)
  local run = true

  local function scroll_(t)
    vim.defer_fn(function ()
      if run then
        local head = t:sub(1, 1)
        local tail = t:sub(2, #t)
        local text_ = tail .. head

        if size then
          set('<' .. text_:sub(1, size) .. '>')
        else
          set('<' .. text_ .. '>')
        end

        return scroll_(text_)
      end
    end, rate)
  end

  scroll_(text)

  local did_stop = false

  return function()
    if not did_stop then
      set('')
      run = false
      did_stop = true
    end
  end
end

--- @param text string The text to display either as a marquee or notification.
--- @param seg? Segment segment to place the marquee after
--- @param hl? string Optional highlight group for the marquee segment. Defaults to 'Comment'.
--- @param size? number Limit marquee size
--- @return function stop stop and clear the marquee
function M.handler_marquee_or_notify(text, seg, hl, size)
  if seg then
    local handler_seg = seg.details()
    local pending = segment.create_segment_at(
      handler_seg.details.end_row,
      handler_seg.details.end_col,
      hl or 'Comment'
    )
    return M.scroll(text .. '   ', 160, pending.set_virt, size)
  else
    vim.notify(text)
  end

  return function() end
end

local queue_say, stop_say do
  local say do
    local cmd = 'say'
    local err = 'Failed to spawn "say"'

    if vim.loop.os_uname().sysname == 'Linux' then
      cmd = 'spd-say'
      err = 'Failed to spawn spd-say, install with: sudo apt install speech-dispatcher'
    elseif 'Windows_NT' then
      cmd =  'say.cmd'
      err = 'Failed to spawn say.cmd, install with: scoop install say'
    end

    say = function(x, on_finish)
      assert(
        pcall(
          system,
          cmd,
          {vim.fn.trim(x)},
          nil,
          nil,
          nil,
          vim.schedule_wrap(on_finish)
        ),
        err
      )
    end
  end

  -- If we call 'say' rapidly they can execute out of order.
  local say_queue = {}
  local saying = false

  local function say_next()
    local next = table.remove(say_queue, 1)
    if next and #next > 0 then
      saying = true

      say(next, function()
        saying = false
        say_next()
      end)
    end
  end

  queue_say = function(x)
    say_queue[#say_queue+1] = x

    if not saying then
      say_next()
    end
  end

  stop_say = function()
    say_queue = {}
  end
end

---Use 'say' (mac, windows via scoop) or 'spd-say' to say text
---@type fun(text: string)
function M.say(x)
  if not M.can_say or not x or #x == 0 then return end

  queue_say(x)
end

---@return { say: fun(text: string), finish: fun() } sayer say accepts partial text and will attempt to split it and say the parts. finish needs to be called to say the final unsaid chunk.
function M.sayer()
  local completion = ''
  local said_len = 0
  local did_intro_words = false

  return {
    say = function(text)
      completion = completion .. text

      if not did_intro_words and said_len == 0 then -- start saying the first 3 words ASAP
        local words = vim.fn.split(completion, ' ', true)
        ---@cast words string[]

        if #words > 1 then
          table.remove(words, #words) -- remove the last word because it might be partial or empty

          local intro_words = table.concat(words, ' ')
          M.say(intro_words)

          did_intro_words = true
          said_len = #intro_words + 1
        end
      end

      if text:find('%.') then
        M.say(completion:sub(said_len))
        said_len = #completion + 1
      end
    end,
    finish = function()
      M.say(completion:sub(said_len))
    end
  }
end

M.stop_say = stop_say

return M
