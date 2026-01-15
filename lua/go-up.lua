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
	extmark_id = {
		-- buffer_handle_1 = id_1,
		-- buffer_handle_2 = id_2,
		-- ...
	},
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

M.create_extmark = function(buffer_handle, n)
	if buffer_handle == 0 then buffer_handle = vim.api.nvim_get_current_buf() end

	M.cache.extmark_id[buffer_handle] =
		vim.api.nvim_buf_set_extmark(
			buffer_handle,
			M.cache.extmark_ns_id,
			0,
			0,
			{
				right_gravity = false, -- https://github.com/echasnovski/mini.nvim/issues/1642
				virt_lines =
					(
						function()
							local lines = {}
							local line = {{"", "NonText"}}
							for _ = 1, n do
								table.insert(lines, line)
							end
							return lines
						end
					)(),
				virt_lines_above = true,
			}
		)
end

M.del_extmark = function(buffer_handle)
	if buffer_handle == 0 then buffer_handle = vim.api.nvim_get_current_buf() end

	if M.cache.extmark_id[buffer_handle] ~= nil then
		vim.api.nvim_buf_del_extmark(
			buffer_handle,
			M.cache.extmark_ns_id,
			M.cache.extmark_id[buffer_handle]
		)
	end

	M.cache.extmark_id[buffer_handle] = nil
end

M.extmark_is_valid = function(buffer_handle, n)
	if buffer_handle == 0 then buffer_handle = vim.api.nvim_get_current_buf() end

	if M.cache.extmark_id[buffer_handle] == nil then
		return false
	end

	local extmark_info =
		vim.api.nvim_buf_get_extmark_by_id(
			buffer_handle,
			M.cache.extmark_ns_id,
			M.cache.extmark_id[buffer_handle],
			{
				details = true,
			}
		)

	if extmark_info[1] ~= 0 then
		return false
	end

	if n ~= #extmark_info[3].virt_lines then
		return false
	end

	return true
end

M.update_extmark = function(buffer_handle, n)
	if buffer_handle == 0 then buffer_handle = vim.api.nvim_get_current_buf() end

	if
		M.extmark_is_valid(buffer_handle, n)
	then
		return
	end

	M.del_extmark(buffer_handle)
	M.create_extmark(buffer_handle, n)
end

M.create_autocmd = function()
	vim.api.nvim_create_autocmd(
		{
			"BufEnter",
			-- "TextChanged",
			-- "TextChangedI",
		},
		{
			group = M.cache.augroup,
			callback = function()
				M.update_extmark(0, vim.o.lines)
			end,
		}
	)
end

M.toggle_autocmd = function()
	if
		vim.tbl_isempty(
			vim.api.nvim_get_autocmds({group = M.cache.augroup})
		)
	then
		M.create_autocmd()
		vim.api.nvim_exec_autocmds("BufEnter", {group = M.cache.augroup})
	else
		vim.api.nvim_clear_autocmds({group = M.cache.augroup})
		for buffer_handle, _ in pairs(M.cache.extmark_id) do
			M.del_extmark(buffer_handle)
		end
	end
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
	local should_fix = false
	if n > 0 then
		local _, invisible_space = M.scroll_count_ctrld_space()
		if invisible_space <= 0 then
		-- in this situation, <c-d> only moves the cursor and does not scroll
			should_fix = true
		end
	end

	M.scroll_du(n)
	if should_fix then M.scroll_ey(n) end
end

M.scroll = function(n)
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

M.recenter = function(winscreenrow_target)
	winscreenrow_target = math.floor(winscreenrow_target)
	winscreenrow_target = math.max(1, winscreenrow_target)
	winscreenrow_target = math.min(vim.fn.winheight(0), winscreenrow_target)
	local winscreenrow_current = vim.fn.winline()
	M.scroll_ey(-(winscreenrow_target - winscreenrow_current))
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
