local log = log and log(...) or print

require "iupluacontrols"

local iupcontrols   = import_package "ant.iupcontrols"
local editor = import_package "ant.editor"
local math = import_package "ant.math"
local ms = math.stack
local su = import_package "ant.serialize"
local factory = require "entity_value_controller_factory"

local entity_property_builder = {}

function entity_property_builder.build_primtype_component(parent_tbl,com_name,component_data,schema,alias_name)
    local com_schema = schema[com_name]
    local typ = com_schema.type
    local function modify_function(value)
        parent_tbl[alias_name] = value
        return true -- if return nil, modify will be ignored
    end
    local builder = factory[com_name]
    local value = component_data
    if com_schema.method and com_schema.method.save then
        value = com_schema.method.save(value)
    end
    local value_ctrl = builder(alias_name,value,modify_function)
    
    return value_ctrl
end

function entity_property_builder.build_alias_component(parent_tbl,com_name,component_data,schema,alias_name)
    local com_schema = schema[com_name]
    local map_com_type = com_schema.type
    return entity_property_builder.build_component(parent_tbl,map_com_type,component_data,schema,alias_name)
end

function entity_property_builder.build_array_component(parent_tbl,com_name,component_data,schema,alias_name)
    local com_schema = schema[com_name]
    local map_com_type = com_schema.type
    local array_param = com_schema.array
    local vbox_ctrl = iup.vbox {
        iup.label { title = tostring(alias_name) }
    }
    for index,data in ipairs(component_data) do
        local child_ctrl = entity_property_builder.build_component(component_data,com_name,data,schema,index)
        iup.Append(vbox_ctrl,child_ctrl)
    end
    return vbox_ctrl
end

function entity_property_builder.build_com_component(parent_tbl,com_name,component_data,schema,alias_name)
    local container = iup.vbox {
        POSITION = "15,0",
    }
    local expander = iup.expander {
        iup.backgroundbox {
            container,
            POSITION = "15,0",
        },
        title = tostring(alias_name),
    }
    local com_schema = schema[com_name]
    local count = 0
    for _,sub_schema in ipairs(com_schema) do
        local sub_data = component_data[sub_schema.name]
        if component_data[sub_schema.name] then
            local child_ctrl = nil
            if not sub_schema.type then
                child_ctrl = entity_property_builder.build_com_component(component_data,sub_schema.type,sub_data,schema,sub_schema.name)
            elseif sub_schema.array then -- has type & array
                child_ctrl = entity_property_builder.build_array_component(component_data,sub_schema.type,sub_data,schema,sub_schema.name)
            elseif  entity_property_builder.is_direct(sub_schema.type)  then
                child_ctrl = entity_property_builder.build_primtype_component(component_data,sub_schema.type,sub_data,schema,sub_schema.name)
            else -- has type & not array
                child_ctrl = entity_property_builder.build_component(component_data,sub_schema.type,sub_data,schema,sub_schema.name)
            end
            iup.Append(container,child_ctrl)
            count = count + 1
        end
    end
    if count == 0 then
        iup.Append(container,iup.label {title = "[Empty]"})
    end
    return expander
end

function entity_property_builder.build_component(parent_tbl,com_name,component_data,schema,alias_name)
    local com_schema = schema[com_name]
    local controller = nil
    if not com_schema then
        return iup.label({title=com_name})
    end
    if not com_schema.type then
        controller = entity_property_builder.build_com_component(parent_tbl,com_name,component_data,schema,alias_name)
    elseif com_schema.array then -- has type & array
        controller = entity_property_builder.build_array_component(parent_tbl,com_name,component_data,schema,alias_name)
    elseif entity_property_builder.is_direct(com_name) then
        controller = entity_property_builder.build_primtype_component(parent_tbl,com_name,component_data,schema,alias_name)
    else -- has type & not array
        controller = entity_property_builder.build_alias_component(parent_tbl,com_name,component_data,schema,alias_name)
    end
    return controller
end

function entity_property_builder.is_direct(type)
    return factory[type]
end

--container:iup container
--entity:...
--schema:world._schema
function entity_property_builder.build_enity(container,entity,schema)
    for com_name,component_data in pairs( entity ) do
        local iup_item = entity_property_builder.build_component(entity,com_name,component_data,schema,com_name)
        iup.Append(container,iup_item)
    end
    iup.Append(container,iup.fill {})

end

return entity_property_builder