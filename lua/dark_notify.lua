-- http://lua-users.org/wiki/StringTrim
function trim6(s)
   return s:match'^()%s*$' and '' or s:match'^%s*(.*%S)'
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
  local name = sel.name or nil
  local bg = sel.background or mode
  local lltheme = sel.lightline or nil

  vim.api.nvim_command('set background=' .. bg)
  if name ~= nil then
    vim.api.nvim_command('colorscheme ' .. name)
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

  local function onclose()
  end

  local handle, pid
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)
  local stdin = vim.loop.new_pipe(false)

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

  local function onshutdown(err)
    if err == "ECANCELED" then
      return
    end
    vim.loop.close(handle, onclose)
    edit_config(function (conf)
      conf.initialized = false
    end)
  end

  local function onexit()
    edit_config(function (conf)
      conf.initialized = false
    end)
  end

  handle, pid = vim.loop.spawn(
    "dark-notify",
    { stdio = {stdin, stdout, stderr} },
    vim.schedule_wrap(onexit)
  )

  vim.loop.read_start(stdout, vim.schedule_wrap(onread))
  edit_config(function (conf)
    conf.initialized = true
  end)
end

function run(config)
  local lightline_loaders = config.lightline_loaders or {}
  local schemes = config.schemes or {}

  for _, mode in pairs({ "light", "dark" }) do
    if type(schemes[mode]) == "string" then
      schemes[mode] = { name = schemes[mode] }
    end
  end

  edit_config(function (conf)
    conf.lightline_loaders = lightline_loaders
    conf.schemes = schemes
  end)

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
  toggle = toggle
}

-- init.lua or init.vim in a lua <<EOF
-- require('dark_notify').run({
--  lightline_loaders = {
--    my_colorscheme = "path_to_my_colorscheme's lightline autoload file"
--  },
--  schemes {
--    dark  = "dark colorscheme name",
--    light = { name = "light scheme name", background = "optional override, either light or dark" }
--  }
-- })
