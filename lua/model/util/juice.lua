local segment = require('model.util.segment')
local system = require('model.util.system')
local util = require('model.util')

local y = 0

local M = {}

M.can_say = false
M.custom_say = nil -- fun(text: string, on_finish: fun()) override this to use custom say function

function M.animate(render, interval)
  local stop = false

  local function run()
    vim.defer_fn(function()
      if not stop then
        if pcall(render) then
          run()
        else
          stop = true
        end
      end
    end, interval)
  end

  run()

  return function()
    stop = true
  end
end

function M.scroll(text, rate, set, size)
  return M.animate(function()
    local head = text:sub(1, 1)
    local tail = text:sub(2, #text)
    text = tail .. head

    if size then
      set('<' .. text:sub(1, size) .. '>')
    else
      set('<' .. text .. '>')
    end
  end, rate)
end

--- @param seg? Segment Optional segment to place the marquee after
--- @param label? string Optional string to place after the spinner
--- @param hl? string Optional highlight group for the marquee segment. Defaults to 'Comment'.
function M.spinner(seg, label, hl)
  local spinner_frames = {
    '⠈⠉',
    ' ⠙',
    ' ⠸',
    ' ⢰',
    ' ⣠',
    '⢀⣀',
    '⣀⡀',
    '⣄ ',
    '⡆ ',
    '⠇ ',
    '⠋ ',
    '⠉⠁',
  }
  local frame_index = 1
  local start_time = vim.loop.now()

  ---@type Segment
  local spinner_seg
  if seg then
    local handler_seg = seg.details()
    spinner_seg = segment.create_segment_at(
      handler_seg.details.end_row,
      handler_seg.details.end_col,
      hl or 'Comment'
    )
  else
    local pos = util.cursor.position()

    spinner_seg = segment.create_segment_at(pos.row, pos.col, hl or 'Comment')
  end

  local function render()
    local elapsed = math.floor((vim.loop.now() - start_time) / 1000)
    local spinner_text = spinner_frames[frame_index]
    if label then
      spinner_text = spinner_text .. ' ' .. label .. ' (' .. elapsed .. 's)'
    end

    spinner_seg.set_virt(spinner_text)

    frame_index = frame_index + 1
    if frame_index > #spinner_frames then
      frame_index = 1
    end
  end

  local stop = M.animate(render, 125)
  local stopped = false

  local function cancel()
    if not stopped then
      spinner_seg.delete()
      stop()
      stopped = true
    end
  end

  local function update(new_label)
    label = new_label
  end

  return cancel, update, spinner_seg
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

local queue_say, stop_say
do
  local say
  do
    local cmd = 'say'
    local err = 'Failed to spawn "say"'

    if vim.loop.os_uname().sysname == 'Linux' then
      cmd = 'spd-say'
      err =
        'Failed to spawn spd-say, install with: sudo apt install speech-dispatcher'
    elseif 'Windows_NT' then
      cmd = 'say.cmd'
      err = 'Failed to spawn say.cmd, install with: scoop install say'
    end

    say = function(x, on_finish)
      if M.custom_say then
        M.custom_say(x, vim.schedule_wrap(on_finish))
      else
        assert(
          pcall(
            system,
            cmd,
            { vim.fn.trim(x) },
            nil,
            nil,
            nil,
            vim.schedule_wrap(on_finish)
          ),
          err
        )
      end
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
    say_queue[#say_queue + 1] = x

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
  if not M.can_say or not x or #x == 0 then
    return
  end

  queue_say(x)
end

---@return { say: fun(text: string), finish: fun() } sayer say accepts partial text and will attempt to split it and say the parts. finish needs to be called to say the final unsaid chunk.
function M.sayer()
  local completion = ''
  local said_len = 0
  -- TODO say first words if after 100ms we dont have a full sentence yet

  return {
    say = function(text)
      completion = completion .. text

      if text:find('%.') then
        M.say(completion:sub(said_len))
        said_len = #completion + 1
      end
    end,
    finish = function()
      M.say(completion:sub(said_len))
    end,
  }
end

M.stop_say = stop_say

return M
