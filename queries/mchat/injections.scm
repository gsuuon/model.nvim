((params_block) @injection.content
  (#set! injection.language "lua"))

((user_message) @injection.content
  (#set! injection.language "markdown"))

((assistant_message) @injection.content
  (#set! injection.language "markdown"))
