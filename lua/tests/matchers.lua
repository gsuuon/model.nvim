local table_types = function(_, arguments)

  local function matches_type(value, types)
    if type(value) ~= 'table' then
      return false
    end

    for k,_ in pairs(types) do
      if type(types[k]) == 'table' then
        return matches_type(value[k], types[k])
      end

      if type(value[k]) ~= types[k] then
        return false
      end
    end

    return true
  end

  return function(value)
    return matches_type(value, arguments[1])
  end
end

assert:register('matcher', 'table_types', table_types)
