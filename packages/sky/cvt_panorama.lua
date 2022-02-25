local ecs   = ...
local world = ecs.world
local w     = world.w

local renderpkg = import_package "ant.render"
local viewidmgr, fbmgr = renderpkg.viewidmgr, renderpkg.fbmgr
local sampler   = renderpkg.sampler

local mathpkg   = import_package "ant.math"
local mc        = mathpkg.constant

local ientity   = ecs.import.interface "ant.render|ientity"
local irq       = ecs.import.interface "ant.render|irenderqueue"
local irender   = ecs.import.interface "ant.render|irender"
local imaterial = ecs.import.interface "ant.asset|imaterial"
local icamera   = ecs.import.interface "ant.camera|icamera"

local cvt_p2cm_viewid = viewidmgr.get "panorama2cubmap"

local cvt_p2cm_sys = ecs.system "cvt_p2cm_system"

local face_queues<const> = {
    "cubemap_face_queue_px",
    "cubemap_face_queue_nx",
    "cubemap_face_queue_py",
    "cubemap_face_queue_ny",
    "cubemap_face_queue_pz",
    "cubemap_face_queue_nz",
}

local function create_face_queue(queuename, cameraref)
    ecs.create_entity{
        policy = {
            "ant.render|render_queue",
            "ant.general|name",
        },
        data = {
            name = queuename,
            [queuename] = true,
            queue_name = queuename,
            render_target = {
                viewid = cvt_p2cm_viewid,
                view_rect = {x=0, y=0, w=1, h=1},
                clear_state = {clear = ""},
                fb_idx = nil,
            },
            primitive_filter = {filter_type = "",},
            visible = false,
            camera_ref = cameraref,
        }
    }
end

w:register {
    name = "cvt_p2cm_drawer"
}

w:register{name="filter_drawer"}

function cvt_p2cm_sys:init()
    local cameraref = icamera.create()
    for _, fn in ipairs(face_queues) do
        create_face_queue(fn, cameraref)
    end
    ecs.create_entity{
        policy = {
            "ant.render|simplerender",
            "ant.general|name",
        },
        data = {
            simplemesh = ientity.simple_fullquad_mesh(),
            material = "/pkg/ant.sky/cvt_p2cm.material",
            scene = {srt={}},
            filter_state = "",
            cvt_p2cm_drawer = true,
            name = "cvt_p2cm_drawer",
        }
    }

    ecs.create_entity{
        policy = {
            "ant.render|simplerender",
            "ant.general|name",
        },
        data = {
            simplemesh = ientity.simple_fullquad_mesh(),
            material = "/pkg/ant.test.ibl/assets/filter_ibl.material",
            scene = {srt={}},
            filter_state = "",
            name = "filter_drawer",
            filter_drawer = true,
        }
    }
end

local cubemap_flags<const> = sampler.sampler_flag {
    MIN="LINEAR",
    MAG="LINEAR",
    MIP="LINEAR",
    U="CLAMP",
    V="CLAMP",
    W="CLAMP",
    RT="RT_ON",
}

local icm = ecs.interface "icubemap_face"

function icm.convert_panorama2cubemap(tex)
    local ti = tex.texinfo
    assert(ti.width==ti.height*2 or ti.width*2==ti.height)
    local size = math.min(ti.width, ti.height) // 2

    local cm_rbidx = fbmgr.create_rb{format="RGBA32F", size=size, layers=1, mipmap=true, flags=cubemap_flags, cubemap=true}

    local drawer = w:singleton("cvt_p2cm_drawer", "render_object:in")
    local ro = drawer.render_object
    ro.worldmat = mc.IDENTITY_MAT
    imaterial.set_property_directly(ro.properties, "s_tex", {stage=0, texture=tex})

    for idx, fn in ipairs(face_queues) do
        local faceidx = idx-1
        local fbidx = fbmgr.create{
            rbidx = cm_rbidx,
            layer = faceidx,
            resolve = "g",
            mip = 0,
            numlayer = 1,
        }
        local q = w:singleton(fn, "render_target:in")
        local rt = q.render_target
        local vr = rt.view_rect
        vr.x, vr.y, vr.w, vr.h = 0, 0, size, size
        rt.viewid = cvt_p2cm_viewid + faceidx
        rt.fb_idx = fbidx
        irq.update_rendertarget(fn, rt)

        imaterial.set_property_directly(ro.properties, "u_param", {faceidx, 0.0, 0.0, 0.0})

        irender.draw(rt.viewid, ro)

        local keep_rbs<const> = true
        fbmgr.destroy(fbidx, keep_rbs)
    end
    return fbmgr.get_rb(cm_rbidx).handle
end

local sample_count<const> = 2048
local cLambertian<const>   = 0
local cGGX       <const>   = 1
local cCharlie   <const>   = 2

local face_size <const>    = 256
--[[
#define u_roughness     u_ibl_params.x
#define u_sampleCount   u_ibl_params.y
#define u_width         u_ibl_params.z
#define u_lodBias       u_ibl_params.w

#define u_distribution  u_ibl_params1.x
#define u_currentFace   u_ibl_params1.y
#define u_isGeneratingLUT u_ibl_params1.z
]]

local ibl_properties = {
    irradiance = {
        u_ibl_params = {0.0, sample_count, face_size, 0.0},
        u_ibl_params1= {cLambertian, 0.0, 0.0, 0.0},
    },
    prefilter = {
        u_ibl_params = {0.0, sample_count, face_size, 0.0},
        u_ibl_params1= {cGGX, 0.0, 0.0, 0.0},
    },
    LUT = {
        u_ibl_params = {0.0, 0.0, 0.0, 0.0},
        u_ibl_params1= {0.0, 0.0, 1.0, 0.0},
    }
}

local build_ibl_viewid = viewidmgr.get "build_ibl"

function icm.filter_ibl(source)
    local irradiance_rbidx = fbmgr.create_rb{format="RGBA32F", size=face_size, layers=1, flags=cubemap_flags, cubemap=true}

    local drawer = w:singleton("filter_drawer", "render_object:in")
    local ro = drawer.render_object
    -- do for irradiance
    local irradiance_properties = ibl_properties.irradiance

    imaterial.set_property(drawer, "s_panorama", source)

    for idx, fn in ipairs(face_queues) do
        local faceidx = idx-1
        local q = w:singleton(fn, "render_target:in")
        local rt = q.render_target
        rt.viewid = build_ibl_viewid+faceidx
        local vr = rt.view_rect
        vr.x, vr.y, vr.w, vr.h = 0, 0, face_size, face_size

        local fbidx = fbmgr.create{
            rbidx = irradiance_rbidx,
            layer = faceidx,
            mip = 0,
            numlayer = 1,
        }
        rt.fb_idx = fbidx
        irq.update_rendertarget(fn, rt)
        local p, p1 = irradiance_properties.u_ibl_params, irradiance_properties.u_ibl_params1
        p1[2] = faceidx
        imaterial.set_property(drawer, "u_ibl_params", p)
        imaterial.set_property(drawer, "u_ibl_params1", p1)
        irender.draw(rt.viewid, ro)

        fbmgr.destroy(fbidx, true)
    end
end