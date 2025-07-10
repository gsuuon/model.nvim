type Buffer = number;
type Window = number;
type Tabpage = number;

export declare interface Nvim {
  nvim_get_autocmds: (opts: Record<string, unknown>) => Array<unknown>;

  nvim_create_autocmd: (event: Record<string, unknown>, opts: Record<string, unknown>) => number;

  nvim_del_autocmd: (id: number) => void;

  nvim_clear_autocmds: (opts: Record<string, unknown>) => void;

  nvim_create_augroup: (name: string, opts: Record<string, unknown>) => number;

  nvim_del_augroup_by_id: (id: number) => void;

  nvim_del_augroup_by_name: (name: string) => void;

  nvim_exec_autocmds: (event: Record<string, unknown>, opts: Record<string, unknown>) => void;

  nvim_buf_line_count: (buffer: Buffer) => number;

  nvim_buf_attach: (buffer: Buffer, send_buffer: boolean, opts: Record<string, unknown>) => boolean;

  nvim_buf_detach: (buffer: Buffer) => boolean;

  nvim_buf_get_lines: (buffer: Buffer, start: number, end: number, strict_indexing: boolean) => string[];

  nvim_buf_set_lines: (buffer: Buffer, start: number, end: number, strict_indexing: boolean, replacement: string[]) => void;

  nvim_buf_set_text: (buffer: Buffer, start_row: number, start_col: number, end_row: number, end_col: number, replacement: string[]) => void;

  nvim_buf_get_text: (buffer: Buffer, start_row: number, start_col: number, end_row: number, end_col: number, opts: Record<string, unknown>) => string[];

  nvim_buf_get_offset: (buffer: Buffer, index: number) => number;

  nvim_buf_get_var: (buffer: Buffer, name: string) => Record<string, unknown>;

  nvim_buf_get_changedtick: (buffer: Buffer) => number;

  nvim_buf_get_keymap: (buffer: Buffer, mode: string) => Record<string, unknown>[];

  nvim_buf_set_keymap: (buffer: Buffer, mode: string, lhs: string, rhs: string, opts: Record<string, unknown>) => void;

  nvim_buf_del_keymap: (buffer: Buffer, mode: string, lhs: string) => void;

  nvim_buf_set_var: (buffer: Buffer, name: string, value: Record<string, unknown>) => void;

  nvim_buf_del_var: (buffer: Buffer, name: string) => void;

  nvim_buf_get_name: (buffer: Buffer) => string;

  nvim_buf_set_name: (buffer: Buffer, name: string) => void;

  nvim_buf_is_loaded: (buffer: Buffer) => boolean;

  nvim_buf_delete: (buffer: Buffer, opts: Record<string, unknown>) => void;

  nvim_buf_is_valid: (buffer: Buffer) => boolean;

  nvim_buf_del_mark: (buffer: Buffer, name: string) => boolean;

  nvim_buf_set_mark: (buffer: Buffer, name: string, line: number, col: number, opts: Record<string, unknown>) => boolean;

  nvim_buf_get_mark: (buffer: Buffer, name: string) => [number, number];

  nvim_buf_call: (buffer: Buffer, fun: unknown) => Record<string, unknown>;

  nvim_parse_cmd: (str: string, opts: Record<string, unknown>) => Record<string, unknown>;

  nvim_cmd: (cmd: Record<string, unknown>, opts: Record<string, unknown>) => string;

  nvim_create_user_command: (name: string, command: Record<string, unknown>, opts: Record<string, unknown>) => void;

  nvim_del_user_command: (name: string) => void;

  nvim_buf_create_user_command: (buffer: Buffer, name: string, command: Record<string, unknown>, opts: Record<string, unknown>) => void;

  nvim_buf_del_user_command: (buffer: Buffer, name: string) => void;

  nvim_get_commands: (opts: Record<string, unknown>) => Record<string, unknown>;

  nvim_buf_get_commands: (buffer: Buffer, opts: Record<string, unknown>) => Record<string, unknown>;

  nvim_create_namespace: (name: string) => number;

  nvim_get_namespaces: () => Record<string, unknown>;

  nvim_buf_get_extmark_by_id: (buffer: Buffer, ns_id: number, id: number, opts: Record<string, unknown>) => number[];

  nvim_buf_get_extmarks: (buffer: Buffer, ns_id: number, start: Record<string, unknown>, end: Record<string, unknown>, opts: Record<string, unknown>) => Array<unknown>;

  nvim_buf_set_extmark: (buffer: Buffer, ns_id: number, line: number, col: number, opts: Record<string, unknown>) => number;

  nvim_buf_del_extmark: (buffer: Buffer, ns_id: number, id: number) => boolean;

  nvim_buf_add_highlight: (buffer: Buffer, ns_id: number, hl_group: string, line: number, col_start: number, col_end: number) => number;

  nvim_buf_clear_namespace: (buffer: Buffer, ns_id: number, line_start: number, line_end: number) => void;

  nvim_set_decoration_provider: (ns_id: number, opts: Record<string, unknown>) => void;

  nvim_get_option_value: (name: string, opts: Record<string, unknown>) => Record<string, unknown>;

  nvim_set_option_value: (name: string, value: Record<string, unknown>, opts: Record<string, unknown>) => void;

  nvim_get_all_options_info: () => Record<string, unknown>;

  nvim_get_option_info2: (name: string, opts: Record<string, unknown>) => Record<string, unknown>;

  nvim_tabpage_list_wins: (tabpage: Tabpage) => Window[];

  nvim_tabpage_get_var: (tabpage: Tabpage, name: string) => Record<string, unknown>;

  nvim_tabpage_set_var: (tabpage: Tabpage, name: string, value: Record<string, unknown>) => void;

  nvim_tabpage_del_var: (tabpage: Tabpage, name: string) => void;

  nvim_tabpage_get_win: (tabpage: Tabpage) => Window;

  nvim_tabpage_set_win: (tabpage: Tabpage, win: Window) => void;

  nvim_tabpage_get_number: (tabpage: Tabpage) => number;

  nvim_tabpage_is_valid: (tabpage: Tabpage) => boolean;

  nvim_ui_attach: (width: number, height: number, options: Record<string, unknown>) => void;

  nvim_ui_set_focus: (gained: boolean) => void;

  nvim_ui_detach: () => void;

  nvim_ui_try_resize: (width: number, height: number) => void;

  nvim_ui_set_option: (name: string, value: Record<string, unknown>) => void;

  nvim_ui_try_resize_grid: (grid: number, width: number, height: number) => void;

  nvim_ui_pum_set_height: (height: number) => void;

  nvim_ui_pum_set_bounds: (width: number, height: number, row: number, col: number) => void;

  nvim_ui_term_event: (event: string, value: Record<string, unknown>) => void;

  nvim_get_hl_id_by_name: (name: string) => number;

  nvim_get_hl: (ns_id: number, opts: Record<string, unknown>) => Record<string, unknown>;

  nvim_set_hl: (ns_id: number, name: string, val: Record<string, unknown>) => void;

  nvim_get_hl_ns: (opts: Record<string, unknown>) => number;

  nvim_set_hl_ns: (ns_id: number) => void;

  nvim_set_hl_ns_fast: (ns_id: number) => void;

  nvim_feedkeys: (keys: string, mode: string, escape_ks: boolean) => void;

  nvim_input: (keys: string) => number;

  nvim_input_mouse: (button: string, action: string, modifier: string, grid: number, row: number, col: number) => void;

  nvim_replace_termcodes: (str: string, from_part: boolean, do_lt: boolean, special: boolean) => string;

  nvim_exec_lua: (code: string, args: Array<unknown>) => Record<string, unknown>;

  nvim_notify: (msg: string, log_level: number, opts: Record<string, unknown>) => Record<string, unknown>;

  nvim_strwidth: (text: string) => number;

  nvim_list_runtime_paths: () => string[];

  nvim_get_runtime_file: (name: string, all: boolean) => string[];

  nvim_set_current_dir: (dir: string) => void;

  nvim_get_current_line: () => string;

  nvim_set_current_line: (line: string) => void;

  nvim_del_current_line: () => void;

  nvim_get_var: (name: string) => Record<string, unknown>;

  nvim_set_var: (name: string, value: Record<string, unknown>) => void;

  nvim_del_var: (name: string) => void;

  nvim_get_vvar: (name: string) => Record<string, unknown>;

  nvim_set_vvar: (name: string, value: Record<string, unknown>) => void;

  nvim_echo: (chunks: Array<unknown>, history: boolean, opts: Record<string, unknown>) => void;

  nvim_out_write: (str: string) => void;

  nvim_err_write: (str: string) => void;

  nvim_err_writeln: (str: string) => void;

  nvim_list_bufs: () => Buffer[];

  nvim_get_current_buf: () => Buffer;

  nvim_set_current_buf: (buffer: Buffer) => void;

  nvim_list_wins: () => Window[];

  nvim_get_current_win: () => Window;

  nvim_set_current_win: (window: Window) => void;

  nvim_create_buf: (listed: boolean, scratch: boolean) => Buffer;

  nvim_open_term: (buffer: Buffer, opts: Record<string, unknown>) => number;

  nvim_chan_send: (chan: number, data: string) => void;

  nvim_list_tabpages: () => Tabpage[];

  nvim_get_current_tabpage: () => Tabpage;

  nvim_set_current_tabpage: (tabpage: Tabpage) => void;

  nvim_paste: (data: string, crlf: boolean, phase: number) => boolean;

  nvim_put: (lines: string[], type: string, after: boolean, follow: boolean) => void;

  nvim_subscribe: (event: string) => void;

  nvim_unsubscribe: (event: string) => void;

  nvim_get_color_by_name: (name: string) => number;

  nvim_get_color_map: () => Record<string, unknown>;

  nvim_get_context: (opts: Record<string, unknown>) => Record<string, unknown>;

  nvim_load_context: (dict: Record<string, unknown>) => Record<string, unknown>;

  nvim_get_mode: () => Record<string, unknown>;

  nvim_get_keymap: (mode: string) => Record<string, unknown>[];

  nvim_set_keymap: (mode: string, lhs: string, rhs: string, opts: Record<string, unknown>) => void;

  nvim_del_keymap: (mode: string, lhs: string) => void;

  nvim_get_api_info: () => Array<unknown>;

  nvim_set_client_info: (name: string, version: Record<string, unknown>, type: string, methods: Record<string, unknown>, attributes: Record<string, unknown>) => void;

  nvim_get_chan_info: (chan: number) => Record<string, unknown>;

  nvim_list_chans: () => Array<unknown>;

  nvim_list_uis: () => Array<unknown>;

  nvim_get_proc_children: (pid: number) => Array<unknown>;

  nvim_get_proc: (pid: number) => Record<string, unknown>;

  nvim_select_popupmenu_item: (item: number, insert: boolean, finish: boolean, opts: Record<string, unknown>) => void;

  nvim_del_mark: (name: string) => boolean;

  nvim_get_mark: (name: string, opts: Record<string, unknown>) => Array<unknown>;

  nvim_eval_statusline: (str: string, opts: Record<string, unknown>) => Record<string, unknown>;

  nvim_exec2: (src: string, opts: Record<string, unknown>) => Record<string, unknown>;

  nvim_command: (command: string) => void;

  nvim_eval: (expr: string) => Record<string, unknown>;

  nvim_call_function: (fn: string, args: Array<unknown>) => Record<string, unknown>;

  nvim_call_dict_function: (dict: Record<string, unknown>, fn: string, args: Array<unknown>) => Record<string, unknown>;

  nvim_parse_expression: (expr: string, flags: string, highlight: boolean) => Record<string, unknown>;

  nvim_open_win: (buffer: Buffer, enter: boolean, config: Record<string, unknown>) => Window;

  nvim_win_set_config: (window: Window, config: Record<string, unknown>) => void;

  nvim_win_get_config: (window: Window) => Record<string, unknown>;

  nvim_win_get_buf: (window: Window) => Buffer;

  nvim_win_set_buf: (window: Window, buffer: Buffer) => void;

  nvim_win_get_cursor: (window: Window) => [number, number];

  nvim_win_set_cursor: (window: Window, pos: [number, number]) => void;

  nvim_win_get_height: (window: Window) => number;

  nvim_win_set_height: (window: Window, height: number) => void;

  nvim_win_get_width: (window: Window) => number;

  nvim_win_set_width: (window: Window, width: number) => void;

  nvim_win_get_var: (window: Window, name: string) => Record<string, unknown>;

  nvim_win_set_var: (window: Window, name: string, value: Record<string, unknown>) => void;

  nvim_win_del_var: (window: Window, name: string) => void;

  nvim_win_get_position: (window: Window) => [number, number];

  nvim_win_get_tabpage: (window: Window) => Tabpage;

  nvim_win_get_number: (window: Window) => number;

  nvim_win_is_valid: (window: Window) => boolean;

  nvim_win_hide: (window: Window) => void;

  nvim_win_close: (window: Window, force: boolean) => void;

  nvim_win_call: (window: Window, fun: unknown) => Record<string, unknown>;

  nvim_win_set_hl_ns: (window: Window, ns_id: number) => void;

  nvim_win_text_height: (window: Window, opts: Record<string, unknown>) => Record<string, unknown>;
}
