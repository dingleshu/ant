local log = log and log(...) or print

local treecontrol = require "editor.tree"
local eu = require "editor.util"

local hierarchyview = {}

local tree = treecontrol.new {
	HIDEBUTTONS ="YES",
	HIDELINES   ="YES",	
	IMAGELEAF	="IMGLEAF",
	IMAGEBRANCHCOLLAPSED = "IMGLEAF",
	IMAGEBRANCHEXPANDED = "IMGLEAF"
}

hierarchyview.window = tree

function hierarchyview:build(htree, ud_table)	
	local treeview = self.window
	local function constrouct_treeview(tr, parent)
		local keys = eu.get_sort_keys(tr)

		for _, k in ipairs(keys) do
			local v = tr[k]
			local ktype = type(k)
			if ktype == "string" or ktype == "number" then
				local vtype = type(v)
				local function add_child(parent, name)
					local child = treeview:add_child(parent, name)
					local eid = assert(ud_table[name])
					child.eid = eid					
					return child
				end
				
				if vtype == "table" then
					local child = add_child(parent, k)
					constrouct_treeview(v, child)
				elseif vtype == "string" then
					add_child(parent, v)
				end
			else
				log("not support ktype : ", ktype)
			end
	
		end
	end

	treeview:clear()
	constrouct_treeview(htree, nil)	
	treeview:clear_selections()
end

function hierarchyview:select_nodename()
	return self.window["TITLE"]
end

return hierarchyview