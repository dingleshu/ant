local luaecs = import_package "ant.luaecs"
local assetmgr = import_package "ant.asset"
local serialize = import_package "ant.serialize"
local ltask = require "ltask"
local bgfx = require "bgfx"
local fastio = require "fastio"
local policy = require "policy"
local typeclass = require "typeclass"
local system = require "system"
local event = require "event"

local world_metatable = {}
local world = {}
world_metatable.__index = world

local function create_entity_by_data(w, group, data)
    local queue = w._create_entity_queue
    local eid = w.w:new {
        debug = {
            traceback = debug.traceback(),
        }
    }
    local initargs = {
        eid = eid,
        group = group or 0,
        data = data,
    }
    queue[#queue+1] = initargs
    return eid
end

local function create_entity_by_template(w, group, name, template)
    local queue = w._create_entity_queue
    local eid = w.w:new {
        debug = {
            prefab = name,
            traceback = debug.traceback(),
        }
    }
    local initargs = {
        eid = eid,
        group = group or 0,
        template = template,
    }
    queue[#queue+1] = initargs
    return eid, initargs
end

function world:create_entity(v, group)
    local policy_info = policy.create(self, v.policy)
    local data = v.data
    for c, def in pairs(policy_info.component_opt) do
        if data[c] == nil then
            data[c] = def
        end
    end
    for _, c in ipairs(policy_info.component) do
        local d = data[c]
        if d == nil then
            error(("component `%s` must exists"):format(c))
        end
    end
    return create_entity_by_data(self, group or 0, data)
end

function world:remove_entity(e)
    local w = self
    w.w:remove(e)
end

local function table_append(t, a)
	table.move(a, 1, #a, #t+1, t)
end
local table_insert = table.insert

local function create_instance(w, group, prefab, data)
    local entities = {}
    local mounts = {}
    local noparent = {}
    for i = 1, #data do
        local v = data[i]
        local np
        if v.prefab then
            entities[i], np = create_instance(w, group, v.prefab, v.template)
        else
            local e, initargs = create_entity_by_template(w, group, prefab, v.template)
            entities[i], np = e, initargs
        end
        if v.mount then
            assert(
                math.type(v.mount) == "integer"
                and v.mount >= 1
                and v.mount <= #data
                and not data[v.mount].prefab
            )
            assert(v.mount < i)
            mounts[i] = np
        else
            if v.prefab then
                table_append(noparent, np)
            else
                table_insert(noparent, np)
            end
        end
    end
    for i = 1, #data do
        local v = data[i]
        if v.mount then
            if v.prefab then
                for _, m in ipairs(mounts[i]) do
                    m.parent = entities[v.mount]
                end
            else
                mounts[i].parent = entities[v.mount]
            end
        end
    end
    return entities, noparent
end

local template_mt = {}

function template_mt:__gc()
    local destruct = self._world._destruct
    local template = self.template
    destruct[#destruct+1] = function (world)
        world.w:template_destruct(template)
    end
end

local function create_entity_template(w, v)
    local res = policy.create(w, v.policy)
    local data = v.data
    for c, def in pairs(res.component_opt) do
        if data[c] == nil then
            data[c] = def
        end
    end
    for _, c in ipairs(res.component) do
        local d = data[c]
        if d == nil then
            error(("component `%s` must exists"):format(c))
        end
    end

    return setmetatable({
        _world = w,
        mount = v.mount,
        template = w.w:template(data),
        tag = v.tag,
    }, template_mt)
end

local create_template

local function create_template_(w, t)
	local prefab = {}
	for _, v in ipairs(t) do
        if not w.__EDITOR__ and v.editor then
            if v.prefab then
                v = {
                    prefab = "/pkg/ant.ecs/dummy.prefab"
                }
            else
                --TODO
                v = {
                    policy = {},
                    data = {},
                }
            end
        end
        if v.prefab then
            prefab[#prefab+1] = {
                prefab = v.prefab,
                mount = v.mount,
                template = create_template(w, v.prefab),
            }
        else
            prefab[#prefab+1] = create_entity_template(w, v)
        end
    end
    return prefab
end

function create_template(w, filename)
    local v = w._templates[filename]
    if not v then
        local realpath = assetmgr.compile(filename)
        local data = fastio.readall(realpath, filename)
        local t = serialize.parse(filename, data)
        v = create_template_(w, t)
        w._templates[filename] = v
    end
    return v
end

local function add_tag(dict, tag, eid)
	if dict[tag] then
		table.insert(dict[tag], eid)
	else
		dict[tag] = {eid}
	end
end

local function each_prefab(entities, template, f)
    for i, e in ipairs(template) do
        if e.prefab then
            each_prefab(entities[i], e.prefab, f)
        else
            f(entities[i], e.tag)
        end
    end
end

function world:_prefab_instance(instance, args)
    local w = self
    local template = create_template(w, args.prefab)
    local prefab, noparent = create_instance(w, args.group, args.prefab, template)
    for _, m in ipairs(noparent) do
        m.parent = args.parent
    end
    local tags = instance.tag
    each_prefab(prefab, template, function (e, tag)
        if tag then
            if type(tag) == "table" then
                for _, tag_ in ipairs(tag) do
                    add_tag(tags, tag_, e)
                end
            else
                add_tag(tags, tag, e)
            end
        end
        table.insert(tags['*'], e)
    end)
end

function world:create_instance(args)
    local w = self
    args.group = args.group or 0
    local instance = {
        group = args.group,
        tag = {['*']={}}
    }
    local q = self._create_prefab_queue
    q[#q+1] = {
        instance = instance,
        args = args,
    }
    local on_ready = args.on_ready
    local on_message = args.on_message
    local proxy_entity = {}
    if on_ready then
        function proxy_entity.on_ready()
            on_ready(instance)
        end
    end
    if on_message then
        function proxy_entity.on_message(_, ...)
            on_message(instance, ...)
        end
    end
    if next(proxy_entity) then
        instance.proxy = create_entity_by_data(w, args.group, proxy_entity)
    end
    return instance
end

function world:remove_instance(instance)
    assert(instance.tag)
    world:pub {"RemoveInstance1", instance}
end

function world:reset_prefab_cache(filename)
    self._templates[filename] = nil
end

function world:group_enable_tag(tag, id)
    local w = self
    local t = w._group_tags[tag]
    if not t then
        t = {
            args = {},
        }
        w._group_tags[tag] = t
    end
    if t[id] then
        return
    end
    t.dirty = true
    t[id] = true
    table.insert(t.args, id)
end

function world:group_disable_tag(tag, id)
    local w = self
    local t = w._group_tags[tag]
    if not t then
        return
    end
    if t[id] == nil then
        return
    end
    t.dirty = true
    t[id] = nil
    for i = 1, #t.args do
        local v = t.args[i]
        if v == id then
            table.remove(t.args, i)
            break
        end
    end
end

function world:group_flush(tag)
    local w = self
    local group_tags = w._group_tags
    local t = group_tags[tag]
    if not t.dirty then
        return
    end
    t.dirty = nil
    if #t.args == 0 then
        w.w:group_enable(tag)
        group_tags[tag] = nil
    else
        w.w:group_enable(tag, table.unpack(t.args))
    end
end

local function update_cpu_stat(w, funcs, symbols)
	local ecs_world = w._ecs_world
	local get_time = ltask.counter
	local MaxFrame <const> = 30
	local MaxText <const> = math.min(10, #funcs)
	local MaxName <const> = 48
	local CurFrame = 0
	local dbg_print = bgfx.dbg_text_print
	local printtext = {}
	local stat = {}
	for i = 1, #funcs do
		stat[i] = 0
	end
	for i = 1, MaxText do
		printtext[i] = ""
	end
	return function()
		for i = 1, #funcs do
			local f = funcs[i]
			local now = get_time()
			f(ecs_world)
			stat[i] = stat[i] + (get_time() - now)
		end
		if CurFrame ~= MaxFrame then
			CurFrame = CurFrame + 1
		else
			CurFrame = 1
			local t = {}
			for i = 1, #funcs do
				t[i] = {stat[i], i}
				stat[i] = 0
			end
			table.sort(t, function (a, b)
				return a[1] > b[1]
			end)
			for i = 1, MaxText do
				local m = t[i]
				local v, idx = m[1], m[2]
				local name = symbols[idx]
				printtext[i] = name .. (" "):rep(MaxName-#name) .. (" | %.02fms   "):format(v / MaxFrame * 1000)
			end
		end
		dbg_print(0, 2, 0x02, "--- system")
		for i = 1, MaxText do
			dbg_print(2, 2+i, 0x02, printtext[i])
		end
	end
end

function world:pipeline_func(what)
	local w = self
	local funcs, symbols = system.lists(w, what)
	if not funcs or #funcs == 0 then
		return function() end
	end
	local CPU_STAT <const> = true
	if what == "_init" or what == "_update" then
		if CPU_STAT then
			return update_cpu_stat(w, funcs, symbols)
		end
	end
	local ecs_world = w._ecs_world
	return function()
		for i = 1, #funcs do
			local f = funcs[i]
			f(ecs_world)
		end
	end
end

function world:pipeline_init()
	self.pipeline_entity_init = self:pipeline_func "_entity_init"
	self.pipeline_entity_remove = self:pipeline_func "_entity_remove"
	self.pipeline_update = self:pipeline_func "_update"
	self:pipeline_func "_init" ()
end

function world:pipeline_exit()
	self:pipeline_func "exit" ()
end

function world:clibs(name)
    local w = self
    local loaded = w._clibs_loaded
    if loaded[name] then
        return loaded[name]
    end
    local initfunc = assert(package.preload[name])
    local funcs = initfunc()
    loaded[name] = funcs
    if not w._initializing then
        for _, f in pairs(funcs) do
            debug.setupvalue(f, 1, w._ecs_world)
        end
    end
    return funcs
end

local submit = setmetatable({}, {__mode="k", __index = function (t, w)
    local mt = {}
    function mt:__close()
        w:submit(self)
    end
    t[w] = mt
    return mt
end})

function world:entity(eid, pattern)
    local v = self.w:fetch(eid, pattern)
    if v then
        return setmetatable(v, submit[self.w])
    end
end

function world:entity_message(eid, ...)
    self:pub {"EntityMessage", eid, ...}
end

function world:instance_message(instance, ...)
    self:pub {"EntityMessage", instance.proxy, ...}
end

event.init(world)

local m = {}

function m.new_world(config)
	do
		local cfg = config.ecs
        if cfg then
            cfg.pipeline = {
                "_init", "_update", "exit"
            }
            cfg.import = cfg.import or {}
            table.insert(cfg.import, "@ant.ecs")
            cfg.system = cfg.system or {}
            table.insert(cfg.system, "ant.ecs|entity_system")
            table.insert(cfg.system, "ant.ecs|prefab_system")
            table.insert(cfg.system, "ant.ecs|debug_system")
        end
	end
    if config.DEBUG then
        luaecs.check_select(true)
    end
    local ecs = luaecs.world()
	local w; w = setmetatable({
		args = config,
		_ecs = {},
		_group_tags = {},
		_create_entity_queue = {},
		_create_prefab_queue = {},
		_destruct = {},
		_clibs_loaded = {},
		_templates = {},
		w = ecs,
	}, world_metatable)

	-- load systems and components from modules
	typeclass.init(w, config)
	system.solve(w)

    for _, funcs in pairs(w._clibs_loaded) do
        for _, f in pairs(funcs) do
            debug.setupvalue(f, 1, w._ecs_world)
        end
    end
    return w
end

return m
