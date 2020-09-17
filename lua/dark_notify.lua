function get_config()
  return vim.g.dark_switcher_config or {}
end

-- See https://github.com/neovim/neovim/issues/12544
function edit_config(fn)
  local edit = vim.g.dark_switcher_config or {}
  fn(edit)
  vim.g.dark_switcher_config = edit
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
      local config = get_config()
      local mode
      if chunk == "Light\n" then
        mode = "light"
      elseif chunk == "Dark\n" then
        mode = "dark"
      else
        error("dark-notify output not expected: " .. chunk)
        return
      end
      local sel = config.schemes[mode] or {}
      name = sel.name or nil
      bg = sel.background or mode

      vim.api.nvim_command('set background=' .. bg)
      if name ~= nil then
        vim.api.nvim_command('colorscheme ' .. name)
      end

      -- now try to reload lightline
      name = name or vim.g.colors_name
      local reloader = config.lightline_loaders[name]
      local lightline = vim.call("exists", "g:loaded_lightline")

      if lightline == 1 and reloader ~= nil then
        vim.api.nvim_command("source " .. reloader)
        vim.api.nvim_command("call lightline#colorscheme()")
      end
    else
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

  if not get_config().initialized then
    init_dark_notify()
  end
end

return { run=run }

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
