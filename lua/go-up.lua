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
	assert(math.abs(n) <= vim.api.nvim_win_get_height(0)) -- <c-d>/<c-u> cannot scroll more than one window height
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
the desired scroll behavior is:
keep the cursor at the same window position whenever possible
if that is not possible (at the beginning/end of the buffer),
keep the cursor at the same buffer position and only scroll the window

as a result:
the cursor can always return to its original buffer position using scroll(n) and scroll(-n)
while still allowing the entire buffer to be viewed
this works around the lack of an off-screen cursor
--]]

M.scroll_count_ctrld_space = function()
	local pos_cursor = {
		vim.fn.line(".") - 1,
		vim.fn.virtcol(".") - 1,
	}
	local height = vim.api.nvim_win_text_height(
		0,
		{
			start_row = pos_cursor[1],
			start_vcol = pos_cursor[2],
			max_height = (3 * vim.o.lines + 1),
			-- max_height exists for speed, not as a logical constraint
			-- for the result, imposing an upper bound does not affect the outcome
			-- space.all can be replaced by math.min(winheight, space.all)
			-- so we can limit max_height here
			-- i.e.
			-- (all - fill - 1) >= winheight -- `all` beyond this limit may be discarded
			-- all >= (winheight + fill + 1)
			-- all >= (2 * vim.o.lines + 1) -- since ((winheight <= vim.o.lines) and (fill == vim.o.lines))
			-- all >= (3 * vim.o.lines + 1) -- relax the condition to allow other virtual lines
		}
	)
	local all = height.all
	local fill = height.fill
	local text = all - fill

	local space = {}
	space.all = text - 1
	space.visible = vim.api.nvim_win_get_height(0) - vim.fn.winline()
	space.invisible = space.all - space.visible
	return space
end

M.scroll_count_ctrlu_space = function()
	local pos_cursor = {
		vim.fn.line(".") - 1,
		vim.fn.virtcol(".") - 1,
	}
	local height = vim.api.nvim_win_text_height(
		0,
		{
			end_row = pos_cursor[1],
			end_vcol = pos_cursor[2],
			max_height = (3 * vim.o.lines + 1),
			-- max_height exists for speed, not as a logical constraint
			-- for the result, imposing an upper bound does not affect the outcome
			-- space.all can be replaced by math.min(winheight, space.all)
			-- so we can limit max_height here
			-- i.e.
			-- (all - fill - 1) >= winheight -- `all` beyond this limit may be discarded
			-- all >= (winheight + fill + 1)
			-- all >= (2 * vim.o.lines + 1) -- since ((winheight <= vim.o.lines) and (fill == vim.o.lines))
			-- all >= (3 * vim.o.lines + 1) -- relax the condition to allow other virtual lines
		}
	)
	local all = height.all
	if pos_cursor[2] == 0 then all = all + 1 end -- since end_vcol is exclusive
	local fill = height.fill
	local text = all - fill

	local space = {}
	space.all = text - 1
	space.visible = vim.fn.winline() - 1
	space.invisible = space.all - space.visible
	return space
end

M.scroll_du_fix = function(n)
-- at the end of the buffer, <c-d> scrolls until the last line becomes visible
-- after that, it only moves the cursor and no longer scrolls
-- we therefore calculate the owed space and use <c-e> to compensate
	local owed_space = 0
	if n > 0 then
		local space = M.scroll_count_ctrld_space()
		local invisible_space_that_ctrld_can_consume = math.max(0, space.invisible)
		if n > invisible_space_that_ctrld_can_consume then
			owed_space = n - invisible_space_that_ctrld_can_consume
		end
	end

	M.scroll_du(n)
	M.scroll_ey(owed_space)
end

M.scroll = function(n)
	n = math.modf(n)
	if n == 0 then
		return
	elseif n > 0 then
		local space = M.scroll_count_ctrld_space()
		if math.abs(n) <= space.all then
			M.scroll_du_fix(n)
		else
			M.scroll_ey(space.invisible)
		end
	elseif n < 0 then
		local space = M.scroll_count_ctrlu_space()
		if math.abs(n) <= space.all then
			M.scroll_du_fix(n)
		else
			M.scroll_ey(-space.invisible)
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
