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
      local command = table.concat(vim.iter({'autocmd', def}):flatten():totable() , ' ')
      vim.api.nvim_command(command)
    end
    vim.api.nvim_command('augroup END')
  end
end



local state = {
  initialized = false,
  pid = -1,
  stdin_handle = nil,
  config = {},
}

local M = {}

local function ensure_config()
  if state.config == nil then
    state.config = {}
  end
end

local function get_config()
  ensure_config()
  return state.config
end

local function edit_config(fn)
  ensure_config()
  fn(state.config)
end

local function apply_mode(mode)
  local config = get_config()
  local sel = config.schemes[mode] or {}
  local colorscheme = sel.colorscheme or nil
  local bg = sel.background or mode
  local lltheme = sel.lightline or nil

  if config.before ~= nil then
    config.before(mode)
  end

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

  if config.after ~= nil then
    config.after(mode)
  end


  state.current_mode = mode
end

function M.update()
  local mode = vim.fn.system('dark-notify --exit')
  mode = trim6(mode)
  apply_mode(mode)
end

function M.set_mode(mode)
  mode = trim6(mode)
  if not (mode == "light" or mode == "dark") then
    error("mode must be either \"light\" or \"dark\"" .. mode)
    return
  end
  apply_mode(mode)
end

function M.toggle()
  local mode = state.current_mode
  if mode == "light" then
    mode = "dark"
  elseif mode == "dark" then
    mode = "light"
  else
    M.update()
    return
  end
  apply_mode(mode)
end

local function init_dark_notify()
  -- Docs on this vim.loop stuff: https://github.com/luvit/luv

  local handle, pid
  local stdout = vim.loop.new_pipe(false)
  local stdin = vim.loop.new_pipe(false)

  local function onexit()
    vim.loop.close(handle, vim.schedule_wrap(function()
      vim.loop.shutdown(stdout)
      vim.loop.shutdown(stdin)
      state.initialized = false
      state.pid = nil
      state.stdin_handle = nil
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

  state.initialized = true
  state.pid = pid
  state.stdin_handle = stdin

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
function M.stop()
  if state.stdin_handle == nil then
    return
  end
  vim.loop.write(state.stdin_handle, "quit\n")
  -- process quits itself, calls onexit
  -- config gets edited from there
end

function M.configure(config)
  if config == nil then
    return
  end
  local lightline_loaders = config.lightline_loaders or {}
  local schemes = config.schemes or {}
  local before = config.before
  local after = config.after

  for _, mode in pairs({ "light", "dark" }) do
    if type(schemes[mode]) == "string" then
      schemes[mode] = { colorscheme = schemes[mode] }
    end
  end

  edit_config(function (conf)
    conf.lightline_loaders = lightline_loaders
    conf.schemes = schemes
    conf.before = before
    conf.after = after
  end)
end

function M.run(config)
  if config ~= nil or get_config().schemes == nil then
    -- if it's nil, it's a first run, so configure with no options.
    config = config or {}
    M.configure(config)
  end

  local config = get_config()
  if not config.initialized then
    -- first run on startup, also happens to apply current mode
    init_dark_notify()
  elseif state.current_mode ~= nil then
    -- we have run it before, but we're updating the settings
    -- so don't reset to system, but do apply changed config.
    local mode = state.current_mode
    apply_mode(mode)
  end
end

return M

-- init.lua or init.vim in a lua <<EOF
-- require('dark_notify').run({
--  lightline_loaders = {
--    my_colorscheme = "path_to_my_colorscheme's lightline autoload file"
--  },
--  schemes = {
--    dark  = "dark colorscheme name",
--    light = { colorscheme = "light scheme name", background = "optional override, either light or dark" }
--  },
--  onchange = function(mode)
--  end,
-- })
