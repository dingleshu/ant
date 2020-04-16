local ecs = ...
local world = ecs.world

local viewidmgr = require "viewid_mgr"
local fbmgr = require "framebuffer_mgr"

local cu = require "camera.util"

local assetmgr = import_package "ant.asset"

local setting = require "setting"

local tm_sys = ecs.system "tonemapping_system"
tm_sys.require_singleton "postprocess"
tm_sys.require_system    "postprocess_system"
tm_sys.require_interface "postprocess"

local ipp = world:interface "postprocess"

function tm_sys:post_init()
    local sd = setting.get()
    local hdrsetting = sd.graphic.hdr
    local pp = world:singleton "postprocess"
    if hdrsetting.enable then
        local main_fbidx = fbmgr.get_fb_idx(viewidmgr.get "main_view")

        local fbsize = ipp.main_rb_size(main_fbidx)
        cu.main_queue_camera()
        local techniques = pp.techniques
        techniques[#techniques+1]
            {
                name = "tonemapping",
                passes = {
                    {
                        name = "main",
                        material = assetmgr.load "/pkg/ant.resources/materials/postprocess/tonemapping.material",
                        output = {
                            fb_idx = main_fbidx,
                            rb_idx = 1,
                        },
                        viewport = {
                            rect = {x=0, y=0, w=fbsize.w, h=fbsize.h},
                            clear_state = {clear=""},
                        }
                    },
                }
            }
    end
end