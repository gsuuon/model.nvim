local curl = require('model.util.curl')

return {
  description = 'Fetch the contents of a website using curl GET request',
  parameters = {
    type = 'object',
    properties = {
      url = {
        type = 'string',
        description = 'URL of the website to fetch',
      },
    },
    required = { 'url' },
  },
  invoke = function(args, callback)
    if type(args.url) ~= 'string' then
      error('Invalid URL: must be a string')
    end

    local canceled = false
    local cancel = nil

    cancel = curl.request({
      url = args.url,
      method = args.method or 'GET',
      headers = args.headers or {},
      body = args.body,
    }, function(text)
      if not canceled and callback then
        callback(text)
      end
    end, function(error_text)
      if not canceled and callback then
        callback(nil, error_text)
      end
    end)

    return function()
      canceled = true
      if cancel then
        cancel()
      end
    end
  end,
}
