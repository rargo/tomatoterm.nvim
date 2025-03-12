local M = {}

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

M.send_to_terminal = function(switch_to_terminal)
  terminal_chans = {}
  for _, chan in pairs(vim.api.nvim_list_chans()) do
    --M.print_table(chan)
    if chan["mode"] == "terminal" and chan["pty"] ~= "" then
      table.insert(terminal_chans, chan)
    end
  end

  if #terminal_chans == 0 then
    print("no open terminals")
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

  local line_text = table.concat(vim.fn.getline(line_start, line_end), "\n") .. "\n"
  --print(line_text)

  vim.api.nvim_chan_send(first_terminal_chan_id, line_text)
  if switch_to_terminal then
    vim.cmd("b " .. first_terminal_buffer_id)
  end
end

M.switch_buffer = function(next)
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

    --print("buffer " .. bufnr .. " name:" .. name)
    if string.match(name, "term://") == nil then
      table.insert(bufs_nr, bufnr)
    end

  ::loop::
  end

  --print(table.concat(bufs_nr, " "))
  if #bufs_nr == 0 then
    --print("no open terminal")
    require("notify")("No other buffers", "info", { title = "Buffer Switch", timeout = 1000, })
    return
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
  end

  if curbuf_is_terminal == true then
    vim.cmd("b " .. bufs_nr[1])
    return
  else
    if next then
      require("notify")("No next buffer", "info", { title = "Buffer Switch", timeout = 1000, })
    else
      require("notify")("No prev buffer", "info", { title = "Buffer Switch", timeout = 1000, })
    end
  end
end

M.switch_terminal = function(next)
  local curbuf_nr = vim.fn.bufnr() 
  local curbuf_is_terminal = false
  local buffers = vim.api.nvim_list_bufs()

  local terminal_bufs_nr = {}

  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    print("current is terminal")
    curbuf_is_terminal = true
  end
  
  for _, buf in ipairs(buffers) do
    local bufnr = vim.fn.bufnr(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    --print("buffer " .. bufnr .. " name:" .. name)

    if vim.fn.buflisted(buf) == 0 then
      goto loop
    end

    if string.match(name, "term://") ~= nil then
      table.insert(terminal_bufs_nr, bufnr)
    end

  ::loop::
  end

  if #terminal_bufs_nr == 0 then
    --print("no open terminal")
    require("notify")("No open terminals", "info", { title = "Terminal Switch", timeout = 1000, })
    return
  end

  if next then
    table.sort(terminal_bufs_nr)
    for _, nr in ipairs(terminal_bufs_nr) do
      -- jump to the next terminal which bufnr is right after current buffer
      if nr > curbuf_nr then
        vim.cmd("b " .. nr)
        return
      end
    end
  else
    table.sort(terminal_bufs_nr, function(left, right)
      if (left > right) then
        return true
      end
    end
    )
    for _, nr in ipairs(terminal_bufs_nr) do
      if nr < curbuf_nr then
        vim.cmd("b " .. nr)
        return
      end
    end
  end

  if curbuf_is_terminal == false then
      vim.cmd("b " .. terminal_bufs_nr[1])
      return
  else
    if next then
      require("notify")("No next terminal", "info", { title = "Terminal Switch", timeout = 1000, })
    else
      require("notify")("No prev terminal", "info", { title = "Terminal Switch", timeout = 1000, })
    end
    -- need to feedkeys, becase keymaps will go back to normal mode, and the terminal event will not trigger
    if vim.fn.mode() == 'n' then
      vim.fn.feedkeys('i', 'n')
    end
  end
end

M.switch_buffer_terminal = function(next)
  local curbuf_is_terminal = false
  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    print("curbuf_is_terminal true")
    curbuf_is_terminal = true
  else
    print("curbuf_is_terminal false")
  end

  if curbuf_is_terminal == true then
    M.switch_terminal(next)
  else
    M.switch_buffer(next)
  end
end

M.buffer_terminal_toggle = function()
  if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
    if M.prev_buffer_bufnr ~= nil then
      vim.cmd("b " .. M.prev_buffer_bufnr)
    else
      M.switch_buffer(true)
    end
  else
    if M.prev_terminal_bufnr ~= nil then
      vim.cmd("b " .. M.prev_terminal_bufnr)
    else
      M.switch_terminal(true)
    end
  end

end

M.setup = function()
  au({'TermOpen'}, 'term://*', function()
    if (vim.fn.mode() ~= 't' and (vim.b.term_mode == false or vim.b.term_mode == nil)) then
      vim.fn.feedkeys('i', 'n');
      vim.b.term_mode = true
    end
    --vim.cmd("setlocal statusline=%{b:term_title}")
  end)

  au({ 'BufEnter'}, 'term://*', function()
    if (vim.fn.mode() ~= 't' and (vim.b.term_mode == false or vim.b.term_mode == nil)) then
      vim.fn.feedkeys('i', 'n');
      vim.b.term_mode = true
    end
  end)

  au({ 'BufEnter'}, '*', function()
    if string.match(vim.api.nvim_buf_get_name(0), "term://") ~= nil then
      M.prev_terminal_bufnr = vim.fn.bufnr()
    else
      M.prev_buffer_bufnr = vim.fn.bufnr()
    end
  end)

  au({'TermLeave'}, 'term://*', function()
    vim.b.term_mode = false
  end)

  tmap('<C-t>', '<C-\\><C-N><cmd>lua require("tomatoterm").buffer_terminal_toggle()<cr>')
  nmap('<C-t>', '<cmd>lua require("tomatoterm").buffer_terminal_toggle()<cr>')
  nmap('<C-n>', '<cmd>lua require("tomatoterm").switch_buffer_terminal(true)<cr>')
  nmap('<C-p>', '<cmd>lua require("tomatoterm").switch_buffer_terminal(false)<cr>')
  tmap('<C-n>', '<C-\\><C-N><cmd>lua require("tomatoterm").switch_buffer_terminal(true)<cr>')
  tmap('<C-p>', '<C-\\><C-N><cmd>lua require("tomatoterm").switch_buffer_terminal(false)<cr>')
end

return M
