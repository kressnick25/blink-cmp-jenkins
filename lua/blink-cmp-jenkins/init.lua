local parser = require("blink-cmp-jenkins.parser")

--- @module 'blink.cmp'
--- @class blink-cmp-jenkins.Souce : blink.cmp.Source
--- @field opts blink-cmp-jenkins.Options
--- @field parsed_methods table
local source = {}

--- @class blink-cmp-jenkins.Options: blink.cmp.PathOpts
--- @field gdsl_path string path to the Jenkins GDSL file
local default_opts = {
	-- gdsl_path = os.getenv("HOME").."/.cache/nvim/jenkins.gdsl"
}

-- `opts` table comes from `sources.providers.your_provider.opts`
-- You may also accept a second argument `config`, to get the full
-- `sources.providers.your_provider` table
function source.new(opts)
	local self = setmetatable({}, { __index = source })
	self.opts = vim.tbl_deep_extend("force", default_opts, opts)

	vim.validate("blink-cmp-jenkins.opts.gdsl_path", self.opts.gdsl_path, { "string" })

	return self
end

-- (Optional) Enable the source in specific contexts only
function source:enabled()
	return vim.bo.filetype == "groovy" or vim.bo.filetype == "jenkinsfile"
end

function source:get_completions(ctx, callback)
	-- ctx (context) contains the current keyword, cursor position, bufnr, etc.

	if self.parsed_methods == nil then
		local buf = vim.fn.bufadd(self.opts.gdsl_path)
		vim.fn.bufload(buf)

		local p = parser:new(self.opts.gdsl_path, buf)
		self.parsed_methods = p:parse()
		vim.api.nvim_buf_delete(buf, { unload = true })
	end

	-- You should never filter items based on the keyword, since blink.cmp will
	-- do this for you
	local items = {}
	for _, def in ipairs(self.parsed_methods) do
		local name = def["name"]
		--- @type lsp.CompletionItem
		local item = {
			-- Label of the item in the UI
			label = name,
			-- (Optional) Item kind, where `Function` and `Method` will receive
			-- auto brackets automatically
			kind = require("blink.cmp.types").CompletionItemKind.Function,

			-- (Optional) Text to fuzzy match against
			filterText = name,
			-- (Optional) Text to use for sorting. You may use a layout like
			-- 'aaaa', 'aaab', 'aaac', ... to control the order of the items
			sortText = name,

			-- Text to be inserted when accepting the item using ONE of:
			--
			-- (Recommended) Control the exact range of text that will be replaced
			-- textEdit = {
			-- 	newText = "item " .. def["name"],
			-- 	range = {
			-- 		-- 0-indexed line and character
			-- 		start = { line = 0, character = 0 },
			-- 		["end"] = { line = 0, character = 0 },
			-- 	},
			-- },
			-- Or get blink.cmp to guess the range to replace for you. Use this only
			-- when inserting *exclusively* alphanumeric characters. Any symbols will
			-- trigger complicated guessing logic in blink.cmp that may not give the
			-- result you're expecting
			-- Note that blink.cmp will use `label` when omitting both `insertText` and `textEdit`
			insertText = name,
			-- May be Snippet or PlainText
			insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,

			-- There are some other fields you may want to explore which are blink.cmp
			-- specific, such as `score_offset` (blink.cmp.CompletionItem)
		}
		table.insert(items, item)
	end

	-- The callback _MUST_ be called at least once. The first time it's called,
	-- blink.cmp will show the results in the completion menu. Subsequent calls
	-- will append the results to the menu to support streaming results.
	callback({
		items = items,
		-- Whether blink.cmp should request items when deleting characters
		-- from the keyword (i.e. "foo|" -> "fo|")
		-- Note that any non-alphanumeric characters will always request
		-- new items (excluding `-` and `_`)
		is_incomplete_backward = false,
		-- Whether blink.cmp should request items when adding characters
		-- to the keyword (i.e. "fo|" -> "foo|")
		-- Note that any non-alphanumeric characters will always request
		-- new items (excluding `-` and `_`)
		is_incomplete_forward = false,
	})

	-- (Optional) Return a function which cancels the request
	-- If you have long running requests, it's essential you support cancellation
	return function() end
end

-- (Optional) Before accepting the item or showing documentation, blink.cmp will call this function
-- so you may avoid calculating expensive fields (i.e. documentation) for only when they're actually needed
function source:resolve(item, callback)
	item = vim.deepcopy(item)

	local i = nil
	for _, def in ipairs(self.parsed_methods) do
		if def["name"] == item["label"] then
			i = def
		end
	end

	if i ~= nil then
		-- Shown in the documentation window (<C-space> when menu open by default)
		item.documentation = {
			kind = "markdown",
			value = "Type: "..i["type"].."\n"..i["doc"],
		}

		-- Additional edits to make to the document, such as for auto-imports
		item.additionalTextEdits = {
			{
				newText = "foo",
				range = {
					start = { line = 0, character = 0 },
					["end"] = { line = 0, character = 0 },
				},
			},
		}
	end

	callback(item)
end

-- Called immediately after applying the item's textEdit/insertText
function source:execute(ctx, item, callback, default_implementation)
	-- By default, your source must handle the execution of the item itself,
	-- but you may use the default implementation at any time
	default_implementation()

	-- The callback _MUST_ be called once
	callback()
end

return source
