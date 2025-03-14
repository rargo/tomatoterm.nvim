local M = {}

M.debug = false

M.next_term_no = 1

M.term_list = {}
M.term_job_id = {}

local group = vim.api.nvim_create_augroup('tomatoterm', {})

local function au(typ, pattern, cmdOrFn)
  if type(cmdOrFn) == 'function' then
    vim.api.nvim_create_autocmd(typ, { pattern = pattern, callback = cmdOrFn, group = group })
  else
    vim.api.nvim_create_autocmd(typ, { pattern = pattern, command = cmdOrFn, group = group })
  end
end

local keymap_default_options = {noremap = true, silent = true}
local keymap_expr_options = {noremap = true, expr = true, silent = true}

local function nmap(key, command, option)
  if (option == nil) then
    option = keymap_default_options
  end
  vim.api.nvim_set_keymap('n', key, command, option)
end

local function tmap(key, command, option)
  if (option == nil) then
    option = keymap_default_options
  end
  vim.api.nvim_set_keymap('t', key, command, option)
end

local function vmap(key, command, option)
  if (option == nil) then
    option = keymap_default_options
  end
  vim.api.nvim_set_keymap('v', key, command, option)
end

local function DP(text)
  if M.debug then
    print(text)
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
    vim.cmd("b " .. first_terminal_buffer_id)
  end
end

M.switch_buffer = function(next)
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
        vim.cmd("b " .. nr)
        return
      end
    end
    require("notify")("Wrap to the first buffer", "info", { title = "Buffer Switch", timeout = 1000, })
    vim.cmd("b " .. bufs_nr[1])
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
        vim.cmd("b " .. nr)
        return
      end
    end
    require("notify")("Wrap to the last buffer ", "info", { title = "Buffer Switch", timeout = 1000, })
    vim.cmd("b " .. bufs_nr[1])
  end
end

local function do_switch_terminal(bufnr, wrap)
  local term_no = M.term_list[bufnr]
  local info = "Terminal"
  if term_no ~= nil then
    info = info .. " " .. term_no
  end

  local job_id = M.term_job_id[bufnr]
  if job_id ~= nil then
    local pid = vim.fn.jobpid(job_id)
    local cmd = "ps -p " .. pid .. " -o comm="
    local h = io.popen(cmd)
    local process_name = h:read("*a")
    h:close()
    process_name = string.gsub(process_name, "\n","")
    info = info .. " " .. process_name .. "(" .. pid ..  ")"
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
  vim.cmd("b " .. bufnr)
end

M.switch_terminal = function(next)
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
      if vim.fn.mode() == 'n' then
        -- need to feedkeys, becase tmap key switch back to normal mode, 
        -- and no buffer switch, so there is no TermEnter event trigger
        vim.fn.feedkeys('i', 'n')
      end
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

  -- need to feedkeys, becase keymaps will go back to normal mode, and the terminal event will not trigger
  -- if vim.fn.mode() == 'n' then
  --   vim.fn.feedkeys('i', 'n')
  -- end
end

M.switch_buffer_terminal = function(next)
  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    M.switch_terminal(next)
  else
    M.switch_buffer(next)
  end
end

M.buffer_terminal_toggle = function()
  DP("buffer_terminal_toggle")
  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    if M.prev_buffer_bufnr ~= nil then
      DP("111 " .. M.prev_buffer_bufnr)
      if vim.fn.buflisted(M.prev_buffer_bufnr) ~= 0 then
        vim.cmd("b " .. M.prev_buffer_bufnr)
      else
        require("notify")("Alternate buf not existed, switch to next buffer", "info", { title = "Buffer Switch", timeout = 1000, })
        M.switch_buffer(true)
      end
    else
      DP("222")
      M.switch_buffer(true)
    end
  else
    if M.prev_terminal_bufnr ~= nil then
      DP("33" .. M.prev_terminal_bufnr)
      if vim.fn.buflisted(M.prev_terminal_bufnr) ~= 0 then
        vim.cmd("b " .. M.prev_terminal_bufnr)
      else
        require("notify")("Alternate terminal not existed, switch to next terminal", "info", { title = "Terminal Switch", timeout = 1000, })
        M.switch_terminal(true)
      end
    else
      DP("44")
      M.switch_terminal(true)
    end
  end
end

local function OnTermOpen()
  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    local bufnr = vim.fn.bufnr()
    DP("@ buf event add terminal " .. bufnr)
    vim.b.term_no = M.next_term_no
    M.term_list[bufnr] = M.next_term_no
    M.next_term_no = M.next_term_no + 1

    M.term_job_id[bufnr] = vim.b.terminal_job_id

    M.prev_terminal_bufnr = bufnr
  end
  if (vim.fn.mode() ~= 't' and (vim.b.term_mode == false or vim.b.term_mode == nil)) then
    vim.fn.feedkeys('i', 'n');
    vim.b.term_mode = true
  end
end

local function OnTermLeave()

  -- TODO 
  -- on term leave, nerdtree windows will cover the whole screen
  vim.b.term_mode = false
end

local function OnBufEnter_term()
  if (vim.fn.mode() ~= 't' and (vim.b.term_mode == false or vim.b.term_mode == nil)) then
    vim.fn.feedkeys('i', 'n');
    vim.b.term_mode = true
  end
end

local function OnBufEnter_all()
  DP(vim.api.nvim_buf_get_name(0))
  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    DP("buf event add terminal " .. vim.fn.bufnr())
    M.prev_terminal_bufnr = vim.fn.bufnr()
  else
    --if vim.fn.mode() ~= 't' then
    -- first terminal open will trigger BufEnter with buffer name is ""
    if vim.api.nvim_buf_get_name(0) ~= "" then
      DP("buf event add buffer " .. vim.fn.bufnr())
      M.prev_buffer_bufnr = vim.fn.bufnr()
    end
  end
end

M.setup = function()
  DP("tomatoterm setup")
  au({'TermOpen'}, 'term://*', OnTermOpen)
  au({'TermLeave'}, 'term://*', OnTermLeave)
  au({'BufEnter'}, 'term://*', OnBufEnter_term)
  au({'BufEnter'}, '*', OnBufEnter_all)

  tmap('<C-t>', '<C-\\><C-N><cmd>lua require("tomatoterm").buffer_terminal_toggle()<cr>')
  tmap('<C-n>', '<C-\\><C-N><cmd>lua require("tomatoterm").switch_buffer_terminal(true)<cr>')
  tmap('<C-p>', '<C-\\><C-N><cmd>lua require("tomatoterm").switch_buffer_terminal(false)<cr>')

  nmap('<C-t>', '<cmd>lua require("tomatoterm").buffer_terminal_toggle()<cr>')
  nmap('<C-n>', '<cmd>lua require("tomatoterm").switch_buffer_terminal(true)<cr>')
  nmap('<C-p>', '<cmd>lua require("tomatoterm").switch_buffer_terminal(false)<cr>')

  -- send visual select text to terminal run:
  vmap('s', "<ESC><cmd>lua require('tomatoterm').send_to_terminal(true)<CR>")
end

return M
