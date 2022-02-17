local initargs = ...

local ltask     = require "ltask"
local inputmgr  = import_package "ant.inputmgr"
local ecs       = import_package "ant.ecs"
local rhwi      = import_package "ant.hwi"
local cr        = import_package "ant.compile_resource"
local setting	= import_package "ant.settings".setting

local bgfx      = require "bgfx"
local ServiceBgfxMain = ltask.queryservice "ant.render|bgfx_main"
for _, name in ipairs(ltask.call(ServiceBgfxMain, "APIS")) do
	bgfx[name] = function (...)
		return ltask.call(ServiceBgfxMain, name, ...)
	end
end

local ServiceWindow = ltask.queryservice "ant.window|window"
ltask.send(ServiceWindow, "subscribe", "init", "exit")
ltask.send(ServiceWindow, "subscribe", "mouse_wheel", "mouse", "touch", "keyboard", "char", "size")
local resizeQueue = {}

local S = {}

local config = {
	ecs = initargs
}
local world
local encoderBegin = false
local quit

local function Render()
	while true do
		world:pipeline_update()
		bgfx.encoder_end()
		encoderBegin = false
		do
			--local _ <close> = world:cpu_stat "bgfx.frame"
			rhwi.frame()
		end
		world:pipeline_update_end()
		if quit then
			ltask.wakeup(quit)
			return
		end
		bgfx.encoder_begin()
		encoderBegin = true
		ltask.sleep(0)
	end
end

local function check_load_framebuffer_size(w, h)
	local fbw, fbh = setting:get "graphic/framebuffer/w", setting:get "graphic/framebuffer/h"
	if fbw and fbh then
		return fbw, fbh
	else
		local ratio = setting:get "graphic/framebuffer/ratio"
		if ratio then
			return math.floor(w * ratio + 0.5),
			math.floor(h * ratio + 0.5)
		end
	end
	return w, h
end

local function calc_viewport(fbw, fbh)
	return {
		x=0, y=0, w=fbw, h=fbh
	}
end

function S.init(nwh, context, width, height)
	local fbw, fbh = check_load_framebuffer_size(width, height)
	log.info("framebuffer size:", fbw, fbh)
	rhwi.init {
		nwh = nwh,
		context = context,
		width = fbw,
		height = fbh,
	}
	cr.init()
	bgfx.set_debug "T"
	bgfx.encoder_create()
	bgfx.encoder_init()
	import_package "ant.render".init_bgfx()
	bgfx.encoder_begin()
	encoderBegin = true
	config.fbw, config.fbh = fbw, fbh
	config.viewport = calc_viewport(fbw, fbh)
	world = ecs.new_world(config)
	local ev = inputmgr.create(world, "win32")
	S.mouse_wheel = ev.mouse_wheel
	S.mouse = ev.mouse
	S.touch = ev.touch
	S.keyboard = ev.keyboard
	S.char = ev.char
	S.size = function (w, h)
		ev.size(w, h)
		world:pub{"view_resize", w, h}
	end
	for _, size in ipairs(resizeQueue) do
		S.size(size[1], size[2])
	end

	world:pub {"viewsize", width, height}
	world:pipeline_init()

	ltask.fork(Render)
end

S.mouse_wheel = function () end
S.mouse = function () end
S.touch = function () end
S.keyboard = function () end
S.char = function () end
S.size = function (w,h)
	resizeQueue[#resizeQueue+1] = {w,h}
end
function S.exit()
	quit = {}
	ltask.wait(quit)
	if world then
		world:pipeline_exit()
        world = nil
	end
	if encoderBegin then
		bgfx.encoder_end()
	end
	bgfx.encoder_destroy()
	ltask.send(ServiceWindow, "unsubscribe_all")
	rhwi.shutdown()
    print "exit"
end

S.message = function(...)
	world:pub {"task-message", ...}
end

return S
