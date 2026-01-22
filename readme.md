add virtual lines above the first line for comfortable scrolling and recentering

<img width="1920" height="1053" alt="20260122-152932-589587749" src="https://github.com/user-attachments/assets/d5ca4fed-ac3f-4e3a-a7ba-69f6823d070e" />

fork of https://github.com/nullromo/go-up.nvim

# rationale

the [original plugin](https://github.com/nullromo/go-up.nvim) explains the rationale

for me, i want to make scrolling and recentering more comfortable

## scroll

i want scrolling to be orthogonal to the cursor, but since the cursor must stay on screen, scrolling often moves it

https://github.com/neovim/neovim/issues/989

before the off-screen cursor is implemented, i at least want the cursor position to remain unchanged after symmetric scrolling

that is, after pressing `<c-d>` and then `<c-u>`, the cursor should stay at its original **buffer** position, but this is not how the built-in behavior works

https://vi.stackexchange.com/questions/6005/scroll-without-changing-the-cursor-position

this plugin provides a function so that after scroll(n) followed by scroll(-n), the cursor always returns to its original **buffer** location

## recenter

i want to freely recenter the cursor at any window position

a common complaint is that `zz` cannot center the current line at the start of the buffer.

https://github.com/neovim/neovim/issues/26366

https://github.com/neovim/neovim/issues/25392

this plugin provides a recenter function that can place the current line at any position in the window

## limitation

these issues should ideally be solved at the c level, this is only a hack

https://github.com/neovim/neovim/issues/16166#issuecomment-1134656673

i hope vim can natively support virtual lines above the first line, instead of simulating them with extmarks as this plugin does

# example config

```lua
-- # option

vim.o.smoothscroll = true
vim.o.scrolloff = 0
vim.o.splitkeep = "topline"

-- due to limitations of this plugin, these options must be set

-- # setup

require("go-up").setup()

-- # keymap

local height = function(ratio)
	return ratio * vim.api.nvim_win_get_height(0)
end
local scroll = require("go-up").scroll
local recenter = require("go-up").recenter
local setwinline = require("go-up").setwinline

vim.keymap.set({"n", "x"}, "<c-d>", function() scroll(height(0.5)) end)
vim.keymap.set({"n", "x"}, "<c-u>", function() scroll(-height(0.5)) end)
vim.keymap.set({"n", "x"}, "<c-f>", function() scroll(height(1)) end)
vim.keymap.set({"n", "x"}, "<c-b>", function() scroll(-height(1)) end)
-- additionally:
vim.keymap.set({"n", "x"}, "<c-s>", function() scroll(height(0.25)) end)
vim.keymap.set({"n", "x"}, "<c-g>", function() scroll(-height(0.25)) end)

vim.keymap.set({"n", "x"}, "zt", function() recenter(height(0)) end)
vim.keymap.set({"n", "x"}, "zz", function() recenter(height(0.5)) end)
vim.keymap.set({"n", "x"}, "zb", function() recenter(height(1)) end)
-- additionally:
vim.keymap.set({"n", "x"}, "zh", function() recenter(height(0.25)) end)
vim.keymap.set({"n", "x"}, "zl", function() recenter(height(0.75)) end)

vim.keymap.set({"n", "x"}, "H", function() setwinline(height(0)) end)
vim.keymap.set({"n", "x"}, "M", function() setwinline(height(0.5)) end)
vim.keymap.set({"n", "x"}, "L", function() setwinline(height(1)) end)
-- additionally:
vim.keymap.set({"n", "x"}, "K", function() setwinline(height(0.25)) end)
vim.keymap.set({"n", "x"}, "J", function() setwinline(height(0.75)) end)
```
