((params_block) @injection.content
  (#set! injection.language "lua"))

(user_message
   (content) @injection.content
  (#set! injection.language "markdown"))

(assistant_message
   (content) @injection.content
  (#set! injection.language "markdown"))

((data_section_body) @injection.content
  (#set! injection.language "markdown"))
