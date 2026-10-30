use sdl2::{
    controller::GameController,
    joystick::Joystick,
    pixels::Color,
    render::{Canvas, Texture},
    video::Window,
};
use std::ffi::{CStr, c_uint};

pub struct Platform {
    pub sdl: sdl2::Sdl,
    pub canvas: Canvas<Window>,
    pub joysticks: Vec<Joystick>,
    pub controllers: Vec<GameController>,
}

impl Platform {
    pub fn open(fullscreen: bool, vsync: bool) -> Result<Self, String> {
        // Both are enforced again using observed values. Hints alone can fall back.
        unsafe {
            std::env::set_var("SDL_VIDEODRIVER", "wayland");
        }
        sdl2::hint::set("SDL_RENDER_DRIVER", "opengles2");
        sdl2::hint::set("SDL_RENDER_SCALE_QUALITY", "0");
        sdl2::hint::set("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1");
        let sdl = sdl2::init()?;
        let video = sdl.video()?;
        let version = sdl2::version::version();
        println!(
            "RUST_PLATFORM requested_video=wayland requested_renderer=opengles2 audio=disabled SDL={version} actual_video={}",
            video.current_video_driver()
        );
        if video.current_video_driver() != "wayland" {
            return Err("native Wayland required".into());
        }
        let mut builder =
            video.window("Eggshell throwaway platform smoke (not gameplay)", 640, 480);
        builder.resizable().position_centered();
        if fullscreen {
            builder.fullscreen_desktop();
        }
        let window = builder.build().map_err(|e| e.to_string())?;
        let driver = sdl2::render::drivers()
            .position(|d| d.name == "opengles2")
            .ok_or("opengles2 SDL renderer missing")?;
        let mut builder = window.into_canvas().index(driver as u32).accelerated();
        if vsync {
            builder = builder.present_vsync();
        }
        let mut canvas = builder.build().map_err(|e| e.to_string())?;
        let info = canvas.info();
        println!(
            "RUST_RENDERER name={} flags={} texture_limit={}x{} vsync_requested={vsync}",
            info.name, info.flags, info.max_texture_width, info.max_texture_height
        );
        if info.name != "opengles2" || info.flags & 2 == 0 || info.flags & 1 != 0 {
            return Err("unexpected or software SDL renderer".into());
        }
        canvas.set_draw_color(Color::RGB(0, 8, 48));
        canvas.clear();
        // Make SDL submit its pending work so its own GL context is current.
        if unsafe { sdl2::sys::SDL_RenderFlush(canvas.raw()) } != 0 {
            return Err(sdl2::get_error());
        }
        if unsafe { sdl2::sys::SDL_GL_GetCurrentContext() }.is_null() {
            return Err("SDL renderer has no current GLES context".into());
        }
        let vendor = gl_string(&video, 0x1F00)?;
        let renderer = gl_string(&video, 0x1F01)?;
        let version = gl_string(&video, 0x1F02)?;
        let lower = format!("{vendor} {renderer} {version}").to_lowercase();
        println!("RUST_GPU vendor={vendor:?} renderer={renderer:?} version={version:?}");
        if !version.contains("OpenGL ES")
            || [
                "llvmpipe",
                "softpipe",
                "swrast",
                "software",
                "swiftshader",
                "lavapipe",
                "virgl",
                "angle",
                "zink",
            ]
            .iter()
            .any(|x| lower.contains(x))
            || !(lower.contains("mali") || lower.contains("panfrost"))
        {
            return Err("Pro hardware GLES identity gate failed (requires Mali/Panfrost, no translation/software)".into());
        }
        let drawable = canvas.output_size()?;
        println!(
            "RUST_FRAMEBUFFER width={} height={} window={:?}",
            drawable.0,
            drawable.1,
            canvas.window().size()
        );
        let joystick = sdl.joystick()?;
        let gamecontroller = sdl.game_controller()?;
        let count = joystick.num_joysticks()?;
        println!("RUST_INPUT_ENUM count={count}");
        let mut joysticks = Vec::new();
        let mut controllers = Vec::new();
        for index in 0..count {
            let joy = joystick.open(index).map_err(|e| e.to_string())?;
            println!(
                "RUST_INPUT index={index} name={:?} guid={} instance={} axes={} buttons={} hats={} controller={}",
                joy.name(),
                joy.guid(),
                joy.instance_id(),
                joy.num_axes(),
                joy.num_buttons(),
                joy.num_hats(),
                gamecontroller.is_game_controller(index)
            );
            if gamecontroller.is_game_controller(index) {
                let controller = gamecontroller.open(index).map_err(|e| e.to_string())?;
                println!("RUST_CONTROLLER mapping={:?}", controller.mapping());
                controllers.push(controller);
            }
            joysticks.push(joy);
        }
        if count == 0 {
            return Err("no built-in joystick enumerated; input acceptance blocked".into());
        }
        Ok(Self {
            sdl,
            canvas,
            joysticks,
            controllers,
        })
    }
    pub fn upload<'a>(
        creator: &'a sdl2::render::TextureCreator<sdl2::video::WindowContext>,
        image: &crate::pack::Image,
    ) -> Result<Texture<'a>, String> {
        let mut texture = creator
            .create_texture_static(
                sdl2::pixels::PixelFormatEnum::RGBA32,
                image.width,
                image.height,
            )
            .map_err(|e| e.to_string())?;
        texture.set_blend_mode(sdl2::render::BlendMode::Blend);
        texture.set_scale_mode(sdl2::render::ScaleMode::Nearest);
        texture
            .update(None, &image.rgba, image.width as usize * 4)
            .map_err(|e| e.to_string())?;
        Ok(texture)
    }
}
fn gl_string(video: &sdl2::VideoSubsystem, name: c_uint) -> Result<String, String> {
    let address = video.gl_get_proc_address("glGetString");
    if address.is_null() {
        return Err("glGetString unavailable".into());
    }
    // SDL owns the current GLES context. This function has the GLES ABI signature.
    let function: unsafe extern "C" fn(c_uint) -> *const u8 =
        unsafe { std::mem::transmute(address) };
    let value = unsafe { function(name) };
    if value.is_null() {
        return Err("glGetString returned NULL".into());
    }
    Ok(unsafe { CStr::from_ptr(value.cast()) }
        .to_string_lossy()
        .into_owned())
}
