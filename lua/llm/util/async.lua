--- Coroutine wrapper that lets you use callback-based functions like async await.
--- Provide `resolve` as the callback fn, and use `wait` to wait for the callback.
--- Optionally provide a callback for the return value of the coroutine. Immediately
--- starts the async function.
---
--- Usage example:
---   async(function(wait, resolve)
---    local a = wait(callback_a(arg_a, resolve))
---    local b = wait(callback_b(a, resolve))
---    return b
---   end, outer_callback)
--- @param fn fun(wait: (fun(any): any), resolve: (fun(any): any)): any))
--- @param callback? fun(result: any)
local function async(fn, callback)
  local co = coroutine.create(fn)

  local function wait(cb_fn)
    return coroutine.yield(cb_fn)
  end

  local function resolve(result)
    if coroutine.status(co) == 'dead' then
      error('resolve in dead coroutine')
    end

    local success, yield_result = coroutine.resume(co, result)

    if not success then
      error(debug.traceback(co, yield_result), 0)
    end

    -- The last resume finished the coroutine
    if coroutine.status(co) == 'dead' and callback ~= nil then
      callback(yield_result)
    end
  end

  local success, initial_yield = coroutine.resume(co, wait, resolve)

  if not success then
    error(debug.traceback(co, initial_yield), 0)
  end
end

return async
