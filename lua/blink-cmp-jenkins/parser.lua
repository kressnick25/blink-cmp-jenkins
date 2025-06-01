--- @module 'blink-cmp-jenkins'

-- TODO the GDSL is sorted into steps that require a 'node' context.
-- Is it worth parsing these? Then only show if current suggestion
-- is has a parent TSNode of 'node' type.

--- @class blink-cmp-jenkins.JenkinsParser
--- @field path string
--- @field buf integer
--- @field parser vim.treesitter.LanguageTree
local M = {}

--- @param path string
--- @param buf integer
function M:new(path, buf)
	self.path = path
	self.buf = buf

	if vim.treesitter.language.add("groovy") then
		local p, err = vim.treesitter.get_parser(buf, "groovy", { error = false })
		if p ~= nil then
			self.parser = p
		else
			error("Error loading TreeSitter groovy parser: " .. err)
		end
	else
		error("Unable to load TreeSitter groovy parser. Ensure it is installed: `:TSInstall groovy`")
	end

	return setmetatable({}, { __index = self })
end

--- @param node TSNode
--- @param indent integer
local function traverse_node(node, indent)
	indent = indent or 0
	local indent_str = string.rep("  ", indent)
	-- Print node information
	print(indent_str .. "Node: " .. node:type())
	-- Traverse child nodes
	for child, _ in node:iter_children() do
		traverse_node(child, indent + 1)
	end
end

-- @param s string
-- @return string
local function strip_surround(s)
	local res
	res = s:sub(2, -1)
	res = res:sub(1, res:len() - 1)
	return res
end

-- @param s string
-- @return boolean
local function is_in_quotes(s)
	return s:sub(1, 1) == "'" or s:sub(1, 1) == '"'
end

--- @param node TSNode?
--- @return string
function M:node_text(node)
	if node ~= nil then
		return vim.treesitter.get_node_text(node, self.buf)
	else
		return "nil"
	end
end

--- @param node TSNode
--- @return table
function M:parse_params(node)
	local params = {}
	if node:type() ~= "map" then
		error("parse_params: unexpected node type: " .. node:type())
	end
	for _, key_value_pair_node in ipairs(node:named_children()) do
		local key = self:node_text(key_value_pair_node:named_child(0))
		local val = self:node_text(key_value_pair_node:named_child(1))
		-- strip surrounding quotes
		if is_in_quotes(key) then
			key = strip_surround(key)
		end
		if is_in_quotes(val) then
			val = strip_surround(val)
		end
		params[key] = val
	end
	return params
end

--- @param node TSNode
--- @return string, string
function M:parse_named_parameter_definition(node)
	local name = ""
	local type = ""
	if node:named_child_count() ~= 2 then
		error("Unexpected number of named_children (!2)")
	end
	for _, key_value_pair_node in ipairs(node:named_children()) do
		local val = key_value_pair_node:named_child(1)
		local val_text = strip_surround(self:node_text(val))
		if name == "" then
			name = val_text
		else
			type = val_text
		end
	end
	return name, type
end

--- @param node TSNode
--- @return table a list of (name, type) pairs
function M:parse_named_params(node)
	local params = {}
	if node:type() ~= "list" then
		error("parse_named_params: expected node:type to be list, got: " .. node:type())
	end
	for _, key_value_pair_node in ipairs(node:named_children()) do
		-- named_child[0] == 'parameter'
		local definition = key_value_pair_node:named_child(1) -- (name: 'foo', type: 'bar')
		if definition ~= nil then
			local name, type = self:parse_named_parameter_definition(definition)
			params[name] = type
		end
	end
	return params
end

--- @param arguments TSNode
--- @return table - parsed argument definitions <name:value>
function M:parse_args(arguments)
	local result = {}
	for arg in arguments:iter_children() do
		local key_node = arg:child(0)
		local val_node = arg:child(2)
		if key_node ~= nil then
			local key = vim.treesitter.get_node_text(key_node, self.buf)
			if val_node ~= nil then
				-- type string|table
				local val = nil
				if key == "params" then
					val = self:parse_params(val_node)
				elseif key == "namedParams" then
					val = self:parse_named_params(val_node)
				else
					val = strip_surround(vim.treesitter.get_node_text(val_node, self.buf))
				end
				result[key] = val
			end
		end
	end
	return result
end

--- @return table - list of method definitions
function M:parse()
	local all_definitions = {}
	local tree = self.parser:parse(true)[1]
	local root = tree:root()
	print("Root node type: " .. root:type())
	local has_children = false
	local count = 0
	for _ in root:iter_children() do
		has_children = true
		count = count + 1
	end

	if not has_children then
		error("Unable to parse file '" .. self.path .. "', no children")
	end

	-- get all function calls with function name == "method"
	-- TODO refine, this is picking up 'method' as well as 'method()' (want 2nd not first)
	local method_query = vim.treesitter.query.parse(
		"groovy",
		[[
        ;query
        (function_call function: ((identifier) @method_name (#eq? @method_name "method"))) @m
    ]]
	)

	local i = 1
	for _id, node, _metdata in method_query:iter_captures(root, self.buf) do
		if node:type() == "function_call" then
			local argument_list = node:child(1)
			local def = {}
			if argument_list ~= nil then
				def = self:parse_args(argument_list)
				all_definitions[i] = def
				i = i + 1
			end
		end
	end

	return all_definitions
end

-- The function call "enclosingCall" that is inside an if statement
-- ((function_call) @f
-- (#contains? @f "enclosingCall")
--  (#has-ancestor? @f if_statement)) 
--
-- All methods inside an enclosingCall if_statement
-- ((function_call function: ((identifier) @method_name (#eq? @method_name "method"))) @m
-- (#has-ancestor? @m if_statement))
--
-- The whole if_statement that contains exactly one "enclosingCall"
-- (if_statement condition: (parenthesized_expression (function_call function: ((identifier) @m (#eq? @m "enclosingCall"))))) @c
-- The whole if_statement that contains exactly one or more "enclosingCall"
-- (if_statement condition: ((parenthesized_expression) @p (#contains? @p "enclosingCall"))) @d

return M
