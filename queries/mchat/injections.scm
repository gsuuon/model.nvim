((params_block) @injection.content
                (#set! injection.language "lua"))

(user_message
  (content) @injection.content
  (#set! injection.language "markdown"))

(assistant_message
  (content) @injection.content
  (#set! injection.language "markdown"))

(assistant_message
  (data_section
    (data_section_open) @_marker
    (data_section_body) @injection.content
    (#eq? @_marker "<<<<<< tool_calls")
    (#set! injection.language "javascript")))

(assistant_message
  (data_section
    (data_section_open) @_marker
    (data_section_body) @injection.content
    (#not-eq? @_marker "<<<<<< tool_calls")
    (#set! injection.language "markdown")))
