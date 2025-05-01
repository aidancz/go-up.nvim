local M = {}
local H = {}

-- # config & setup

M.config = {
}

M.setup = function(config)
	M.config = vim.tbl_deep_extend("force", M.config, config or {})
	M.set_option()
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

M.extmark_is_valid = function(buffer_handle, n)
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

M.update_extmark = function(buffer_handle, n, force)
	if
		force == false
		and
		M.extmark_is_valid(buffer_handle, n)
	then
		return
	end

	if M.cache.extmark_id[buffer_handle] ~= nil then
		vim.api.nvim_buf_del_extmark(
			buffer_handle,
			M.cache.extmark_ns_id,
			M.cache.extmark_id[buffer_handle]
		)
	end

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

M.create_autocmd = function()
	vim.api.nvim_create_autocmd(
		{
			"BufEnter",
			"TextChanged",
			"TextChangedI",
		},
		{
			group = M.cache.augroup,
			callback = function()
				M.update_extmark(vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_height(0)-1)
			end,
		}
	)
end

-- # function: recenter

M.set_option = function()
	vim.opt.smoothscroll = true
end

M.scroll = function(n)
	if n == 0 then
		return
	elseif n > 0 then
		vim.cmd("normal!" .. n .. "")
		-- HACK: invisible char here, ascii 5
	elseif n < 0 then
		vim.cmd("normal!" .. -n .. "")
		-- HACK: invisible char here, ascii 25
	end
end

M.new_zz = function()
	local winscreenrow_target = math.floor(vim.api.nvim_win_get_height(0) / 2)
	local winscreenrow_current = vim.fn.winline()
	M.scroll(-(winscreenrow_target - winscreenrow_current))
end

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
			win_config.border ~= nil
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
	M.scroll(M.count_blank_top())
end

M.align_bottom = function()
	M.scroll(-M.count_blank_bottom())
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

M.redraw = function()
-- HACK: https://github.com/nullromo/go-up.nvim/issues/9
	M.update_extmark(vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_height(0)-1, true)
end

-- # return

return M
