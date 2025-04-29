local M = {}

M.version = "0.1"

-- M.debug = true

M.next_term_no = 1

M.terminals = {}

M.default_options = {
  start_new_terminal_if_none_exist = true;
  keys = {
    -- it's hard to find keys that both not used in neovim and shell
    -- follow compromise solution
    toggle = "<C-t>",
    next_buffer_terminal = "<C-n>",
    prev_buffer_terminal = "<C-p>",
    add_terminal = "<F12>",
    add_terminal_vertical_split = "<C-F12>",
    set_terminal_name = "<C-s>",
    visual_mode_send_to_terminal = "s", -- visual mode map
  }
}
M.options = {}

local keymap_options = {noremap = true, silent = true}

local group = vim.api.nvim_create_augroup('tomatoterm', {})

local function au(typ, pattern, cmdOrFn)
  if type(cmdOrFn) == 'function' then
    vim.api.nvim_create_autocmd(typ, { pattern = pattern, callback = cmdOrFn, group = group })
  else
    vim.api.nvim_create_autocmd(typ, { pattern = pattern, command = cmdOrFn, group = group })
  end
end

local function DP(text)
  if M.debug then
    print(text)
  end
end

local function get_term_process_cwd(job_id)
  local pid = vim.fn.jobpid(job_id)
  cmd = "pwdx " .. pid .. " | awk '{print $2}' | tr -d \"\\n\""
  h = io.popen(cmd)
  local pwd = h:read("*a")
  h:close()

  return pwd
end

local function get_term_process_name(job_id)
  local pid = vim.fn.jobpid(job_id)
  local cmd = "ps -p " .. pid .. " -o comm="
  local h = io.popen(cmd)
  local process_name = h:read("*a")
  h:close()
  process_name = string.gsub(process_name, "\n","")

  return process_name
end


--terminal_check_insert_mode: 
--    if current terminal is not in insert mode, feedkeys i to enter insert mode
local function terminal_check_insert_mode(debug_msg)
  DP("vim mode: " .. vim.fn.mode())
  if (vim.fn.mode() ~= 'i' and vim.fn.mode() ~= 't') and (vim.b.feedkeys == nil or vim.b.feedkeys == false) then
    DP("feedkeys i:" .. debug_msg)
    vim.fn.feedkeys('i', 'n')
    vim.b.feedkeys = true
  end
end

local function notify(title, content)
  require("notify").dismiss()
  require("notify")(content, "info", { title = title, timeout = 2000, })
end

local function do_switch_buffer(bufnr)
  local info = ""
  info = info .. vim.fn.bufname(bufnr)
  notify("Buffer Switch", info)
  local wins = vim.fn.win_findbuf(bufnr)
  if #wins ~= 0 then
    --jump to window instead of switch buffer
    local winid = vim.fn.win_getid(wins[1])
    vim.fn.win_gotoid(wins[1])
    --vim.cmd(winid .. "wincmd w")
  else
    vim.cmd("b " .. bufnr)
  end
end

local function set_keymap(mode, key, action, keymap_opt)
  if key ~= false and key ~= nil then
    vim.api.nvim_set_keymap(mode, key, action, keymap_opt)
  end
end

local function do_switch_terminal(bufnr, wrap)
  local terminal = M.terminals[bufnr]
  local info = "Terminal"
  if terminal ~= nil then
    local term_no = terminal.no
    local job_id = terminal.job_id

    info = info .. " " .. term_no

    local process_name = get_term_process_name(job_id)
    info = info .. "\n" .. "name: " .. process_name

    local pwd = get_term_process_cwd(job_id)
    info = info .. "\n" .. "pwd: " .. pwd
  else
    -- for those terminal opened on session restore, we don't have terminal variable available
    info = info .. " bufnr:" .. bufnr
  end

  if wrap ~= nil then
    if wrap == "wrap_first" then
      info = info .. "\n" .. "wrap to FIRST terminal"
    else 
      if wrap == "wrap_last" then
        info = info .. "\n" .. "wrap to LAST terminal"
      end
    end
  end
  notify("Terminal Switch", info)
  --terminal is also a buffer in neovim
  local wins = vim.fn.win_findbuf(bufnr)
  if #wins ~= 0 then
    --jump to window instead of switch buffer
    local winid = vim.fn.win_getid(wins[1])
    vim.fn.win_gotoid(wins[1])
    --vim.cmd(winid .. "wincmd w")
  else
    vim.cmd("b " .. bufnr)
  end
end

M.switch_to_buffer = function(next)
  --DP("switch_to_buffer")
  local curbuf_nr = vim.fn.bufnr() 
  local curbuf_is_terminal = false
  local buffers = vim.api.nvim_list_bufs()

  local bufs_nr = {}

  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    curbuf_is_terminal = true
  end
  
  for _, buf in ipairs(buffers) do
    local bufnr = vim.fn.bufnr(buf)
    local name = vim.api.nvim_buf_get_name(buf)

    if vim.fn.buflisted(buf) == 0 then
      goto loop
    end

    --DP("buffer " .. bufnr .. " name:" .. name)
    if string.match(name, "term://") == nil then
      table.insert(bufs_nr, bufnr)
    end

  ::loop::
  end

  --DP(table.concat(bufs_nr, " "))
  if #bufs_nr == 0 then
    notify("Buffer Switch", "No buffer open")
    if curbuf_is_terminal == true then
      -- need to feedkeys, becase tmap key switch back to normal mode, 
      -- and no buffer switch, so there is no BufEnter event trigger
      terminal_check_insert_mode("No buffer open, stay in current terminal")
    end
    return
  end

  if #bufs_nr == 1 and curbuf_is_terminal == false then
    notify("Buffer Switch", "No other buffer")
    return
  end

  if next then
    table.sort(bufs_nr)
    for _, nr in ipairs(bufs_nr) do
      -- jump to the next terminal which bufnr is right after current buffer
      if nr > curbuf_nr then
        do_switch_buffer(nr)
        return
      end
    end
    notify("Buffer Switch", "Wrap to the first buffer")
    do_switch_buffer(bufs_nr[1])
  else
    table.sort(bufs_nr, function(left, right)
      if (left > right) then
        return true
      end
    end
    )
    for _, nr in ipairs(bufs_nr) do
      -- jump to the next terminal which bufnr is right after current buffer
      if nr < curbuf_nr then
        do_switch_buffer(nr)
        return
      end
    end
    notify("Buffer Switch", "Wrap to the last buffer")
    do_switch_buffer(bufs_nr[1])
  end
end

M.switch_to_terminal = function(next)
  --DP("switch_to_terminal")
  local curbuf_nr = vim.fn.bufnr() 
  local curbuf_is_terminal = false
  local buffers = vim.api.nvim_list_bufs()

  local terminal_bufs_nr = {}

  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    DP("current is terminal")
    curbuf_is_terminal = true
  end
  
  for _, buf in ipairs(buffers) do
    local bufnr = vim.fn.bufnr(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    --DP("buffer " .. bufnr .. " name:" .. name)

    if vim.fn.buflisted(buf) == 0 then
      goto loop
    end

    if string.match(name, "term://") ~= nil then
      table.insert(terminal_bufs_nr, bufnr)
    end

  ::loop::
  end

  if #terminal_bufs_nr == 0 then
    --DP("no open terminal")
    if M.options.start_new_terminal_if_none_exist == true then
      vim.cmd("keepalt terminal")
      notify("Terminal Switch", "No terminal open, start a new one")
    else
      notify("Terminal Switch", "No terminal open")
    end
    return
  end

  if #terminal_bufs_nr == 1 and curbuf_is_terminal == true then
    notify("Terminal Switch", "no other terminal")
    --no other terminal to be switch
    -- need to feedkeys, becase tmap key switch back to normal mode, 
    -- and no buffer switch, so there is no BufEnter event trigger
    terminal_check_insert_mode("curbuf is the only terminal")
    return
  end

  if next then
    table.sort(terminal_bufs_nr)
    for _, nr in ipairs(terminal_bufs_nr) do
      -- jump to the next terminal which bufnr is right after current buffer
      if nr > curbuf_nr then
        do_switch_terminal(nr)
        return
      end
    end
    local nr = terminal_bufs_nr[1]
    do_switch_terminal(nr, "wrap_first")
  else
    table.sort(terminal_bufs_nr, function(left, right)
      if (left > right) then
        return true
      end
    end
    )
    for _, nr in ipairs(terminal_bufs_nr) do
      if nr < curbuf_nr then
        do_switch_terminal(nr)
        return
      end
    end
    local nr = terminal_bufs_nr[1]
    do_switch_terminal(nr, "wrap_last")
  end
end

-- automatically change to insert mode in terminal windows
local function OnTermOpen()
  local bufname = vim.api.nvim_buf_get_name(0)
  local bufnr = vim.fn.bufnr()
  DP("-------------------------------")
  DP("OnTermOpen bufnr:" .. bufnr .. " name:" .. bufname)
  if string.match(bufname, "term://") ~= nil then
    vim.b.term_no = M.next_term_no
    local terminal = {}

    terminal.no = M.next_term_no
    terminal.job_id = vim.b.terminal_job_id

    M.next_term_no = M.next_term_no + 1

    -- vim.ui.input({ prompt = 'Enter terminal name: ' }, function(input)
    --   terminal.name = input
    -- end)
    -- terminal.name = vim.fn.input("Enter terminal name")

    M.terminals[bufnr] = terminal
    DP("OnTermOpen add terminal, term_no:" .. terminal.no)
  end
  terminal_check_insert_mode("OnTermOpen")
end

local function OnTermLeave()
  local bufname = vim.api.nvim_buf_get_name(0)
  local bufnr = vim.fn.bufnr()
  local mode = vim.fn.mode() 
  DP("-------------------------------")
  DP("OnTermLeave mode:" .. mode .. " bufnr:" .. bufnr .. " name:" .. bufname)
  DP("")
  vim.b.feedkeys = false
end

local function OnBufEnter()
  local bufname = vim.api.nvim_buf_get_name(0)
  local bufnr = vim.fn.bufnr()
  local mode = vim.fn.mode() 
  DP("-------------------------------")
  DP("OnBufEnter mode:" .. mode .. " bufnr:" .. bufnr .. " name:" .. bufname)
  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    DP("OnBufEnter is terminal")
    DP("OnBufEnter set prev_buffer_bufnr to " .. bufnr)
    M.prev_terminal_bufnr = vim.fn.bufnr()
    terminal_check_insert_mode("OnBufEnter buffer is terminal")
  else
    DP("OnBufEnter is buffer")
    -- first terminal open will trigger BufEnter with buffer name is ""
    if vim.api.nvim_buf_get_name(0) ~= "" then
      DP("OnBufEnter set prev_buffer_bufnr to " .. bufnr)
      M.prev_buffer_bufnr = vim.fn.bufnr()
    end
  end
  DP("")
end

M.switch_to_buffer_terminal = function(next)
  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    M.switch_to_terminal(next)
  else
    M.switch_to_buffer(next)
  end
end

M.toggle_buffer_terminal = function()
  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    --last is terminal, switch to a normal buffer
    if M.prev_buffer_bufnr ~= nil then
      if vim.fn.buflisted(M.prev_buffer_bufnr) ~= 0 then
        do_switch_buffer(M.prev_buffer_bufnr)
      else
        notify("Buffer Switch", "Alternate buffer not existed, switch to next buffer")
        M.switch_to_buffer(true)
      end
    else
      M.switch_to_buffer(true)
    end
  else
    --last is normal buffer, switch to a terminal
    if M.prev_terminal_bufnr ~= nil then
      if vim.fn.buflisted(M.prev_terminal_bufnr) ~= 0 then
        do_switch_terminal(M.prev_terminal_bufnr)
      else
        notify("Buffer Switch", "Alternate terminal not existed, switch to next terminal")
        M.switch_to_terminal(true)
      end
    else
      M.switch_to_terminal(true)
    end
  end
end

M.send_to_terminal = function(switch_to_terminal)
  local buffers = vim.api.nvim_list_bufs()
  local terminals = {}
  for _, buf in ipairs(buffers) do
    --local bufnr = vim.fn.bufnr(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    --DP("buffer " .. bufnr .. " name:" .. name)

    if vim.fn.buflisted(buf) == 0 then
      goto loop
    end

    if string.match(name, "term://") ~= nil then
      local term = {}
      term.term_no = vim.fn.getbufvar(buf, "term_no", -1)
      term.term_name = vim.fn.getbufvar(buf, "term_name", "null")
      print("send_to_terminal term_no:" .. term.term_no .. " term_name:" .. term.term_name)

      term.buf_id = vim.fn.bufnr(buf)
      term.job_id = vim.fn.getbufvar(buf, "terminal_job_id", 0)
      print("send_to_terminal buf_id:" .. term.buf_id .. " job_id:" .. term.job_id)

      term.cwd = get_term_process_cwd(term.job_id)
      term.process_name = get_term_process_name(term.job_id)

      table.insert(terminals, term)
    end

  ::loop::
  end

  if #terminals == 0 then
    notify("Send to terminal", "No terminal open")
    return
  end

  local terminal_chan_id = -1
  local terminal_buf_id = -1
  if #terminals > 1 then
    -- let user select which terminal to send to
    
    local options = {}
    local option_chan_id = {}
    local option_buf_id = {}
    for _, term in ipairs(terminals) do
      local str = term.job_id .. " " .. term.process_name .. " " .. term.cwd
      
      if term.term_no ~= -1 then
        str = str .. " " .. term.term_no
      end

      if term.term_name ~= "null" then
        str = str .. " " .. term.term_name
      end

      option_chan_id.str = term.job_id
      option_buf_id.str = term.buf_id
    end

    -- local select = vim.fn.inputlist(options)
    -- print("select: " .. select)
    -- terminal_chan_id = option_chan_id[select]
    -- terminal_buf_id = option_buf_id[select]
    vim.ui.select(options, {
      prompt = 'please select one terminal to send to:'
    }, function(choice)
        terminal_chan_id = option_chan_id.choice
        terminal_buf_id = option_buf_id.choice
      end)
  else
    terminal_chan_id = terminals[1].job_id
    terminal_buf_id = terminals[1].buf_id
  end

  print("terminal_chan_id: " .. terminal_chan_id .. " terminal_buf_id: " .. terminal_buf_id)

  --terminal_chans = {}
  --for _, chan in pairs(vim.api.nvim_list_chans()) do
  --  --M.dp_table(chan)
  --  if chan["mode"] == "terminal" and chan["pty"] ~= "" then
  --    table.insert(terminal_chans, chan)
  --  end
  --end

  -- if #terminal_chans == 0 then
  --   notify("Send to terminal", "No terminal open")
  --   return
  -- end

  -- -- sort to get the first terminal
  -- table.sort(terminal_chans, function(left, right)
  --   return left["buffer"] < right["buffer"]
  -- end)

  -- local first_terminal_chan_id = terminal_chans[1]["id"]
  -- local first_terminal_buffer_id = terminal_chans[1]["buffer"]

  -- local line_start = vim.fn.line("'<")
  -- local line_end = vim.fn.line("'>")

  -- local col_start = vim.fn.col("'<")
  -- local col_end = vim.fn.col("'>")
  local _line_start, _col_start = unpack(vim.fn.getpos("."), 2, 3)
  local _line_end, _col_end = unpack(vim.fn.getpos("v"), 2, 3)
  -- local pos1 = vim.fn.getpos("'<")
  -- local pos2 = vim.fn.getpos("'>")

  -- local line_start = pos1[2]
  -- local line_end = pos2[2]

  -- local col_start = pos1[3]
  -- local col_end = pos2[3]

  local line_start = 0
  local line_end = 0
  if _line_start > _line_end then
    line_start = _line_end
    line_end = _line_start
  else
    line_start = _line_start
    line_end = _line_end
  end

  if _col_start > _col_end then
    col_start = _col_end
    col_end = _col_start
  else
    col_start = _col_start
    col_end = _col_end
  end

  print("line start: " .. line_start .. " line_end: " .. line_end)
  print("col start: " .. col_start .. " col_end: " .. col_end)

  local line_text=""
  -- if line_start == line_end then
  --   -- one line
  --   line_text = vim.fn.strcharpart(vim.fn.getline(line_start), col_start-1, col_end-col_start+1) .. "\n"
  -- else
    line_text = table.concat(vim.fn.getline(line_start, line_end), "\n") .. "\n"
  -- end

  print(line_text)

  vim.api.nvim_chan_send(terminal_chan_id, line_text)
  if switch_to_terminal then
    do_switch_buffer(terminal_buf_id)
  end
end

M.set_terminal_name = function() 
  -- vim.ui.input({ prompt = 'Set Terminal Name: ' }, function(input)
  --   if input ~= "" and input ~= nil then
  --     vim.b.term_name = input
  --   end
  -- end)
  local text = vim.fn.input("Set Terminal Name: ", "");
  if text ~= "" then
    vim.b.term_name = text
    if vim.b.term_no ~= nil then
      notify("Terminal " .. vim.b.term_no .. " New Name", text)
    else
      notify("Terminal New Name", text)
    end
  end
end

M.setup = function(opt)
  M.options = vim.tbl_deep_extend("force", M.default_options, options or {})

  DP("tomatoterm setup")
  au({'TermOpen'}, 'term://*', OnTermOpen)
  au({'TermLeave'}, 'term://*', OnTermLeave)
  au({'BufEnter'}, '*', OnBufEnter)

  -- <C-a> add a terminal
  set_keymap('t', M.options.keys.add_terminal,
    '<C-\\><C-N><cmd>keepalt terminal<CR>', keymap_options)
  -- <C-v> add a terminal vertical split
  set_keymap('t', M.options.keys.add_terminal_vertical_split,
    '<C-\\><C-N><cmd>keepalt rightbelow vsplit term://bash<CR>', keymap_options)

  -- <C-a> add a terminal
  set_keymap('n', M.options.keys.add_terminal,
    '<cmd>keepalt terminal<CR>', keymap_options)
  -- <C-v> add a terminal vertical split
  set_keymap('n', M.options.keys.add_terminal_vertical_split,
    '<cmd>keepalt rightbelow vsplit term://bash<CR>', keymap_options)

  set_keymap('t', M.options.keys.toggle, 
    '<C-\\><C-N><cmd>lua require("tomatoterm").toggle_buffer_terminal()<cr>', keymap_options)
  set_keymap('t', M.options.keys.next_buffer_terminal,
    '<C-\\><C-N><cmd>lua require("tomatoterm").switch_to_buffer_terminal(true)<cr>', keymap_options)
  set_keymap('t', M.options.keys.prev_buffer_terminal,
    '<C-\\><C-N><cmd>lua require("tomatoterm").switch_to_buffer_terminal(false)<cr>', keymap_options)

  set_keymap('n', M.options.keys.toggle, 
    '<cmd>lua require("tomatoterm").toggle_buffer_terminal()<cr>', keymap_options)
  set_keymap('n', M.options.keys.next_buffer_terminal,
    '<cmd>lua require("tomatoterm").switch_to_buffer_terminal(true)<cr>', keymap_options)
  set_keymap('n', M.options.keys.prev_buffer_terminal,
    '<cmd>lua require("tomatoterm").switch_to_buffer_terminal(false)<cr>', keymap_options)

  set_keymap('t', M.options.keys.set_terminal_name,
    '<cmd>lua require("tomatoterm").set_terminal_name()<cr>', keymap_options)

  set_keymap('t', M.options.keys.add_terminal_vertical_split,
    '<C-\\><C-N><cmd>keepalt rightbelow vsplit term://bash<CR>', keymap_options)

  set_keymap('v', M.options.keys.visual_mode_send_to_terminal,
    '<cmd>lua require("tomatoterm").send_to_terminal(true)<cr>', keymap_options)

  vim.api.nvim_create_user_command('TermSetName', function(opts)
    vim.b.term_name = opts.args
    if vim.b.term_no ~= nil then
      notify("Terminal " .. vim.b.term_no .. " New Name", text)
    else
      notify("Terminal New Name", text)
    end
  end, { nargs = 1 })
end


return M
