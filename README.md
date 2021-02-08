# dark-notify

It's a program for watching when macOS switches to dark mode. Useful for making 
your text editor switch to a dark theme. Includes a Neovim (Lua) plugin to do 
exactly that.

![Demo gif](demo.gif)

## Install

```sh
brew install cormacrelf/tap/dark-notify
```

## Neovim usage

Requires neovim 0.4.4 or later.

Add a plugin with your favourite plugin manager:

```vim
Plug 'cormacrelf/dark-notify'
```

Then add to your `init.vim`:

```
:lua <<EOF
require('dark_notify').run()
EOF
```

By default, this will just execute `:set bg=dark` or `:set bg=light` as soon as 
the system appearance changes.

### Additional options

```lua
local dn = require('dark_notify')

-- Configure
dn.run({
    schemes = {
      -- you can use a different colorscheme for each
      dark  = "dark colorscheme name",
      -- even a different `set background=light/dark` setting or lightline theme
      -- if you use lightline, you may want to configure lightline themes,
      -- even if they're the same one, especially if the theme reacts to :set bg
      light = {
        colorscheme = "light scheme name",
        background = "override to either light or dark",
        lightline = "set your lightline theme name here"
      }
    },
    lightline_loaders = {
        -- It's tricky to get lightline to update a colorscheme for `set bg=dark`.
        -- Add a line here to reload the config for your lightline theme.
        my_ll_theme_name = "path to a lightline autoload file",
        -- example
        github = (vim.g.plug_home .. "/vim-colors-github/autoload/lightline/colorscheme/github.vim")
    },
    onchange = function(mode)
        -- optional, you can configure your own things to react to changes.
        -- this is called at startup and every time dark mode is switched,
        -- either via the OS, or because you manually set/toggled the mode.
        -- mode is either "light" or "dark"
    end,
})

-- Draw the blinds for now
dn.set_mode("dark")

-- Swap to whatever it isn't currently
dn.toggle()

-- Match the system
dn.update()

-- Stop reacting to changes
dn.stop()

-- Start reacting again, with previous settings
dn.run()
```

You can put those in mappings if you want.

```vim
nmap <f5> :lua require('dark_notify').toggle()<cr>
```

### What if I just want the toggle functionality / am not on macOS?

Use the configure function instead.

```vim
:lua <<EOF
require('dark_notify').configure({
    -- same options as run({ ... })
})
EOF
```

## Command line usage

```sh
$ dark-notify
light
# then System Preferences > General, switch back and forth
dark
light
dark
# ... ctrl-C to quit.
```

You can also run another command whenever it changes:

```sh
$ dark-notify -c 'echo something'
something light
something dark
$ dark-notify -c 'python3 my-script.py'
```

`dark-notify -h` for more options.

