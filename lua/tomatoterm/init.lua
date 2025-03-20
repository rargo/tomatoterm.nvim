local M = {}

--M.debug = false
M.debug = true

M.next_term_no = 1

M.terminals = {}

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

local function check_insert_mode(msg)
  if vim.fn.mode() ~= 'i' then
    DP("feedkeys i:" .. msg)
    vim.fn.feedkeys('i', 'n')
  end
end

local function do_switch_buffer(bufnr, buf_switch_cb)
  local wins = vim.fn.win_findbuf(bufnr)
  if #wins ~= 0 then
    --jump to window instead of switch buffer
    local winid = vim.fn.win_getid(wins[1])
    vim.fn.win_gotoid(wins[1])
    --vim.cmd(winid .. "wincmd w")
  else
    vim.cmd("b " .. bufnr)
    if buf_switch_cb ~= nil then
      buf_switch_cb()
    end
  end
end

local function switch_buffer(next)
  --DP("switch_buffer")
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
    --DP("no open terminal")
    require("notify")("No buffer open", "info", { title = "Buffer Switch", timeout = 1000, })
    return
  end

  if #bufs_nr == 1 then
    if curbuf_is_terminal == false then
      require("notify")("No other buffers ", "info", { title = "Buffer Switch", timeout = 1000, })
      return
    end
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
    require("notify")("Wrap to the first buffer", "info", { title = "Buffer Switch", timeout = 1000, })
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
    require("notify")("Wrap to the last buffer ", "info", { title = "Buffer Switch", timeout = 1000, })
    do_switch_buffer(bufs_nr[1])
  end
end

local function do_switch_terminal(bufnr, wrap)
  local terminal = M.terminals[bufnr]
  local info = "Terminal"
  if terminal ~= nil then
    local term_no = terminal.no
    local job_id = terminal.job_id

    info = info .. " " .. term_no

    local pid = vim.fn.jobpid(job_id)
    local cmd = "ps -p " .. pid .. " -o comm="
    local h = io.popen(cmd)
    local process_name = h:read("*a")
    h:close()
    process_name = string.gsub(process_name, "\n","")
    info = info .. " " .. process_name .. "(" .. pid ..  ")"
  else
    info = info .. " bufnr:" .. bufnr
  end

  if wrap ~= nil then
    if wrap == "wrap_first" then
      info = info .. " (FIRST buffer)"
    else 
      if wrap == "wrap_last" then
        info = info .. " (LAST buffer)"
      end
    end
  end
  require("notify")(info, "info", { title = "Terminal Switch", timeout = 1000, })
  do_switch_buffer(bufnr)
end

local function switch_terminal(next)
  --DP("switch_terminal")
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
    require("notify")("No terminal open", "info", { title = "Terminal Switch", timeout = 1000, })
    return
  end

  if #terminal_bufs_nr == 1 then
    if curbuf_is_terminal == true then
      require("notify")("No other terminal ", "info", { title = "Buffer Switch", timeout = 1000, })
      --no other terminal to be switch
      -- need to feedkeys, becase tmap key switch back to normal mode, 
      -- and no buffer switch, so there is no TermEnter event trigger
      check_insert_mode("curbuf is the only terminal")
      return
    end
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
    --M.prev_terminal_bufnr = bufnr
    DP("OnTermOpen add terminal, term_no:" .. terminal.no)
    --DP("OnTermOpen set prev_terminal_bufnr to " .. bufnr)
  end
  --if (vim.fn.mode() ~= 't' and (vim.b.term_mode == false or vim.b.term_mode == nil)) then
  check_insert_mode("OnTermOpen")
  --M.prev_buffer_is_terminal = true
end

-- TODO 
-- on term leave, nerdtree windows will cover the whole screen
local function OnTermLeave()
  local bufname = vim.api.nvim_buf_get_name(0)
  local bufnr = vim.fn.bufnr()
  local mode = vim.fn.mode() 
  DP("-------------------------------")
  DP("OnTermLeave mode:" .. mode .. " bufnr:" .. bufnr .. " name:" .. bufname)
  --vim.b.term_mode = false
  DP("")
end

-- note: switch from non terminal to terminal win trigger OnWinEnter_term event,
-- switch from terminal to terminal WON'T trigger OnWinEnter_term event
local function OnWinEnter_term()
  local bufname = vim.api.nvim_buf_get_name(0)
  local bufnr = vim.fn.bufnr()
  local mode = vim.fn.mode() 
  DP("-------------------------------")
  DP("OnWinEnter_term mode:" .. mode .. " bufnr:" .. bufnr .. " name:" .. bufname)
  check_insert_mode("OnWinEnter_term")
end

local function OnBufEnter_all()
  local bufname = vim.api.nvim_buf_get_name(0)
  local bufnr = vim.fn.bufnr()
  local mode = vim.fn.mode() 
  DP("-------------------------------")
  DP("OnBufEnter_all mode:" .. mode .. " bufnr:" .. bufnr .. " name:" .. bufname)
  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    DP("OnBufEnter_all is terminal")
    DP("OnBufEnter_all set prev_buffer_bufnr to " .. bufnr)
    M.prev_terminal_bufnr = vim.fn.bufnr()
    if M.prev_buffer_is_terminal == true then
      -- since switch from terminal to terminal WON'T trigger OnWinEnter_term event, 
      -- we check if last buffer is also terminal, if so, feedkeys to enter terminal mode
      check_insert_mode("OnBufEnter_all prev buffer is terminal")
    end
    M.prev_buffer_is_terminal = true
  else

    -- switch from terminal to buffer, because terminal mode is insert mode
    -- need to feedkeys to go back normal mode
    M.prev_buffer_is_terminal = false
    DP("OnBufEnter_all is buffer")
    --if vim.fn.mode() ~= 't' then
    -- first terminal open will trigger BufEnter with buffer name is ""
    if vim.api.nvim_buf_get_name(0) ~= "" then
      DP("OnBufEnter_all set prev_buffer_bufnr to " .. bufnr)
      M.prev_buffer_bufnr = vim.fn.bufnr()
    end
  end
  DP("")
end

M.switch_buffer_terminal = function(next)
  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    switch_terminal(next)
  else
    switch_buffer(next)
  end
end

M.buffer_terminal_toggle = function()
  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    if M.prev_buffer_bufnr ~= nil then
      if vim.fn.buflisted(M.prev_buffer_bufnr) ~= 0 then
        do_switch_buffer(M.prev_buffer_bufnr)
      else
        require("notify")("Alternate buf not existed, switch to next buffer", "info", { title = "Buffer Switch", timeout = 1000, })
        switch_buffer(true)
      end
    else
      switch_buffer(true)
    end
  else
    if M.prev_terminal_bufnr ~= nil then
      if vim.fn.buflisted(M.prev_terminal_bufnr) ~= 0 then
        do_switch_buffer(M.prev_terminal_bufnr, function()
          check_insert_mode("switch back to alternate terminal")
        end)
      else
        require("notify")("Alternate terminal not existed, switch to next terminal", "info", { title = "Terminal Switch", timeout = 1000, })
        switch_terminal(true)
      end
    else
      switch_terminal(true)
    end
  end
end

M.send_to_terminal = function(switch_to_terminal)
  terminal_chans = {}
  for _, chan in pairs(vim.api.nvim_list_chans()) do
    --M.dp_table(chan)
    if chan["mode"] == "terminal" and chan["pty"] ~= "" then
      table.insert(terminal_chans, chan)
    end
  end

  if #terminal_chans == 0 then
    require("notify")("No terminal open", "info", { title = "Send to terminal", timeout = 1000, })
    return
  end

  -- sort to get the first terminal
  table.sort(terminal_chans, function(left, right)
    return left["buffer"] < right["buffer"]
  end)

  local first_terminal_chan_id = terminal_chans[1]["id"]
  local first_terminal_buffer_id = terminal_chans[1]["buffer"]

  local line_start = vim.fn.line("'<")
  local line_end = vim.fn.line("'>")

  local col_start = vim.fn.col("'<")
  local col_end = vim.fn.col("'>")

  local line_text=""
  if line_start == line_end then
    -- one line
    line_text = vim.fn.strcharpart(vim.fn.getline(line_start), col_start-1, col_end-col_start+1) .. "\n"
  else
    line_text = table.concat(vim.fn.getline(line_start, line_end), "\n") .. "\n"
  end

  vim.api.nvim_chan_send(first_terminal_chan_id, line_text)
  if switch_to_terminal then
    do_switch_buffer(first_terminal_buffer_id)
  end
end

M.setup = function()
  DP("tomatoterm setup")
  au({'TermOpen'}, 'term://*', OnTermOpen)
  au({'TermLeave'}, 'term://*', OnTermLeave)
  au({'BufEnter'}, '*', OnBufEnter_all)
  au({'WinEnter'}, 'term://*', OnWinEnter_term)

  vim.api.nvim_set_keymap('t', '<C-t>', 
    '<C-\\><C-N><cmd>lua require("tomatoterm").buffer_terminal_toggle()<cr>',
  {noremap = true, silent = true})
  vim.api.nvim_set_keymap('t', '<C-n>',
    '<C-\\><C-N><cmd>lua require("tomatoterm").switch_buffer_terminal(true)<cr>',
  {noremap = true, silent = true})
  vim.api.nvim_set_keymap('t', '<C-p>',
    '<C-\\><C-N><cmd>lua require("tomatoterm").switch_buffer_terminal(false)<cr>',
  {noremap = true, silent = true})

  vim.api.nvim_set_keymap('n', '<C-t>', 
    '<C-\\><C-N><cmd>lua require("tomatoterm").buffer_terminal_toggle()<cr>',
  {noremap = true, silent = true})
  vim.api.nvim_set_keymap('n', '<C-n>',
    '<C-\\><C-N><cmd>lua require("tomatoterm").switch_buffer_terminal(true)<cr>',
  {noremap = true, silent = true})
  vim.api.nvim_set_keymap('n', '<C-p>',
    '<C-\\><C-N><cmd>lua require("tomatoterm").switch_buffer_terminal(false)<cr>',
  {noremap = true, silent = true})

  -- send visual select text to terminal run:
  vim.api.nvim_set_keymap('n', 's', 
    "<ESC><cmd>lua require('tomatoterm').send_to_terminal(true)<CR>",
  {noremap = true, silent = true})
end

return M
