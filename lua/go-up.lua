local M = {}
local H = {}

-- # config & setup

M.config = {
}

M.setup = function(config)
	M.config = vim.tbl_deep_extend("force", M.config, config or {})
	M.create_autocmd()
end

-- # cache

M.cache = {
	extmark_ns_id = vim.api.nvim_create_namespace("go-up"),
	augroup = vim.api.nvim_create_augroup("go-up", {clear = true}),
}

-- # function: virtual lines

-- -- prototype
-- vim.api.nvim_buf_set_extmark(
-- 	0,
-- 	vim.api.nvim_create_namespace("test"),
-- 	0,
-- 	0,
-- 	{
-- 		right_gravity = false,
-- 		virt_lines = {{{"", "NonText"}}, {{"", "NonText"}}, {{"", "NonText"}}},
-- 		virt_lines_above = true,
-- 	}
-- )

M.buf_set_extmark = function(buf, n_lines)
	local eob = vim.opt.fillchars:get().eob or "~"
	local hl = "EndOfBuffer"
	local line = {{eob, hl}}
	local lines = {}
	for _ = 1, n_lines do
		table.insert(lines, line)
	end

	vim.api.nvim_buf_set_extmark(
		buf,
		M.cache.extmark_ns_id,
		0,
		0,
		{
			right_gravity = false, -- https://github.com/nvim-mini/mini.nvim/issues/1642
			virt_lines = lines,
			virt_lines_above = true,
		}
	)
end

M.buf_get_extmark = function(buf)
	local extmarks = vim.api.nvim_buf_get_extmarks(
		buf,
		M.cache.extmark_ns_id,
		{0, 0},
		{0, 0},
		{details = true}
	)
	if vim.tbl_isempty(extmarks) then
		return nil
	else
		assert(#extmarks == 1)
		return extmarks[1]
	end
end

M.buf_del_extmark = function(buf)
	local extmark = M.buf_get_extmark(buf)
	if extmark == nil then return end

	local id = extmark[1]
	vim.api.nvim_buf_del_extmark(buf, M.cache.extmark_ns_id, id)
end

M.buf_is_extmark_valid = function(buf, n_lines)
	local extmark = M.buf_get_extmark(buf)
	if extmark == nil then return false end
	if #extmark[4].virt_lines ~= n_lines then return false end
	return true
end

M.buf_ensure_extmark = function(buf, n_lines)
	if M.buf_is_extmark_valid(buf, n_lines) then
		-- do nothing
	else
		M.buf_del_extmark(buf)
		M.buf_set_extmark(buf, n_lines)
	end
end

M.create_autocmd = function()
	vim.api.nvim_create_autocmd(
		{
			"BufEnter",
			"VimResized",
		},
		{
			group = M.cache.augroup,
			callback = function()
				M.buf_ensure_extmark(0, vim.o.lines)
-- vim needs to keep the cursor visible,
-- so the maximum number of virt_lines that can be shown is the window height minus one,
-- the exact number does not matter
-- we could use M.buf_ensure_extmark(0, 999) here,
-- but vim.o.lines feels more elegant
			end,
		}
	)
end

-- # function: scroll

--[[
vim does not provide a function for scrolling
it can scroll only in two ways

1. <c-e> and <c-y>
the cursor trys to stay at buffer position

2. <c-d> and <c-u>
the cursor trys to stay at window position
--]]

M.scroll_ey = function(n)
	assert(vim.wo.smoothscroll == true) -- can't set and restore, don't know why
	if n == 0 then
		return
	elseif n > 0 then
		vim.cmd("normal!" .. n .. vim.keycode("<c-e>"))
	elseif n < 0 then
		n = -n
		vim.cmd("normal!" .. n .. vim.keycode("<c-y>"))
	end
end

M.scroll_du = function(n)
	assert(vim.wo.smoothscroll == true) -- can't set and restore, don't know why
	if n == 0 then
		return
	elseif n > 0 then
		vim.cmd("normal!" .. n .. vim.keycode("<c-d>"))
	elseif n < 0 then
		n = -n
		vim.cmd("normal!" .. n .. vim.keycode("<c-u>"))
	end
end

--[[
what i want to achieve is symmetrical scrolling
which means that after scroll(n) and scroll(-n), the cursor should not move
scroll_du is very close, but it fails at the beginning/end of the buffer
we need to modify it slightly
--]]

M.scroll_count_ctrld_space = function()
	local pos11_cursor = require("virtcol").get_cursor()
	local pos00 = {
		pos11_cursor.lnum - 1,
		pos11_cursor.virtcol - 1,
	}
	local height_info = vim.api.nvim_win_text_height(
		0,
		{
			start_row = pos00[1],
			start_vcol = pos00[2] + 1, -- exclusive
		}
	)
	local height = height_info.all
	local space = height - 1
	local invisible_space = space - (vim.api.nvim_win_get_height(0) - vim.fn.winline())
	return space, invisible_space
end

M.scroll_count_ctrlu_space = function()
	local pos11_cursor = require("virtcol").get_cursor()
	local pos00 = {
		pos11_cursor.lnum - 1,
		pos11_cursor.virtcol - 1,
	}
	local height_info = vim.api.nvim_win_text_height(
		0,
		{
			end_row = pos00[1],
			end_vcol = pos00[2] + 1, -- exclusive
		}
	)
	local height_info_sob = vim.api.nvim_win_text_height(0, {end_row = 0, end_vcol = 0})
	local height = height_info.all - height_info_sob.all
	local space = height - 1
	local invisible_space = space - (vim.fn.winline() - 1)
	return space, invisible_space
end

M.scroll_du_fix = function(n)
-- at the end of the buffer, <c-d> scrolls until the last line becomes visible
-- after that, it only moves the cursor and no longer scrolls
-- we therefore calculate the owed space and use <c-e> to compensate
	local owed_space = 0
	if n > 0 then
		local _, invisible_space = M.scroll_count_ctrld_space()
		invisible_space = math.max(0, invisible_space)
		owed_space = math.max(0, n - invisible_space)
	end

	M.scroll_du(n)
	M.scroll_ey(owed_space)
end

M.scroll = function(n)
	n = math.modf(n)
	if n == 0 then
		return
	elseif n > 0 then
		local space, invisible_space = M.scroll_count_ctrld_space()
		if math.abs(n) <= space then
			M.scroll_du_fix(n)
		else
			M.scroll_ey(0 + invisible_space)
		end
	elseif n < 0 then
		local space, invisible_space = M.scroll_count_ctrlu_space()
		if math.abs(n) <= space then
			M.scroll_du_fix(n)
		else
			M.scroll_ey(0 - invisible_space)
		end
	end
end

-- # function: recenter

M.normalize_winline = function(winline)
	winline = math.floor(winline)
	winline = math.max(1, winline)
	winline = math.min(vim.api.nvim_win_get_height(0), winline)
	return winline
end

M.recenter = function(winline_target)
	winline_target = M.normalize_winline(winline_target)
	local winline_current = vim.fn.winline()
	local winline_delta = winline_target - winline_current
	M.scroll_ey(-winline_delta)
end

-- # function: setwinline

M.cursor_gjgk = function(n)
	if n == 0 then
		return
	elseif n > 0 then
		vim.cmd("normal!" .. n .. "gj")
	elseif n < 0 then
		n = -n
		vim.cmd("normal!" .. n .. "gk")
	end
end

M.setwinline = function(winline_target)
	winline_target = M.normalize_winline(winline_target)
	local winline_current = vim.fn.winline()
	local winline_delta = winline_target - winline_current
	M.cursor_gjgk(winline_delta)
end

-- # used before

--[[

M.winscreenrow = function(winid, lnum, col)
	local screenrow = vim.fn.screenpos(winid, lnum, col).row

	if screenrow == 0 then return 0 end
	-- screenrow == 0 means invisible

	local screenrow_win_first_line_with_border = vim.fn.win_screenpos(winid)[1]
	local screenrow_win_first_line
	local win_config = vim.api.nvim_win_get_config(winid)
	if
		win_config.relative ~= "" -- floating window
		and
		win_config.border ~= "none" -- has border
		and
		win_config.border[2] ~= "" -- border has top char
	then
		screenrow_win_first_line = screenrow_win_first_line_with_border + 1
	else
		screenrow_win_first_line = screenrow_win_first_line_with_border
	end
	local winscreenrow = screenrow - (screenrow_win_first_line - 1)
	return winscreenrow
end

M.count_blank_top = function()
	local winscreenrow_buf_first_line = M.winscreenrow(0, 1, 1)
	local winscreenrow_win_first_line = 1

	if winscreenrow_buf_first_line == 0 then
		return 0
	else
		return winscreenrow_buf_first_line - winscreenrow_win_first_line
	end
end

M.count_blank_bot = function()
	local lnum = vim.fn.line("$")
	local col = vim.fn.col({lnum, "$"})

	local winscreenrow_buf_last_line = M.winscreenrow(0, lnum, col)
	local winscreenrow_win_last_line = vim.api.nvim_win_get_height(0)

	if winscreenrow_buf_last_line == 0 then
		return 0
	else
		return -(winscreenrow_buf_last_line - winscreenrow_win_last_line)
	end
end

M.align_top = function()
	M.adjust_view(M.count_blank_top())
end

M.align_bot = function()
	M.adjust_view(-M.count_blank_bot())
end

M.scroll_dry_run_count_blank = function(n)
	if n == 0 then
		return 0
	elseif n > 0 then
		local view = vim.fn.winsaveview()
		M.scroll_ey(n)
		local blank = M.count_blank_bot()
		vim.fn.winrestview(view)
		return blank
	elseif n < 0 then
		local view = vim.fn.winsaveview()
		M.scroll_ey(n)
		local blank = M.count_blank_top()
		vim.fn.winrestview(view)
		return blank
	end
end

--]]

-- # return

return M
