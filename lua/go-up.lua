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
				right_gravity = false, -- https://github.com/echasnovski/mini.nvim/issues/1642
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

M.toggle = function()
	if
		next(
			vim.api.nvim_get_autocmds({group = M.cache.augroup})
		) == nil
	then
		vim.api.nvim_exec_autocmds("BufEnter", {group = M.cache.augroup})
		M.create_autocmd()
	else
		vim.api.nvim_clear_autocmds({group = M.cache.augroup})
		for buffer_handle, _ in pairs(M.cache.extmark_id) do
			M.del_extmark(buffer_handle)
		end
	end
end

-- # function: adjust_view

M.adjust_view = function(n)
	vim.o.smoothscroll = true
	-- can't set and restore, don't know why

	if n == 0 then
		return
	elseif n > 0 then
		vim.cmd("normal!" .. n .. "")
		-- HACK: invisible char here, ascii 5
	elseif n < 0 then
		n = -n
		vim.cmd("normal!" .. n .. "")
		-- HACK: invisible char here, ascii 25
	end
end

-- # function: recenter

M.recenter = function(winscreenrow_target)
	winscreenrow_target = math.floor(winscreenrow_target)
	winscreenrow_target = math.max(1, winscreenrow_target)
	winscreenrow_target = math.min(vim.fn.winheight(0), winscreenrow_target)
	local winscreenrow_current = vim.fn.winline()
	M.adjust_view(-(winscreenrow_target - winscreenrow_current))
end

-- # function: align

M.winscreenrow = function(winid, lnum, col)
	local screenrow = vim.fn.screenpos(winid, lnum, col).row

	if screenrow == 0 then return 0 end
	-- screenrow == 0 means invisible

	local screenrow_win_first_line_with_border = vim.fn.win_screenpos(winid)[1]
	local screenrow_win_first_line
	local win_config = vim.api.nvim_win_get_config(winid)
	if
		win_config.relative ~= ""
		-- floating window
		and
		(
			win_config.border ~= "none"
			-- has border
			and
			win_config.border[2] ~= ""
			-- border has top char
		)
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

M.count_blank_bottom = function()
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

M.align_bottom = function()
	M.adjust_view(-M.count_blank_bottom())
end

M.align = function()
	local blank_top = M.count_blank_top()
	local blank_bottom = M.count_blank_bottom()

	if blank_top ~= 0 then
		M.align_top()
	else
		M.align_bottom()
	end
end

-- # function: scroll

M.scroll__is_cursor_follow0 = function(n)
	vim.o.smoothscroll = true
	if n == 0 then
		return
	elseif n > 0 then
		vim.cmd("normal!" .. n .. "")
	elseif n < 0 then
		n = -n
		vim.cmd("normal!" .. n .. "")
	end
end

M.scroll__is_cursor_follow1 = function(n)
	vim.o.smoothscroll = true
	if n == 0 then
		return
	elseif n > 0 then
		if M.count_blank_bottom() == 0 then
			local view = vim.fn.winsaveview()
			M.scroll__is_cursor_follow0(n)
			local blank_bottom = M.count_blank_bottom()
			vim.fn.winrestview(view)

			vim.cmd("normal!" .. n .. "")
			M.scroll__is_cursor_follow0(blank_bottom)
		else
			vim.cmd("normal!" .. n .. "")
			M.scroll__is_cursor_follow0(n)
		end
	elseif n < 0 then
		n = -n
		vim.cmd("normal!" .. n .. "")
	end
end

M.scroll = function(n, is_cursor_follow)
	n = math.floor(n)
	if is_cursor_follow then
		M.scroll__is_cursor_follow1(n)
	else
		M.scroll__is_cursor_follow0(n)
	end
end

-- # return

return M
