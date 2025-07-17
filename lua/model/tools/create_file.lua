local util = require('model.util')
local files = require('model.util.files')
local rpc = require('model.util.rpc')
local parse = require('model.util.json_stream_parse')

local function path_is_absolute(path)
  -- cross-platform (windows, unix) check that path is relative
  return path:match('^/') or path:match('^%a:[/\\]')
end

local function path_is_above_cwd(path)
  -- normalize path and check if it contains parent directory references
  local normalized = vim.fs.normalize(path)
  return normalized:match('%.%./')
    or normalized:match('^%.%./')
    or normalized:match('/%.%./')
end

---@type Tool
return {
  description = 'Create a new file with given content',
  parameters = {
    type = 'object',
    properties = {
      path = {
        type = 'string',
        description = 'Relative path to the file',
      },
      content = {
        type = 'string',
        description = 'Content to write to the file',
      },
    },
    required = { 'path', 'content' },
  },
  invoke = function(args, callback)
    if type(args.path) ~= 'string' then
      error('Invalid path: must be a string')
    end

    if path_is_absolute(args.path) then
      error('Path must be relative')
    end

    if path_is_above_cwd(args.path) then
      error('Path must resolve to within cwd')
    end

    files.get_file_and_diagnostics(args.path, 'Created file', callback)

    return function()
      -- no cancel
    end,
      'Getting written file with diagnostics..'
  end,
  presentation = function()
    local content = ''
    local path = ''
    local bufnr = nil

    return parse.object({
      path = parse.string(function(_, complete)
        if complete then
          path = complete

          local dir = vim.fs.dirname(path)
          if dir and dir ~= '' then
            local success = vim.fn.mkdir(dir, 'p')
            if success == 0 then
              error('Failed to create directory: ' .. dir)
            end
          end

          local already_existed = vim.fn.filereadable(path) == 1

          -- Create a new buffer and set its content
          bufnr = vim.api.nvim_create_buf(true, false)
          vim.api.nvim_buf_set_lines(
            bufnr,
            0,
            -1,
            false,
            vim.split(content, '\n')
          )
          vim.api.nvim_buf_set_name(bufnr, path)
          vim.api.nvim_buf_set_option(
            bufnr,
            'filetype',
            vim.filetype.match({ filename = path }) or ''
          )

          -- Set a buffer variable to identify this buffer later
          vim.api.nvim_buf_set_var(bufnr, 'model_nvim_created_file', true)

          -- Display a message
          if already_existed then
            util.show('Creating file that already exists: ' .. path)
          else
            util.show('Opened buffer for new file: ' .. path)
          end

          -- Schedule opening the buffer in a new tab
          vim.schedule(function()
            vim.cmd('tabnew')
            vim.api.nvim_set_current_buf(bufnr)
            local winnr = vim.api.nvim_get_current_win()

            rpc.notify('create_file', {
              action = 'open',
              path = path,
              bufnr = bufnr,
              winnr = winnr,
            })
          end)
        end
      end),
      content = parse.string(function(part, complete)
        if complete then
          content = complete

          if bufnr then
            vim.api.nvim_buf_set_lines(
              bufnr,
              0,
              -1,
              false,
              vim.split(content, '\n')
            )
          end
          util.show('Received all content for ' .. path)
        else
          content = content .. part

          if bufnr then
            vim.api.nvim_buf_set_lines(
              bufnr,
              0,
              -1,
              false,
              vim.split(content, '\n')
            )
          end
        end
      end),
    })
  end,
  presentation_autoaccept = function(args, done)
    local arguments, err = util.json.decode(args)
    if arguments then
      local bufnr = vim.fn.bufnr(arguments.path)
      if bufnr ~= -1 then
        local ok, is_created =
          pcall(vim.api.nvim_buf_get_var, bufnr, 'model_nvim_created_file')
        if ok and is_created then
          vim.schedule(function()
            vim.api.nvim_buf_call(bufnr, function()
              vim.cmd('write')
              vim.cmd('q')
              util.show('Autoaccept saved: ' .. arguments.path)
            end)
          end)
        else
          util.eshow('Failed to find created file buffer')
        end
      else
        util.eshow('Failed to find buffer for path: ' .. arguments.path)
      end
      done()
    else
      util.eshow('Failed to parse arguments: ' .. err)
    end
  end,
}
