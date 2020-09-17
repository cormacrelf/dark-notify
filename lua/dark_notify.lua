-- http://lua-users.org/wiki/StringTrim
function trim6(s)
   return s:match'^()%s*$' and '' or s:match'^%s*(.*%S)'
end

-- from norcalli/nvim_utils
function nvim_create_augroups(definitions)
  for group_name, definition in pairs(definitions) do
    vim.api.nvim_command('augroup '..group_name)
    vim.api.nvim_command('autocmd!')
    for _, def in ipairs(definition) do
      -- if type(def) == 'table' and type(def[#def]) == 'function' then
      -- 	def[#def] = lua_callback(def[#def])
      -- end
      local command = table.concat(vim.tbl_flatten{'autocmd', def}, ' ')
      vim.api.nvim_command(command)
    end
    vim.api.nvim_command('augroup END')
  end
end

-- See https://github.com/neovim/neovim/issues/12544
-- neovim 0.5.0 will have vim.g.variable_name, but let's target 0.4.4 as it's already released
function mk_config()
  local exists = vim.api.nvim_call_function("exists", {"dark_notify_config"})
  if exists ~= 1 then
    vim.api.nvim_set_var("dark_notify_config", {})
  end
end

function get_config()
  mk_config()
  return vim.api.nvim_get_var("dark_notify_config")
end

function edit_config(fn)
  mk_config()
  local edit = vim.api.nvim_get_var("dark_notify_config")
  fn(edit)
  vim.api.nvim_set_var("dark_notify_config", edit)
end

function apply_mode(mode)
  local config = get_config()
  local sel = config.schemes[mode] or {}
  local colorscheme = sel.colorscheme or nil
  local bg = sel.background or mode
  local lltheme = sel.lightline or nil

  vim.api.nvim_command('set background=' .. bg)
  if colorscheme ~= nil then
    vim.api.nvim_command('colorscheme ' .. colorscheme)
  end

  -- now try to reload lightline
  local reloader = config.lightline_loaders[lltheme]
  local lightline = vim.api.nvim_call_function("exists", {"g:loaded_lightline"})

  if lightline == 1 then
    local update = false
    if lltheme ~= nil then
      vim.api.nvim_command("let g:lightline.colorscheme = \"" .. lltheme .. "\"")
      update = true
    end
    if reloader ~= nil then
      vim.api.nvim_command("source " .. reloader)
      update = true
    end
    if update then
      vim.api.nvim_command("call lightline#init()")
      vim.api.nvim_command("call lightline#colorscheme()")
      vim.api.nvim_command("call lightline#update()")
    end
  end

  edit_config(function (conf)
    conf.current_mode = mode
  end)
end

function apply_current_mode()
  local mode = vim.fn.system('dark-notify --exit')
  mode = trim6(mode)
  apply_mode(mode)
end

function set_mode(mode)
  mode = trim6(mode)
  if not (mode == "light" or mode == "dark") then
    error("mode must be either \"light\" or \"dark\"" .. mode)
    return
  end
  apply_mode(mode)
end

function toggle()
  local mode = get_config().current_mode
  if mode == "light" then
    mode = "dark"
  elseif mode == "dark" then
    mode = "light"
  else
    apply_current_mode()
    return
  end
  apply_mode(mode)
end

function init_dark_notify()
  -- Docs on this vim.loop stuff: https://github.com/luvit/luv

  local handle, pid
  local stdout = vim.loop.new_pipe(false)
  local stdin = vim.loop.new_pipe(false)

  local function onexit()
    vim.loop.close(handle, vim.schedule_wrap(function()
      vim.loop.shutdown(stdout)
      vim.loop.shutdown(stdin)
      edit_config(function (conf)
        conf.initialized = false
        conf.pid = nil
        conf.stdin_fd = nil
      end)
    end))
  end

  local function onread(err, chunk)
    assert(not err, err)
    if (chunk) then
      local mode = trim6(chunk)
      if not (mode == "light" or mode == "dark") then
        error("dark-notify output not expected: " .. chunk)
        return
      end
      apply_mode(mode)
    end
  end

  handle, pid = vim.loop.spawn(
    "dark-notify",
    { stdio = {stdin, stdout, nil} },
    vim.schedule_wrap(onexit)
  )

  vim.loop.read_start(stdout, vim.schedule_wrap(onread))

  local stdin_fd = vim.loop.fileno(stdin)

  edit_config(function (conf)
    conf.initialized = true
    conf.pid = pid
    conf.stdin_fd = stdin_fd
  end)

  -- For whatever reason, nvim isn't killing child processes properly on exit
  -- So if you don't do this, you get zombie dark-notify processes hanging about.
  nvim_create_augroups({
    DarkNotifyKillChildProcess = {
      { "VimLeave", "*", "lua require('dark_notify').stop()" },
    }
  })
end

-- For whatever reason, killing the child process doesn't work, at all. So we
-- send it the line "quit\n", and it kills itself.
function stop()
  local conf = get_config()
  if conf.stdin_fd == nil then
    return
  end
  local stdin_pipe = vim.loop.new_pipe(false);
  vim.loop.pipe_open(stdin_pipe, get_config().stdin_fd)
  vim.loop.write(stdin_pipe, "quit\n")
  -- process quits itself, calls onexit
  -- config gets edited from there
end

function run(config)
  if config ~= nil or get_config().schemes == nil then
    config = config or {}
    local lightline_loaders = config.lightline_loaders or {}
    local schemes = config.schemes or {}

    for _, mode in pairs({ "light", "dark" }) do
      if type(schemes[mode]) == "string" then
        schemes[mode] = { colorscheme = schemes[mode] }
      end
    end

    edit_config(function (conf)
      conf.lightline_loaders = lightline_loaders
      conf.schemes = schemes
    end)
  end

  local config = get_config()
  if not config.initialized then
    -- first run on startup, also happens to apply current mode
    init_dark_notify()
  elseif config.current_mode ~= nil then
    -- we have run it before, but we're updating the settings
    -- so don't reset to system, but do apply changed config.
    local mode = config.current_mode
    apply_mode(mode)
  end
end

return {
  run = run,
  update = apply_current_mode,
  set_mode = set_mode,
  toggle = toggle,
  stop = stop,
}

-- init.lua or init.vim in a lua <<EOF
-- require('dark_notify').run({
--  lightline_loaders = {
--    my_colorscheme = "path_to_my_colorscheme's lightline autoload file"
--  },
--  schemes = {
--    dark  = "dark colorscheme name",
--    light = { colorscheme = "light scheme name", background = "optional override, either light or dark" }
--  }
-- })
