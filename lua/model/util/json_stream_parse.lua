--[[
JSON Streaming Parser Handlers

The parser provides several handler functions that process JSON data incrementally.
Each handler follows these conventions:

1. Returns nil if it needs more input to complete processing
2. Returns a number (character offset) if it finished processing at that position
3. Throws errors for invalid input

Handlers are designed to process partial JSON strings and maintain state between calls.

Available handlers:

1. _object(field_handlers) - Processes JSON objects
   - field_handlers: table mapping field names to their value handlers
   - Returns a function that processes object chunks
   - Maintains state about current field being processed
   - Delegates value processing to field-specific handlers

2. _string(handler) - Processes JSON string values
   - handler: function that receives string parts and completion status
     - Called with (partial_string, complete_string)
     - complete_string is nil for partial content
   - Handles string escaping
   - Buffers content until closing quote

3. _list(create_handler) - Processes JSON arrays
   - create_handler: function that creates a handler for each list item
     - Receives item index (1-based)
     - Returns a handler for that item's value
   - Tracks current item being processed
   - Creates new handlers for each array element

4. _number(handler) - Processes JSON numbers
   - handler: function that receives the parsed number
   - Validates number format
   - Buffers digits until non-number character
   - Converts to Lua number when complete

5. _boolean(handler) - Processes JSON booleans
   - handler: function that receives the boolean value
   - Validates only 'true' or 'false' values
   - Buffers characters until complete
   - Throws on invalid boolean content

Example Usage:
  local parse = require('json_stream_handlers')
  local my_data = {}
  
  local obj_parser = parse.object({
    name = parse.string(function(part, complete)
      if complete then my_data.name = complete end
    end),
    age = parse.number(function(num)
      my_data.age = num
    end)
  })
  
  obj_parser('{"name": "Jo') -- Processes partial input
  obj_parser('hn", "age": 30}') -- Completes processing
]]

local function _object(field_handlers, required_fields)
  -- State tracking for object parsing
  local in_object = false -- Whether we're inside the outer JSON object
  local current_handler = nil -- Handler for current field value
  local current_key = nil -- Current field name being processed
  local in_key = false -- Whether we're currently parsing a key
  local in_value = false -- Whether we're currently parsing a value
  local key_buffer = '' -- Buffer for building up key across partials
  local parsed_fields = {} -- Track which fields we've parsed
  local is_complete = false -- Whether we've seen the closing brace

  -- Default required_fields to empty table if not provided
  required_fields = required_fields or {}

  local function check_required_fields()
    if is_complete then
      for _, field in ipairs(required_fields) do
        if not parsed_fields[field] then
          error(string.format("Missing required field: '%s'", field))
        end
      end
    end
  end

  return function(partial)
    local i = 1
    while i <= #partial do
      local char = partial:sub(i, i)

      -- First let the current handler (if any) process the remaining input
      if current_handler then
        local consumed = current_handler(partial:sub(i))
        if not consumed then
          -- Handler needs more input, we're done for this partial
          return
        end

        -- Handler finished processing this value
        if current_key then
          parsed_fields[current_key] = true
        end
        current_key = nil
        current_handler = nil
        in_value = false

        -- Advance past what the handler consumed
        i = i + consumed

        -- Get next character after handler's consumption
        char = partial:sub(i, i)
      end

      -- Only process if not whitespace (unless in key/value)
      if in_key or in_value or not char:match('%s') then
        -- If not yet in an object, look for opening brace
        if not in_object then
          if char == '{' then
            in_object = true
          end
        else
          -- If we see closing brace for outer object
          if char == '}' then
            in_object = false
            is_complete = true
            check_required_fields()
            -- dshow({
            --   note = 'saw end',
            --   part = partial:sub(1, i),
            -- })
            return i -- Return position where object ended
          end

          -- If we don't have a current key, look for one
          if not current_key then
            if in_key then
              if char == '"' then
                -- Found end of key string
                current_key = key_buffer
                key_buffer = ''
                in_key = false
              else
                -- Accumulate key characters
                key_buffer = key_buffer .. char
              end
            else
              if char == '"' then
                -- Found start of key string
                in_key = true
              elseif char == ':' then
                error("Unexpected ':' without key")
              end
            end
          else
            -- We have a key, now process its value
            if not in_value then
              -- Look for the value separator
              if char == ':' then
                -- Look up handler for this field
                if field_handlers[current_key] then
                  current_handler = field_handlers[current_key]
                  in_value = true
                end
              end
            end
          end
        end
      end

      i = i + 1
    end

    -- If we processed the entire partial without completing, check if we're done
    if not in_object and is_complete then
      check_required_fields()
    end
  end
end

local function _string(handler)
  local in_string = false
  local buffer = ''
  local escape_next = false

  return function(partial)
    local partial_buffer = ''

    for i = 1, #partial do
      local char = partial:sub(i, i)

      if in_string then
        if escape_next then
          -- Handle escaped characters
          if char == 'n' then
            buffer = buffer .. '\n'
            partial_buffer = partial_buffer .. '\n'
          elseif char == 't' then
            buffer = buffer .. '\t'
            partial_buffer = partial_buffer .. '\t'
          elseif char == 'r' then
            buffer = buffer .. '\r'
            partial_buffer = partial_buffer .. '\r'
          elseif char == '\\' then
            buffer = buffer .. '\\'
            partial_buffer = partial_buffer .. '\\'
          elseif char == '"' then
            buffer = buffer .. '"'
            partial_buffer = partial_buffer .. '"'
          else
            -- Keep other escaped characters as-is
            buffer = buffer .. char
            partial_buffer = partial_buffer .. char
          end
          escape_next = false
        elseif char == '\\' then
          escape_next = true
        elseif char == '"' then
          -- Found closing quote - send any remaining partial before the complete string
          handler(partial_buffer, buffer) -- send complete string
          in_string = false
          buffer = ''
          return i -- return position where string ended
        else
          buffer = buffer .. char
          partial_buffer = partial_buffer .. char
        end
      else
        if char == '"' then
          in_string = true
          partial_buffer = ''
          buffer = ''
        end
      end
    end

    -- After processing all characters, send any accumulated partial
    if in_string and #partial_buffer > 0 then
      handler(partial_buffer, nil)
    end
  end
end

local function _list(create_handler)
  local index = 0
  local in_list = false
  local current_handler = nil

  return function(partial)
    local i = 1
    while i <= #partial do
      local char = partial:sub(i, i)

      -- First let the current handler (if any) process the remaining input
      if current_handler then
        local consumed = current_handler(partial:sub(i))
        if not consumed then
          -- Handler needs more input, we're done for this partial
          return nil
        end

        -- Handler finished processing this item
        current_handler = nil
        i = i + consumed

        -- If we consumed the entire partial, we're done
        if i > #partial then
          return i - 1
        end

        -- Get next character after handler's consumption
        char = partial:sub(i, i)
      end

      if in_list then
        if char == ']' then
          in_list = false
          return i -- return position where list ended
        end

        -- Start a new item when we see any non-whitespace character
        -- that isn't a comma
        if not char:match('%s') and char ~= ',' then
          index = index + 1
          current_handler = create_handler(index)

          local consumed = current_handler(partial:sub(i))

          if consumed then
            i = i + consumed - 1 -- -1 because we'll increment i in the outer loop
            current_handler = nil
          else
            return
          end
        end
      else
        if char == '[' then
          in_list = true
          index = 0
        end
      end

      i = i + 1
    end
  end
end

local function _number(handler)
  local num_str = ''
  local has_decimal = false
  local has_exponent = false
  local in_number = false

  return function(partial)
    local i = 1
    while i <= #partial do
      local char = partial:sub(i, i)

      -- Skip whitespace before number starts
      if not in_number and char:match('%s') then
        i = i + 1
      else
        in_number = true
        if char:match('[0-9]') then
          num_str = num_str .. char
          i = i + 1
        elseif char == '.' and not has_decimal then
          num_str = num_str .. char
          has_decimal = true
          i = i + 1
        elseif (char == 'e' or char == 'E') and not has_exponent then
          num_str = num_str .. char
          has_exponent = true
          i = i + 1
        elseif
          (char == '+' or char == '-')
          and (i == 1 or num_str:sub(-1) == 'e' or num_str:sub(-1) == 'E')
        then
          num_str = num_str .. char
          i = i + 1
        else
          -- Found non-number character - try to parse what we have
          if #num_str > 0 then
            local num = tonumber(num_str)
            if num then
              handler(num)
              num_str = ''
              has_decimal = false
              has_exponent = false
              in_number = false
              return i - 1 -- Only return offset when we've fully processed the number
            end
          end
          break
        end
      end
    end
  end
end

local function _boolean(handler)
  local buffer = ''
  local in_boolean = false

  return function(partial)
    local i = 1
    while i <= #partial do
      local char = partial:sub(i, i)

      -- Skip whitespace before boolean starts
      if not in_boolean and char:match('%s') then
        i = i + 1
      else
        in_boolean = true
        -- Only allow valid boolean characters
        if not char:match('[a-z]') then
          error('Invalid boolean character: ' .. char)
        end

        buffer = buffer .. char

        if buffer == 'true' then
          handler(true)
          return i
        elseif buffer == 'false' then
          handler(false)
          return i
        end

        -- Check for invalid prefixes
        if not (buffer:match('^t') or buffer:match('^f')) then
          error('Invalid boolean prefix: ' .. buffer)
        end

        i = i + 1
      end
    end
  end
end

local parse = {
  object = _object,
  string = _string,
  list = _list,
  number = _number,
  boolean = _boolean,
}

return parse
