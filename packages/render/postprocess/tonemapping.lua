local ecs   = ...
local world = ecs.world
local w     = world.w

local mathpkg   = import_package "ant.math"
local mu        = mathpkg.util

local viewidmgr = require "viewid_mgr"
local fbmgr     = require "framebuffer_mgr"
local sampler   = require "sampler"

local tm_sys    = ecs.system "tonemapping_system"
local ientity   = world:interface "ant.render|entity"
local irender   = world:interface "ant.render|irender"
local irq       = world:interface "ant.render|irenderqueue"
local icamera   = world:interface "ant.camera|camera"
local imaterial = world:interface "ant.asset|imaterial"

local tm_viewid<const> = viewidmgr.get "tonemapping"

function tm_sys:init()
    world:create_entity{
        policy = {
            "ant.general|name",
            "ant.render|simplerender",
            "ant.scene|render_object",
            "ant.scene|scene_object",
        },
        data = {
            name = "tonemapping_render_obj",
            simplemesh = ientity.quad_mesh(),
            material = "/pkg/ant.resources/materials/postprocess/tonemapping.material",
            scene = {
                srt = mu.srt_obj(),
            },
            eid = world:register_entity(),
            render_object   = {},
            filter_material = {},
            state = 0,
            render_object_update = true,
            INIT = true,
            tonemapping = true,
        }
    }
end


local rt_flags<const> = sampler.sampler_flag {
    RT="RT_ON",
    MIN="LINEAR",
    MAG="LINEAR",
    U="CLAMP",
    V="CLAMP",
}

function tm_sys:init_world()
    local vr = irq.view_rect "main_queue"
    world:create_entity {
        policy = {
            "ant.render|postprocess_queue",
            "ant.render|watch_screen_buffer",
            "ant.general|name",
        },
        data = {
            render_target = {
                viewid     = tm_viewid,
                view_rect   = {x=vr.x, y=vr.y, w=vr.w, h=vr.h},
                fb_idx      = fbmgr.create{
                    fbmgr.create_rb{
                        format = "RGBA8",
                        w  = vr.w,
                        h = vr.h,
                        layers = 1,
                        flags = rt_flags,
                    }
                },
                view_mode = "",
                clear_state = {
                    clear = "",
                },
            },
            watch_screen_buffer = true,
            name = "tonemapping_rt_obj",
        }
    }
end

local pp_input0 = {
    stage = 0,
    texture={handle=nil},
}

function tm_sys:tonemapping()
    local tm = w:singleton("tonemapping", "render_object:in")
    local ro = tm.render_object

    local pp = w:singleton("postprocess", "postprocess_input:in")
    local ppi = pp.postprocess_input
    pp_input0.texture.handle = assert(ppi[1].handle)
    imaterial.set_property_directly(ro.properties, "s_postprocess_input0", pp_input0)
    irender.draw(tm_viewid, ro)

    local rb = fbmgr.get_rb(fbmgr.get_byviewid(tm_viewid)[1])
    ppi[1].handle = rb.handle
end