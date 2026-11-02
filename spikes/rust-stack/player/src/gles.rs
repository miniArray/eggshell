//! Explicit owned-GLES backend. Never a fallback from SDL_Renderer.
//! SDL2 owns the Wayland window/context; this Rust module owns shaders and draws.
#[path = "gles_lighting.rs"]
mod lighting_backend;
use crate::pack::Image;
use eggshell_spike_core::PaletteSwap;
use glow::HasContext;
use sdl2::video::{GLContext, GLProfile, SwapInterval, Window};

const VERTEX: &str = r#"
attribute vec2 a_position;
attribute vec2 a_uv;
attribute vec4 a_color;
uniform vec2 u_viewport;
varying vec2 v_uv;
varying vec4 v_color;
void main() {
  gl_Position = vec4(a_position.x/u_viewport.x*2.0-1.0, 1.0-a_position.y/u_viewport.y*2.0,0.0,1.0);
  v_uv=a_uv; v_color=a_color;
}
"#;
const FRAGMENT: &str = r#"
precision highp float;
// Godot4.7.2 ShaderGLES3 prefixes highp sampler2D. ESSL's default
// lowp sampler can quantize texels before translucent blending.
uniform highp sampler2D u_texture;
uniform vec3 u_keys[8];
uniform vec3 u_values[8];
uniform int u_count;
uniform int u_darkness;
uniform vec2 u_viewport;
uniform vec2 u_light_origin;
uniform float u_light_radius;
uniform float u_strength;
varying vec2 v_uv;
varying vec4 v_color;
void main() {
  if (u_darkness != 0) {
    vec2 screen_pixel=vec2(gl_FragCoord.x,u_viewport.y-gl_FragCoord.y);
    float distance_from_light=distance(screen_pixel,u_light_origin);
    float shade=smoothstep(0.0,max(u_light_radius,0.001),distance_from_light);
    gl_FragColor=vec4(0.0,0.0,0.0,u_strength*shade);
  } else {
    vec4 pixel=texture2D(u_texture,v_uv);
    for(int i=0;i<8;i++) {
      if(i<u_count && all(lessThan(abs(pixel.rgb-u_keys[i]),vec3(0.5/255.0)))) pixel.rgb=u_values[i];
    }
    gl_FragColor=pixel*v_color;
  }
}
"#;
/// FRAGMENT's non-darkness path with no palette swaps, as its own program: the same
/// texel times vertex colour, without the per-fragment swap loop and branch that every
/// pixel otherwise pays on the Mali-G31 (fill-bound levels with gradients and three
/// background layers missed frames). Game pipeline only.
const PLAIN_FRAGMENT: &str = r#"
precision highp float;
uniform highp sampler2D u_texture;
varying vec2 v_uv;
varying vec4 v_color;
void main() {
  vec4 pixel=texture2D(u_texture,v_uv);
  gl_FragColor=pixel*v_color;
}
"#;
#[derive(Clone, Debug, PartialEq)]
pub struct Quad {
    pub image: usize,
    pub corners: [[f32; 2]; 4],
    /// Normalized UV at each corner. Allows exact Tiled h/v/transpose transforms.
    pub uv: [[f32; 2]; 4],
    pub color: [f32; 4],
    pub palette: Vec<PaletteSwap>,
}
#[derive(Clone, Copy, Debug, Default)]
pub struct DrawCounts {
    pub quads: u64,
    pub batches: u64,
    pub vertices: u64,
}

/// Syntax-only translation. Numeric expressions and operation order stay exact.
fn diagnostic_es300_render_sources() -> (String, String) {
    es300_render_sources(FRAGMENT)
}
fn es300_render_sources(fragment_source: &str) -> (String, String) {
    let vertex = format!(
        "#version 300 es\nprecision highp float;\n{}",
        VERTEX
            .replace("attribute ", "in ")
            .replace("varying ", "out ")
    );
    let fragment = fragment_source
        .replacen(
            "precision highp float;",
            "precision highp float;\nlayout(location=0) out highp vec4 diagnostic_frag_color;",
            1,
        )
        .replace("varying ", "in ")
        .replace("texture2D(", "texture(")
        .replace("gl_FragColor", "diagnostic_frag_color");
    (vertex, format!("#version 300 es\n{fragment}"))
}
/// Godot canvas.glsl uses a CPU-built screen_transform mat4, not vertex division.
/// Preserve our existing upper-left render/readback convention with Y reflection.
/// No UV, texel-center bias, topology, fragment or texture change is part of this axis.
fn game_es300_render_sources() -> (String, String) {
    game_es300_sources_for(FRAGMENT)
}
fn game_es300_sources_for(fragment: &str) -> (String, String) {
    let (v, f) = es300_render_sources(fragment);
    let v=v.replacen("uniform vec2 u_viewport;","uniform vec2 u_viewport;\nuniform mat4 u_screen_transform;",1).replace("gl_Position = vec4(a_position.x/u_viewport.x*2.0-1.0, 1.0-a_position.y/u_viewport.y*2.0,0.0,1.0);","gl_Position = u_screen_transform * vec4(a_position,0.0,1.0);");
    (v, f)
}
fn game_screen_transform(width: u32, height: u32) -> [f32; 16] {
    // rasterizer_canvas_gles3.cpp332..335: translate(-size/2), then scale(2/size).
    // Native target/readback Y is the reflection of Godot's target convention.
    let sx = 2.0_f32 / width as f32;
    let sy = -2.0_f32 / height as f32;
    let tx = -(width as f32 / 2.0) * sx;
    let ty = -(height as f32 / 2.0) * sy;
    [
        sx, 0.0, 0.0, 0.0, 0.0, sy, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, tx, ty, 0.0, 1.0,
    ]
}
// Equivalent to locked Godot4.7.2 MODE_COPY_SECTION + MODE_SIMPLE_COPY,
// with CONVERT_LINEAR_TO_SRGB=false. This is a diagnostic/readback pass only.
const COPY_VERTEX: &str = r#"#version 300 es
precision highp float;
layout(location=0) in vec2 a_position;
out vec2 uv_interp;
uniform highp vec4 copy_section;
void main(){
 uv_interp=a_position*0.5+0.5;
 gl_Position=vec4(a_position,1.0,1.0);
 gl_Position.xy=(copy_section.xy+uv_interp.xy*copy_section.zw)*2.0-1.0;
}
"#;
const COPY_FRAGMENT: &str = r#"#version 300 es
precision highp float;
precision highp sampler2D;
in vec2 uv_interp;
uniform sampler2D source;
layout(location=0) out vec4 frag_color;
void main(){vec2 uv=uv_interp;vec4 color=texture(source,uv);frag_color=color;}
"#;
const COPY_QUAD: [f32; 12] = [
    -1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0,
];
const LEGACY_RECT_ORDER: [usize; 6] = [0, 1, 2, 0, 2, 3];
// Quad corners are TL,TR,BR,BL. Godot canvas.glsl vertex_base is
// TL,BL,BR,TR,TL,BR. Same diagonal/coverage; exact source submission order.
const GODOT_RECT_ORDER: [usize; 6] = [0, 3, 2, 1, 0, 2];
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PipelineConfig {
    LegacyDefault,
    GameOpaqueRgb10,
}
impl PipelineConfig {
    fn rect_order(self) -> [usize; 6] {
        match self {
            Self::LegacyDefault => LEGACY_RECT_ORDER,
            Self::GameOpaqueRgb10 => GODOT_RECT_ORDER,
        }
    }
}
struct GameTarget {
    index: usize,
    size: [u32; 2],
    actual: serde_json::Value,
    window_actual: serde_json::Value,
    source_filters: [i32; 2],
}
struct CopyResources {
    program: glow::Program,
    buffer: glow::Buffer,
    vao: glow::VertexArray,
    source_uniform: Option<glow::UniformLocation>,
    section_uniform: Option<glow::UniformLocation>,
}
struct DiagnosticTarget {
    framebuffer: glow::Framebuffer,
    texture: glow::Texture,
    actual_internal_format: i32,
}
struct PlainProgram {
    program: glow::Program,
    viewport: Option<glow::UniformLocation>,
    screen_transform: Option<glow::UniformLocation>,
}
struct Uniforms {
    viewport: Option<glow::UniformLocation>,
    darkness: Option<glow::UniformLocation>,
    count: Option<glow::UniformLocation>,
    keys: Option<glow::UniformLocation>,
    values: Option<glow::UniformLocation>,
    light_origin: Option<glow::UniformLocation>,
    light_radius: Option<glow::UniformLocation>,
    strength: Option<glow::UniformLocation>,
}
impl Uniforms {
    unsafe fn load(gl: &glow::Context, p: glow::Program) -> Self {
        unsafe {
            Self {
                viewport: gl.get_uniform_location(p, "u_viewport"),
                darkness: gl.get_uniform_location(p, "u_darkness"),
                count: gl.get_uniform_location(p, "u_count"),
                keys: gl.get_uniform_location(p, "u_keys[0]"),
                values: gl.get_uniform_location(p, "u_values[0]"),
                light_origin: gl.get_uniform_location(p, "u_light_origin"),
                light_radius: gl.get_uniform_location(p, "u_light_radius"),
                strength: gl.get_uniform_location(p, "u_strength"),
            }
        }
    }
}
fn same_batch(a: &Quad, b: &Quad, single_texture: bool) -> bool {
    single_texture || (a.image == b.image && a.palette == b.palette)
}
/// Where an uploaded image lives on the GPU. A standalone texture has the
/// identity mapping; an atlas image maps its UVs into a page.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct ImagePlacement {
    texture: usize,
    atlas: Option<AtlasSpot>,
    /// The image's own texture, used for quads that are not texel-safe.
    standalone: usize,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct AtlasSpot {
    offset: [u32; 2],
    extent: [u32; 2],
    page: u32,
}
/// Texture and optional atlas mapping that draw this quad. Quads that are not
/// texel-safe use the image's standalone texture, so they sample exactly as
/// without the atlas.
fn route(placements: &[ImagePlacement], q: &Quad) -> Option<(usize, Option<AtlasSpot>)> {
    let p = placements.get(q.image)?;
    Some(match p.atlas {
        Some(spot) if crate::atlas::texel_safe(&q.corners, &q.uv, spot.extent) => {
            (p.texture, Some(spot))
        }
        _ => (p.standalone, None),
    })
}
pub struct Gles {
    // Keep the context alive until GL resources are deleted in Drop.
    _context: GLContext,
    pub window: Window,
    pub sdl: sdl2::Sdl,
    pub video: sdl2::VideoSubsystem,
    gl: glow::Context,
    lighting: lighting_backend::Resources,
    program: glow::Program,
    uniforms: Uniforms,
    /// PLAIN_FRAGMENT program (game pipeline) with its viewport and screen transform.
    plain: Option<PlainProgram>,
    /// Whether the plain program is the bound one (draw batches switch per palette).
    plain_bound: bool,
    batch_texture: Option<usize>,
    benchmark_single_texture: Option<usize>,
    batch_palette: Option<Vec<PaletteSwap>>,
    screen_transform_uniform: Option<glow::UniformLocation>,
    rect_vertex_order: [usize; 6],
    buffer: glow::Buffer,
    textures: Vec<glow::Texture>,
    placements: Vec<ImagePlacement>,
    atlas_pending: Option<Vec<Image>>,
    atlas_enabled: bool,
    atlas_uv_out_of_range: u64,
    atlas_quads: u64,
    standalone_quads: u64,
    diagnostic_targets: Vec<DiagnosticTarget>,
    diagnostic_copy: Option<CopyResources>,
    game_target: Option<GameTarget>,
    target_allocations: u64,
    last_capture_pipeline: Option<serde_json::Value>,
    normal_copy_draws: u64,
    pub texture_limit: i32,
    width: u32,
    height: u32,
    vertices: Vec<f32>,
}
impl Gles {
    pub fn open(fullscreen: bool, vsync: bool) -> Result<Self, String> {
        Self::open_configured(fullscreen, vsync, PipelineConfig::LegacyDefault)
    }
    pub fn open_game(fullscreen: bool, vsync: bool) -> Result<Self, String> {
        Self::open_configured(fullscreen, vsync, PipelineConfig::GameOpaqueRgb10)
    }
    fn open_configured(
        fullscreen: bool,
        vsync: bool,
        pipeline: PipelineConfig,
    ) -> Result<Self, String> {
        // Spike: EGGSHELL_ALLOW_X11=1 lets the portal's sandboxed launch (Xwayland
        // only, no Wayland socket) draw through X11 with EGL/GLES. Default unchanged.
        let allow_x11 = std::env::var("EGGSHELL_ALLOW_X11").is_ok_and(|v| v == "1");
        let driver = if allow_x11 { "x11" } else { "wayland" };
        unsafe {
            std::env::set_var("SDL_VIDEODRIVER", driver);
            if allow_x11 {
                std::env::set_var("SDL_VIDEO_X11_FORCE_EGL", "1");
            }
        }
        let sdl = sdl2::init()?;
        let video = sdl.video()?;
        if video.current_video_driver() != driver {
            return Err(format!("owned GLES requires {driver}"));
        }
        let attributes = video.gl_attr();
        attributes.set_context_profile(GLProfile::GLES);
        attributes.set_context_version(2, 0);
        attributes.set_double_buffer(true);
        attributes.set_multisample_buffers(0);
        attributes.set_multisample_samples(0);
        attributes.set_framebuffer_srgb_compatible(false);
        attributes.set_depth_size(0);
        attributes.set_stencil_size(0);
        attributes.set_red_size(8);
        attributes.set_green_size(8);
        attributes.set_blue_size(8);
        attributes.set_alpha_size(8);
        attributes.set_buffer_size(32);
        attributes.set_accelerated_visual(true);
        let mut builder = video.window(
            "Eggshell throwaway owned GLES (not yet gameplay-admitted)",
            640,
            480,
        );
        builder.opengl().resizable().position_centered();
        if fullscreen {
            builder.fullscreen_desktop();
        }
        let window = builder.build().map_err(|e| e.to_string())?;
        let context = window.gl_create_context()?;
        window.gl_make_current(&context)?;
        video.gl_set_swap_interval(if vsync {
            SwapInterval::VSync
        } else {
            SwapInterval::Immediate
        })?;
        let gl = unsafe {
            glow::Context::from_loader_function(|s| video.gl_get_proc_address(s) as *const _)
        };
        let (program, buffer, limit) = unsafe {
            let vendor = gl.get_parameter_string(glow::VENDOR);
            let renderer = gl.get_parameter_string(glow::RENDERER);
            let version = gl.get_parameter_string(glow::VERSION);
            println!(
                "RUST_OWNED_GLES actual_video={} SDL={} backend=owned-GLES-not-SDL_Renderer requested_context=GLES2 vendor={vendor:?} renderer={renderer:?} version={version:?} audio=disabled srgb_framebuffer_requested=false msaa=0 vsync_requested={vsync}",
                video.current_video_driver(),
                sdl2::version::version()
            );
            let lower = format!("{vendor} {renderer} {version}").to_lowercase();
            if !version.contains("OpenGL ES")
                || !(lower.contains("mali") || lower.contains("panfrost"))
                || [
                    "software",
                    "llvmpipe",
                    "softpipe",
                    "swiftshader",
                    "lavapipe",
                    "virgl",
                    "swrast",
                    "angle",
                    "zink",
                ]
                .iter()
                .any(|s| lower.contains(s))
            {
                return Err("owned GLES Pro hardware gate failed".into());
            }
            let channels = [
                gl.get_parameter_i32(glow::RED_BITS),
                gl.get_parameter_i32(glow::GREEN_BITS),
                gl.get_parameter_i32(glow::BLUE_BITS),
                gl.get_parameter_i32(glow::ALPHA_BITS),
            ];
            println!("RUST_OWNED_CHANNELS RGBA_bits={channels:?}");
            if channels != [8, 8, 8, 8] {
                return Err("owned GLES requires an observed RGBA8 framebuffer".into());
            }
            let limit = gl.get_parameter_i32(glow::MAX_TEXTURE_SIZE);
            let program = if pipeline == PipelineConfig::GameOpaqueRgb10 {
                let (v, f) = game_es300_render_sources();
                compile_sources(&gl, &v, &f)?
            } else {
                compile(&gl)?
            };
            let buffer = gl.create_buffer()?;
            gl.disable(glow::DEPTH_TEST);
            gl.disable(glow::CULL_FACE);
            gl.disable(glow::DITHER);
            gl.disable(glow::SCISSOR_TEST);
            gl.enable(glow::BLEND);
            gl.blend_func_separate(
                glow::SRC_ALPHA,
                glow::ONE_MINUS_SRC_ALPHA,
                glow::ONE,
                glow::ONE_MINUS_SRC_ALPHA,
            );
            gl.pixel_store_i32(glow::UNPACK_ALIGNMENT, 1);
            gl.pixel_store_i32(glow::PACK_ALIGNMENT, 1);
            gl.use_program(Some(program));
            gl.uniform_1_i32(gl.get_uniform_location(program, "u_texture").as_ref(), 0);
            (program, buffer, limit)
        };
        let (width, height) = window.drawable_size();
        println!(
            "RUST_OWNED_FRAMEBUFFER width={width} height={height} texture_limit={limit} swap_interval={:?}",
            video.gl_get_swap_interval()
        );
        let screen_transform_uniform = if pipeline == PipelineConfig::GameOpaqueRgb10 {
            Some(
                unsafe { gl.get_uniform_location(program, "u_screen_transform") }
                    .ok_or("game screen transform uniform missing")?,
            )
        } else {
            None
        };
        let uniforms = unsafe { Uniforms::load(&gl, program) };
        let plain = if pipeline == PipelineConfig::GameOpaqueRgb10 {
            unsafe {
                let (v, f) = game_es300_sources_for(PLAIN_FRAGMENT);
                let p = compile_sources(&gl, &v, &f)?;
                gl.use_program(Some(p));
                gl.uniform_1_i32(gl.get_uniform_location(p, "u_texture").as_ref(), 0);
                let plain = PlainProgram {
                    program: p,
                    viewport: gl.get_uniform_location(p, "u_viewport"),
                    screen_transform: Some(
                        gl.get_uniform_location(p, "u_screen_transform")
                            .ok_or("plain screen transform uniform missing")?,
                    ),
                };
                gl.use_program(Some(program));
                Some(plain)
            }
        } else {
            None
        };
        let lighting = unsafe {
            lighting_backend::Resources::new(&gl, pipeline == PipelineConfig::GameOpaqueRgb10)?
        };
        let mut result = Self {
            _context: context,
            window,
            sdl,
            video,
            gl,
            lighting,
            program,
            uniforms,
            plain,
            plain_bound: false,
            batch_texture: None,
            benchmark_single_texture: None,
            batch_palette: None,
            screen_transform_uniform,
            rect_vertex_order: pipeline.rect_order(),
            buffer,
            textures: Vec::new(),
            placements: Vec::new(),
            atlas_pending: None,
            atlas_enabled: false,
            atlas_uv_out_of_range: 0,
            atlas_quads: 0,
            standalone_quads: 0,
            diagnostic_targets: Vec::new(),
            diagnostic_copy: None,
            game_target: None,
            target_allocations: 0,
            last_capture_pipeline: None,
            normal_copy_draws: 0,
            texture_limit: limit,
            width,
            height,
            vertices: Vec::with_capacity(6 * 8 * 1024),
        };
        if pipeline == PipelineConfig::GameOpaqueRgb10 {
            result.prepare_copy_resources()?;
            result.allocate_game_target()?;
        }
        Ok(result)
    }
    fn delete_last_target(&mut self, index: usize) -> Result<(), String> {
        if index + 1 != self.diagnostic_targets.len() {
            return Err("owned target release order violated".into());
        }
        let target = self
            .diagnostic_targets
            .pop()
            .ok_or("missing owned target")?;
        unsafe {
            self.gl.delete_framebuffer(target.framebuffer);
            self.gl.delete_texture(target.texture);
        }
        Ok(())
    }
    fn allocate_game_target(&mut self) -> Result<(), String> {
        if let Some(old) = self.game_target.take() {
            self.delete_last_target(old.index)?;
        }
        self.bind_diagnostic_target(None)?;
        let window_actual = self.framebuffer_info()?;
        let index = self.create_diagnostic_unorm_target(true)?;
        self.bind_diagnostic_target(Some(index))?;
        let actual = self.framebuffer_info()?;
        let source_filters = unsafe {
            [
                self.gl
                    .get_tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MIN_FILTER),
                self.gl
                    .get_tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MAG_FILTER),
            ]
        };
        if source_filters != [glow::NEAREST as i32; 2] {
            return Err("game render source must actually use NEAREST".into());
        }
        if self.diagnostic_target_internal_format(index)? != glow::RGB10_A2 as i32
            || actual["attachment_rgba_bits"] != serde_json::json!([10, 10, 10, 2])
        {
            return Err("game pipeline requires observed RGB10_A2 attachment".into());
        }
        unsafe {
            if let Some(plain) = &self.plain {
                self.gl.use_program(Some(plain.program));
                self.gl.uniform_matrix_4_f32_slice(
                    plain.screen_transform.as_ref(),
                    false,
                    &game_screen_transform(self.width, self.height),
                );
            }
            self.gl.use_program(Some(self.program));
            self.plain_bound = false;
            self.gl.uniform_matrix_4_f32_slice(
                self.screen_transform_uniform.as_ref(),
                false,
                &game_screen_transform(self.width, self.height),
            );
        }
        self.game_target = Some(GameTarget {
            index,
            size: [self.width, self.height],
            actual,
            window_actual,
            source_filters,
        });
        println!("RUST_GAME_GLES_PIPELINE {}", self.pipeline_info());
        Ok(())
    }
    pub fn pipeline_info(&self) -> serde_json::Value {
        match &self.game_target {
            Some(target) => {
                serde_json::json!({"config":"game-opaque-RGB10_A2-ESSL300-highp","actual_render_target":target.actual,"actual_presentation_window":target.window_actual,"actual_source_filters":target.source_filters,"render_shader_profile":"ESSL300-explicit-highp-output","vertex_projection":"Godot-CPU-precomputed-mat4-with-native-Y-reflection","projection_column_major":game_screen_transform(self.width,self.height),"rect_vertex_indices_TL_TR_BR_BL":self.rect_vertex_order,"copy_shader_profile":"ESSL300-highp-float-and-sampler","size":target.size,"normal_presentation":"persistent-highp-fullscreen-shader-copy-to-window-then-swap","present_phase_includes_copy":true,"capture":"request-only-shader-copy-to-temp-RGBA8-outside-clean-timers","owned_target_allocations":self.target_allocations,"normal_copy_draws":self.normal_copy_draws,"per_frame_target_allocation":false,"per_frame_shader_allocation":false})
            }
            None => serde_json::json!({"config":"legacy-diagnostic-default-window-ESSL100"}),
        }
    }
    pub fn last_capture_pipeline(&self) -> Option<&serde_json::Value> {
        self.last_capture_pipeline.as_ref()
    }
    /// Source-faithful full-section copy using resources prepared before READY.
    /// No allocations, uniform-name lookups, asset reads or readback in this path.
    fn draw_game_copy(&self, source: usize, destination: Option<usize>) -> Result<(), String> {
        let input = self
            .diagnostic_targets
            .get(source)
            .ok_or("missing game render target")?;
        let output = destination
            .map(|i| {
                self.diagnostic_targets
                    .get(i)
                    .ok_or("missing game copy target")
            })
            .transpose()?;
        let copy = self
            .diagnostic_copy
            .as_ref()
            .ok_or("game copy resources not initialized")?;
        unsafe {
            let gl = &self.gl;
            gl.bind_framebuffer(glow::FRAMEBUFFER, output.map(|t| t.framebuffer));
            gl.viewport(0, 0, self.width as i32, self.height as i32);
            gl.depth_mask(false);
            gl.disable(glow::DEPTH_TEST);
            gl.disable(glow::CULL_FACE);
            gl.disable(glow::BLEND);
            gl.color_mask(true, true, true, true);
            gl.active_texture(glow::TEXTURE0);
            gl.bind_texture(glow::TEXTURE_2D, Some(input.texture));
            gl.clear_color(0.0, 0.0, 0.0, 0.0);
            gl.clear(glow::COLOR_BUFFER_BIT);
            gl.use_program(Some(copy.program));
            gl.uniform_1_i32(copy.source_uniform.as_ref(), 0);
            gl.uniform_4_f32(copy.section_uniform.as_ref(), 0.0, 0.0, 1.0, 1.0);
            gl.bind_vertex_array(Some(copy.vao));
            gl.draw_arrays(glow::TRIANGLES, 0, 6);
            gl.bind_vertex_array(None);
        }
        self.check_error()
    }
    /// Read-only diagnostic state. Never changes the gameplay rendering path.
    pub fn framebuffer_info(&self) -> Result<serde_json::Value, String> {
        unsafe {
            let gl = &self.gl;
            let binding = gl.get_parameter_i32(glow::DRAW_FRAMEBUFFER_BINDING);
            let point = if binding == 0 {
                glow::BACK
            } else {
                glow::COLOR_ATTACHMENT0
            };
            let attachment =
                |name| gl.get_framebuffer_attachment_parameter_i32(glow::FRAMEBUFFER, point, name);
            let attributes = self.video.gl_attr();
            let value = serde_json::json!({
                "vendor":gl.get_parameter_string(glow::VENDOR),"renderer":gl.get_parameter_string(glow::RENDERER),"version":gl.get_parameter_string(glow::VERSION),"glsl_version":gl.get_parameter_string(glow::SHADING_LANGUAGE_VERSION),
                "draw_framebuffer_binding":gl.get_parameter_i32(glow::DRAW_FRAMEBUFFER_BINDING),"read_framebuffer_binding":gl.get_parameter_i32(glow::READ_FRAMEBUFFER_BINDING),
                "rgba_bits":[gl.get_parameter_i32(glow::RED_BITS),gl.get_parameter_i32(glow::GREEN_BITS),gl.get_parameter_i32(glow::BLUE_BITS),gl.get_parameter_i32(glow::ALPHA_BITS)],
                "attachment_rgba_bits":[attachment(glow::FRAMEBUFFER_ATTACHMENT_RED_SIZE),attachment(glow::FRAMEBUFFER_ATTACHMENT_GREEN_SIZE),attachment(glow::FRAMEBUFFER_ATTACHMENT_BLUE_SIZE),attachment(glow::FRAMEBUFFER_ATTACHMENT_ALPHA_SIZE)],
                "attachment_component_type_enum":attachment(glow::FRAMEBUFFER_ATTACHMENT_COMPONENT_TYPE),"attachment_color_encoding_enum":attachment(glow::FRAMEBUFFER_ATTACHMENT_COLOR_ENCODING),"attachment_object_type_enum":attachment(glow::FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE),
                "samples":gl.get_parameter_i32(glow::SAMPLES),"sample_buffers":gl.get_parameter_i32(glow::SAMPLE_BUFFERS),"dither_enabled":gl.is_enabled(glow::DITHER),"blend_enabled":gl.is_enabled(glow::BLEND),
                "blend_src_rgb_enum":gl.get_parameter_i32(glow::BLEND_SRC_RGB),"blend_dst_rgb_enum":gl.get_parameter_i32(glow::BLEND_DST_RGB),"blend_src_alpha_enum":gl.get_parameter_i32(glow::BLEND_SRC_ALPHA),"blend_dst_alpha_enum":gl.get_parameter_i32(glow::BLEND_DST_ALPHA),
                "SDL_actual_srgb_capable":attributes.framebuffer_srgb_compatible(),"SDL_actual_buffer_bits":attributes.buffer_size()
            });
            self.check_error()?;
            println!("RUST_BLEND_PROBE_GL_INFO {value}");
            Ok(value)
        }
    }
    /// Diagnostic-only render target. Existing draw/shader/blend state is untouched.
    pub fn create_diagnostic_unorm_target(&mut self, rgb10: bool) -> Result<usize, String> {
        let (internal, kind) = if rgb10 {
            (glow::RGB10_A2, glow::UNSIGNED_INT_2_10_10_10_REV)
        } else {
            (glow::RGBA8, glow::UNSIGNED_BYTE)
        };
        self.create_diagnostic_target(internal, kind)
    }
    /// Exact GLES texture_2d_get temp format: unsized RGBA/UNSIGNED_BYTE.
    pub fn create_diagnostic_readback_target(&mut self) -> Result<usize, String> {
        let index = self.create_diagnostic_target(glow::RGBA, glow::UNSIGNED_BYTE)?;
        unsafe {
            self.gl.bind_texture(
                glow::TEXTURE_2D,
                Some(self.diagnostic_targets[index].texture),
            );
            self.gl.tex_parameter_i32(
                glow::TEXTURE_2D,
                glow::TEXTURE_MIN_FILTER,
                glow::LINEAR as i32,
            );
            self.gl.tex_parameter_i32(
                glow::TEXTURE_2D,
                glow::TEXTURE_MAG_FILTER,
                glow::LINEAR as i32,
            );
        }
        self.check_error()?;
        Ok(index)
    }
    fn create_diagnostic_target(&mut self, internal: u32, kind: u32) -> Result<usize, String> {
        unsafe {
            let gl = &self.gl;
            let texture = gl.create_texture()?;
            gl.bind_texture(glow::TEXTURE_2D, Some(texture));
            for (name, value) in [
                (glow::TEXTURE_MIN_FILTER, glow::NEAREST),
                (glow::TEXTURE_MAG_FILTER, glow::NEAREST),
                (glow::TEXTURE_WRAP_S, glow::CLAMP_TO_EDGE),
                (glow::TEXTURE_WRAP_T, glow::CLAMP_TO_EDGE),
            ] {
                gl.tex_parameter_i32(glow::TEXTURE_2D, name, value as i32);
            }
            gl.tex_image_2d(
                glow::TEXTURE_2D,
                0,
                internal as i32,
                self.width as i32,
                self.height as i32,
                0,
                glow::RGBA,
                kind,
                glow::PixelUnpackData::Slice(None),
            );
            // glow0.16 does not expose the ES3.1 level query; use the same SDL
            // context's required native symbol, only in this diagnostic path.
            let address = self.video.gl_get_proc_address("glGetTexLevelParameteriv");
            if address.is_null() {
                gl.delete_texture(texture);
                return Err("diagnostic internal-format query unavailable".into());
            }
            let query: unsafe extern "system" fn(u32, i32, u32, *mut i32) =
                std::mem::transmute(address);
            let mut actual_internal_format = 0;
            query(
                glow::TEXTURE_2D,
                0,
                glow::TEXTURE_INTERNAL_FORMAT,
                &mut actual_internal_format,
            );
            let framebuffer = gl.create_framebuffer()?;
            gl.bind_framebuffer(glow::FRAMEBUFFER, Some(framebuffer));
            gl.framebuffer_texture_2d(
                glow::FRAMEBUFFER,
                glow::COLOR_ATTACHMENT0,
                glow::TEXTURE_2D,
                Some(texture),
                0,
            );
            let status = gl.check_framebuffer_status(glow::FRAMEBUFFER);
            gl.bind_framebuffer(glow::FRAMEBUFFER, None);
            if status != glow::FRAMEBUFFER_COMPLETE {
                gl.delete_framebuffer(framebuffer);
                gl.delete_texture(texture);
                return Err(format!("diagnostic UNORM FBO incomplete:0x{status:x}"));
            }
            self.check_error()?;
            self.target_allocations += 1;
            self.diagnostic_targets.push(DiagnosticTarget {
                framebuffer,
                texture,
                actual_internal_format,
            });
            Ok(self.diagnostic_targets.len() - 1)
        }
    }
    /// Diagnostic-only switch after all ESSL100 control captures finish.
    pub fn select_diagnostic_es300_render(&mut self) -> Result<(), String> {
        let (vertex, fragment) = diagnostic_es300_render_sources();
        unsafe {
            let next = compile_sources(&self.gl, &vertex, &fragment)?;
            self.gl.use_program(Some(next));
            self.gl
                .uniform_1_i32(self.gl.get_uniform_location(next, "u_texture").as_ref(), 0);
            self.gl.delete_program(self.program);
            self.program = next;
            self.uniforms = Uniforms::load(&self.gl, next);
            self.batch_texture = None;
            self.batch_palette = None;
            self.gl.disable(glow::DEPTH_TEST);
            self.gl.disable(glow::CULL_FACE);
            self.gl.disable(glow::DITHER);
            self.gl.disable(glow::SCISSOR_TEST);
            self.gl.enable(glow::BLEND);
            self.gl.blend_func_separate(
                glow::SRC_ALPHA,
                glow::ONE_MINUS_SRC_ALPHA,
                glow::ONE,
                glow::ONE_MINUS_SRC_ALPHA,
            );
        }
        self.check_error()?;
        println!(
            "RUST_DIAGNOSTIC_RENDER_SHADER ESSL300 explicit_output=highp numeric_math=unchanged"
        );
        Ok(())
    }
    fn prepare_copy_resources(&mut self) -> Result<(), String> {
        if self.diagnostic_copy.is_some() {
            return Ok(());
        }
        unsafe {
            let program = compile_sources(&self.gl, COPY_VERTEX, COPY_FRAGMENT)?;
            let buffer = self.gl.create_buffer()?;
            let vao = self.gl.create_vertex_array()?;
            self.gl.bind_vertex_array(Some(vao));
            self.gl.bind_buffer(glow::ARRAY_BUFFER, Some(buffer));
            let bytes = std::slice::from_raw_parts(
                COPY_QUAD.as_ptr().cast::<u8>(),
                std::mem::size_of_val(&COPY_QUAD),
            );
            self.gl
                .buffer_data_u8_slice(glow::ARRAY_BUFFER, bytes, glow::STATIC_DRAW);
            self.gl
                .vertex_attrib_pointer_f32(0, 2, glow::FLOAT, false, 8, 0);
            self.gl.enable_vertex_attrib_array(0);
            self.gl.bind_vertex_array(None);
            self.diagnostic_copy = Some(CopyResources {
                program,
                buffer,
                vao,
                source_uniform: self.gl.get_uniform_location(program, "source"),
                section_uniform: self.gl.get_uniform_location(program, "copy_section"),
            });
        }
        self.check_error()
    }
    /// Godot GLES readback's shader-sampling conversion, not a framebuffer blit.
    /// Keeps original rendering in ESSL100; only this copy uses the vendor's ESSL300 output.
    pub fn diagnostic_shader_copy(
        &mut self,
        source: usize,
        destination: usize,
        render_shader: &str,
    ) -> Result<serde_json::Value, String> {
        if source == destination {
            return Err("diagnostic copy cannot sample its destination".into());
        }
        self.prepare_copy_resources()?;
        unsafe {
            let input = self
                .diagnostic_targets
                .get(source)
                .ok_or("unknown copy source")?;
            let output = self
                .diagnostic_targets
                .get(destination)
                .ok_or("unknown copy destination")?;
            let copy = self.diagnostic_copy.as_ref().unwrap();
            let gl = &self.gl;
            gl.bind_framebuffer(glow::FRAMEBUFFER, Some(output.framebuffer));
            gl.viewport(0, 0, self.width as i32, self.height as i32);
            gl.depth_mask(false);
            gl.depth_func(glow::GEQUAL);
            gl.disable(glow::DEPTH_TEST);
            gl.disable(glow::CULL_FACE);
            gl.disable(glow::BLEND);
            gl.color_mask(true, true, true, true);
            gl.active_texture(glow::TEXTURE0);
            gl.bind_texture(glow::TEXTURE_2D, Some(input.texture));
            let source_min = gl.get_tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MIN_FILTER);
            let source_mag = gl.get_tex_parameter_i32(glow::TEXTURE_2D, glow::TEXTURE_MAG_FILTER);
            if source_min != glow::NEAREST as i32 || source_mag != glow::NEAREST as i32 {
                return Err(
                    "copy source filter differs from original render-target nearest".into(),
                );
            }
            gl.clear_color(0.0, 0.0, 0.0, 0.0);
            gl.clear(glow::COLOR_BUFFER_BIT);
            gl.use_program(Some(copy.program));
            gl.uniform_1_i32(copy.source_uniform.as_ref(), 0);
            gl.uniform_4_f32(copy.section_uniform.as_ref(), 0.0, 0.0, 1.0, 1.0);
            gl.bind_vertex_array(Some(copy.vao));
            gl.draw_arrays(glow::TRIANGLES, 0, 6);
            gl.bind_vertex_array(None);
            self.check_error()?;
            Ok(
                serde_json::json!({"copy":"shader-MODE_COPY_SECTION-MODE_SIMPLE_COPY","render_shader":render_shader,"copy_shader":"ESSL300-highp-float-and-sampler","linear_to_srgb":false,"multiply":false,"blend_enabled":gl.is_enabled(glow::BLEND),"source_min_filter_enum":source_min,"source_mag_filter_enum":source_mag,"copy_section":[0,0,1,1],"cpu_byte_adjustment":false}),
            )
        }
    }
    pub fn bind_diagnostic_target(&self, index: Option<usize>) -> Result<(), String> {
        let target = index
            .map(|i| {
                self.diagnostic_targets
                    .get(i)
                    .ok_or("unknown diagnostic target")
            })
            .transpose()?;
        unsafe {
            self.gl
                .bind_framebuffer(glow::FRAMEBUFFER, target.map(|t| t.framebuffer));
        }
        self.check_error()
    }
    pub fn diagnostic_target_internal_format(&self, index: usize) -> Result<i32, String> {
        self.diagnostic_targets
            .get(index)
            .map(|t| t.actual_internal_format)
            .ok_or_else(|| "unknown diagnostic target".into())
    }
    pub fn present_diagnostic_target(&mut self, index: usize) -> Result<(), String> {
        let t = self
            .diagnostic_targets
            .get(index)
            .ok_or("unknown diagnostic target")?;
        unsafe {
            self.gl
                .bind_framebuffer(glow::READ_FRAMEBUFFER, Some(t.framebuffer));
            self.gl.bind_framebuffer(glow::DRAW_FRAMEBUFFER, None);
            self.gl.blit_framebuffer(
                0,
                0,
                self.width as i32,
                self.height as i32,
                0,
                0,
                self.width as i32,
                self.height as i32,
                glow::COLOR_BUFFER_BIT,
                glow::NEAREST,
            );
            self.gl.bind_framebuffer(glow::FRAMEBUFFER, None);
        }
        self.check_error()?;
        self.present()?;
        Ok(())
    }
    /// Collect the following uploads into atlas pages. Call finish_atlas after them.
    pub fn begin_atlas(&mut self) -> Result<(), String> {
        if !self.placements.is_empty() || self.atlas_pending.is_some() {
            return Err("atlas must start before any image upload".into());
        }
        self.atlas_pending = Some(Vec::new());
        Ok(())
    }
    /// Pack the collected images, upload the pages, and fix every image's placement.
    pub fn finish_atlas(&mut self) -> Result<serde_json::Value, String> {
        let images = self.atlas_pending.take().ok_or("atlas was not started")?;
        let sizes: Vec<[u32; 2]> = images.iter().map(|i| [i.width, i.height]).collect();
        let packed = crate::atlas::pack(&sizes, self.texture_limit.max(0) as u32);
        let views: Vec<(u32, u32, &[u8])> = images
            .iter()
            .map(|i| (i.width, i.height, i.rgba.as_slice()))
            .collect();
        let mut page_textures = Vec::with_capacity(packed.pages);
        for page in 0..packed.pages {
            let rgba = crate::atlas::compose(&packed, page, &views)?;
            page_textures.push(self.upload_texture(packed.page_size, packed.page_size, &rgba)?);
        }
        let mut standalone = 0usize;
        for (index, image) in images.iter().enumerate() {
            let own = self.upload_texture(image.width, image.height, &image.rgba)?;
            self.placements[index] = match packed.placements[index] {
                Some(p) => ImagePlacement {
                    texture: page_textures[p.page],
                    atlas: Some(AtlasSpot {
                        offset: [p.x, p.y],
                        extent: [image.width, image.height],
                        page: packed.page_size,
                    }),
                    standalone: own,
                },
                None => {
                    standalone += 1;
                    ImagePlacement {
                        texture: own,
                        atlas: None,
                        standalone: own,
                    }
                }
            };
        }
        self.atlas_enabled = true;
        self.batch_texture = None;
        let report = serde_json::json!({
            "images": images.len(),
            "page_size": packed.page_size,
            "pages": packed.pages,
            "standalone_images": standalone,
            "padding_px": crate::atlas::PAD,
            "gpu_page_bytes": packed.pages * (packed.page_size as usize).pow(2) * 4,
        });
        println!("RUST_ATLAS {report}");
        Ok(report)
    }
    pub fn atlas_info(&self) -> serde_json::Value {
        serde_json::json!({
            "enabled": self.atlas_enabled,
            "uv_out_of_range_quads": self.atlas_uv_out_of_range,
            "atlas_quads": self.atlas_quads,
            "standalone_quads": self.standalone_quads,
        })
    }
    pub fn upload(&mut self, image: &Image) -> Result<usize, String> {
        if image.width as i32 > self.texture_limit || image.height as i32 > self.texture_limit {
            return Err("owned GLES texture limit exceeded".into());
        }
        if let Some(pending) = &mut self.atlas_pending {
            pending.push(Image {
                width: image.width,
                height: image.height,
                rgba: image.rgba.clone(),
                sha256: image.sha256.clone(),
            });
            // Placeholder; finish_atlas replaces it before any draw.
            self.placements.push(ImagePlacement {
                texture: usize::MAX,
                atlas: None,
                standalone: usize::MAX,
            });
            return Ok(self.placements.len() - 1);
        }
        let texture = self.upload_texture(image.width, image.height, &image.rgba)?;
        self.placements.push(ImagePlacement {
            texture,
            atlas: None,
            standalone: texture,
        });
        Ok(self.placements.len() - 1)
    }
    fn upload_texture(&mut self, width: u32, height: u32, rgba: &[u8]) -> Result<usize, String> {
        if width as i32 > self.texture_limit || height as i32 > self.texture_limit {
            return Err("owned GLES texture limit exceeded".into());
        }
        self.batch_texture = None;
        unsafe {
            let texture = self.gl.create_texture()?;
            self.gl.bind_texture(glow::TEXTURE_2D, Some(texture));
            for (key, value) in [
                (glow::TEXTURE_MIN_FILTER, glow::NEAREST),
                (glow::TEXTURE_MAG_FILTER, glow::NEAREST),
                (glow::TEXTURE_WRAP_S, glow::CLAMP_TO_EDGE),
                (glow::TEXTURE_WRAP_T, glow::CLAMP_TO_EDGE),
            ] {
                self.gl
                    .tex_parameter_i32(glow::TEXTURE_2D, key, value as i32);
            }
            self.gl.tex_image_2d(
                glow::TEXTURE_2D,
                0,
                glow::RGBA as i32,
                width as i32,
                height as i32,
                0,
                glow::RGBA,
                glow::UNSIGNED_BYTE,
                glow::PixelUnpackData::Slice(Some(rgba)),
            );
            let error = self.gl.get_error();
            if error != glow::NO_ERROR {
                self.gl.delete_texture(texture);
                return Err(format!("texture upload GLES error 0x{error:x}"));
            }
            self.textures.push(texture);
            Ok(self.textures.len() - 1)
        }
    }
    pub fn begin(&mut self, rgb: [u8; 3]) -> Result<[u32; 2], String> {
        self.batch_texture = None; // presentation/capture/upload may have rebound TEXTURE0
        (self.width, self.height) = self.window.drawable_size();
        if self.width == 0 || self.height == 0 {
            return Err("zero framebuffer".into());
        }
        if self
            .game_target
            .as_ref()
            .is_some_and(|t| t.size != [self.width, self.height])
        {
            self.allocate_game_target()?;
        }
        if let Some(target) = &self.game_target {
            self.bind_diagnostic_target(Some(target.index))?;
            unsafe {
                self.gl.enable(glow::BLEND);
            }
        }
        unsafe {
            self.gl
                .viewport(0, 0, self.width as i32, self.height as i32);
            self.gl.clear_color(
                rgb[0] as f32 / 255.0,
                rgb[1] as f32 / 255.0,
                rgb[2] as f32 / 255.0,
                1.0,
            );
            self.gl.clear(glow::COLOR_BUFFER_BIT);
            if let Some(plain) = &self.plain {
                self.gl.use_program(Some(plain.program));
                self.gl.uniform_2_f32(
                    plain.viewport.as_ref(),
                    self.width as f32,
                    self.height as f32,
                );
            }
            self.gl.use_program(Some(self.program));
            self.plain_bound = false;
            self.gl.uniform_2_f32(
                self.uniforms.viewport.as_ref(),
                self.width as f32,
                self.height as f32,
            );
            self.gl.uniform_1_i32(self.uniforms.darkness.as_ref(), 0);
        }
        Ok([self.width, self.height])
    }
    /// Deliberately incorrect benchmark picture, never enabled by normal play.
    pub fn enable_benchmark_single_texture(&mut self) -> Result<(), String> {
        self.enable_benchmark_single_texture_image(0)
    }
    pub fn enable_benchmark_single_texture_image(&mut self, image: usize) -> Result<(), String> {
        if image >= self.placements.len() || self.atlas_enabled {
            return Err("single-texture test needs an uploaded image and no atlas".into());
        }
        self.benchmark_single_texture = Some(self.placements[image].texture);
        self.batch_texture = None;
        self.batch_palette = None;
        println!(
            "RUST_BENCHMARK_SINGLE_TEXTURE picture_invalid=true uploaded_texture_index={image} palette=empty geometry_unchanged=true"
        );
        Ok(())
    }
    pub fn draw(&mut self, quads: &[Quad]) -> Result<DrawCounts, String> {
        let mut counts = DrawCounts::default();
        // One routing decision per quad per frame.
        let routes: Vec<Option<(usize, Option<AtlasSpot>)>> = if self.atlas_enabled {
            quads.iter().map(|q| route(&self.placements, q)).collect()
        } else {
            Vec::new()
        };
        let mut first = 0;
        while first < quads.len() {
            let mut end = first + 1;
            while end < quads.len()
                && if self.atlas_enabled {
                    quads[end].palette == quads[first].palette
                        && match (routes[end], routes[first]) {
                            (Some(x), Some(y)) => x.0 == y.0,
                            _ => quads[end].image == quads[first].image,
                        }
                } else {
                    same_batch(
                        &quads[end],
                        &quads[first],
                        self.benchmark_single_texture.is_some(),
                    )
                }
            {
                end += 1;
            }
            self.vertices.clear();
            for (k, q) in quads[first..end].iter().enumerate() {
                let spot = if self.atlas_enabled {
                    routes[first + k].and_then(|r| r.1)
                } else {
                    None
                };
                if self.atlas_enabled {
                    if spot.is_some() {
                        self.atlas_quads += 1;
                    } else {
                        self.standalone_quads += 1;
                    }
                    if q.uv.iter().flatten().any(|v| !(0.0..=1.0).contains(v)) {
                        self.atlas_uv_out_of_range += 1;
                    }
                }
                for i in self.rect_vertex_order {
                    let uv = match spot {
                        Some(s) => [
                            crate::atlas::remap(q.uv[i][0], s.offset[0], s.extent[0], s.page),
                            crate::atlas::remap(q.uv[i][1], s.offset[1], s.extent[1], s.page),
                        ],
                        None => q.uv[i],
                    };
                    self.vertices.extend_from_slice(&[
                        q.corners[i][0],
                        q.corners[i][1],
                        uv[0],
                        uv[1],
                        q.color[0],
                        q.color[1],
                        q.color[2],
                        q.color[3],
                    ]);
                }
            }
            let q = &quads[first];
            if q.palette.len() > 8 {
                return Err("more than eight palette swaps not admitted".into());
            }
            let image = match self.benchmark_single_texture {
                Some(texture) => texture,
                None if self.atlas_enabled => routes[first].ok_or("unuploaded frame image")?.0,
                None => {
                    self.placements
                        .get(q.image)
                        .ok_or("unuploaded frame image")?
                        .texture
                }
            };
            let palette: &[PaletteSwap] = if self.benchmark_single_texture.is_some() {
                &[]
            } else {
                &q.palette
            };
            unsafe {
                let want_plain = palette.is_empty() && self.plain.is_some();
                if want_plain != self.plain_bound {
                    let program = match (&self.plain, want_plain) {
                        (Some(plain), true) => plain.program,
                        _ => self.program,
                    };
                    self.gl.use_program(Some(program));
                    self.plain_bound = want_plain;
                }
                if self.batch_texture != Some(image) {
                    self.gl.active_texture(glow::TEXTURE0);
                    self.gl.bind_texture(
                        glow::TEXTURE_2D,
                        Some(*self.textures.get(image).ok_or("unuploaded frame image")?),
                    );
                    self.batch_texture = Some(image);
                }
                // Swap uniforms belong to the original program; the plain one has none.
                if !want_plain && self.batch_palette.as_deref() != Some(palette) {
                    self.gl
                        .uniform_1_i32(self.uniforms.count.as_ref(), palette.len() as i32);
                    let mut keys = [0.0; 24];
                    let mut values = [0.0; 24];
                    for (i, swap) in palette.iter().enumerate() {
                        for j in 0..3 {
                            keys[i * 3 + j] = swap.from[j] as f32 / 255.0;
                            values[i * 3 + j] = swap.to[j] as f32 / 255.0;
                        }
                    }
                    self.gl
                        .uniform_3_f32_slice(self.uniforms.keys.as_ref(), &keys);
                    self.gl
                        .uniform_3_f32_slice(self.uniforms.values.as_ref(), &values);
                    self.batch_palette = Some(palette.to_vec());
                }
                self.submit();
            }
            counts.quads += (end - first) as u64;
            counts.batches += 1;
            counts.vertices += ((end - first) * 6) as u64;
            first = end;
        }
        Ok(counts)
    }
    /// Exact map_effects.gd analytic smoothstep, after world and before HUD.
    pub fn darkness(&mut self, origin: [f64; 2], radius: f64, strength: f64) -> Result<(), String> {
        if !(0.0..=1.0).contains(&strength)
            || !radius.is_finite()
            || radius <= 0.0
            || origin.iter().any(|v| !v.is_finite())
        {
            return Err("invalid darkness parameters".into());
        }
        if strength == 0.0 {
            return Ok(());
        }
        self.vertices.clear();
        let corners = [
            [0.0, 0.0],
            [self.width as f32, 0.0],
            [self.width as f32, self.height as f32],
            [0.0, self.height as f32],
        ];
        for i in self.rect_vertex_order {
            self.vertices.extend_from_slice(&[
                corners[i][0],
                corners[i][1],
                0.0,
                0.0,
                1.0,
                1.0,
                1.0,
                1.0,
            ]);
        }
        unsafe {
            if self.plain_bound {
                self.gl.use_program(Some(self.program));
                self.plain_bound = false;
            }
            self.gl.uniform_1_i32(self.uniforms.darkness.as_ref(), 1);
            self.gl.uniform_2_f32(
                self.uniforms.light_origin.as_ref(),
                origin[0] as f32,
                origin[1] as f32,
            );
            self.gl
                .uniform_1_f32(self.uniforms.light_radius.as_ref(), radius as f32);
            self.gl
                .uniform_1_f32(self.uniforms.strength.as_ref(), strength as f32);
            self.submit();
            self.gl.uniform_1_i32(self.uniforms.darkness.as_ref(), 0);
        }
        Ok(())
    }
    unsafe fn submit(&self) {
        unsafe {
            self.gl.bind_buffer(glow::ARRAY_BUFFER, Some(self.buffer));
            let bytes = std::slice::from_raw_parts(
                self.vertices.as_ptr().cast::<u8>(),
                self.vertices.len() * std::mem::size_of::<f32>(),
            );
            self.gl
                .buffer_data_u8_slice(glow::ARRAY_BUFFER, bytes, glow::STREAM_DRAW);
            for (index, size, offset) in [(0, 2, 0), (1, 2, 8), (2, 4, 16)] {
                self.gl.enable_vertex_attrib_array(index);
                self.gl
                    .vertex_attrib_pointer_f32(index, size, glow::FLOAT, false, 32, offset);
            }
            self.gl
                .draw_arrays(glow::TRIANGLES, 0, (self.vertices.len() / 8) as i32);
        }
    }
    pub fn present(&mut self) -> Result<(), String> {
        if let Some(target) = &self.game_target {
            self.draw_game_copy(target.index, None)?;
            self.normal_copy_draws += 1;
        }
        self.window.gl_swap_window();
        Ok(())
    }
    /// Explicit evidence mode only. Call before present; excluded from clean timing.
    /// Benchmark picture check: SHA-256 of the current game target's RGBA readback
    /// (rows top-down), optionally also written as PNG. Outside clean timers.
    pub fn frame_digest(&mut self, dump: Option<&std::path::Path>) -> Result<String, String> {
        let source = self
            .game_target
            .as_ref()
            .map(|t| t.index)
            .ok_or("frame digest needs the game target")?;
        let destination = self.create_diagnostic_readback_target()?;
        self.draw_game_copy(source, Some(destination))?;
        let pixels = self.read_bound_pixels();
        self.bind_diagnostic_target(None)?;
        self.delete_last_target(destination)?;
        self.bind_diagnostic_target(Some(source))?;
        self.batch_texture = None;
        self.batch_palette = None;
        unsafe {
            self.gl.use_program(Some(self.program));
        }
        self.plain_bound = false;
        if let Some(path) = dump {
            self.write_png(path, &pixels)?;
        }
        self.check_error()?;
        Ok(crate::pack::hash(&pixels))
    }
    pub fn capture(&mut self, path: &std::path::Path) -> Result<(), String> {
        if let Some(source) = self.game_target.as_ref().map(|t| t.index) {
            let destination = self.create_diagnostic_readback_target()?;
            self.draw_game_copy(source, Some(destination))?;
            let result = self.capture_bound(path);
            let actual = self.framebuffer_info()?;
            self.last_capture_pipeline = Some(
                serde_json::json!({"render_profile":"ESSL300-explicit-highp-output","source_internal_format_enum":self.diagnostic_target_internal_format(source)?,"readback_internal_format_enum":self.diagnostic_target_internal_format(destination)?,"actual_readback_target":actual,"capture_only_temporary_allocation":true,"outside_clean_timers":true,"cpu_byte_adjustments":false}),
            );
            self.bind_diagnostic_target(None)?;
            self.delete_last_target(destination)?;
            self.bind_diagnostic_target(Some(source))?;
            result
        } else {
            self.capture_bound(path)
        }
    }
    fn capture_bound(&self, path: &std::path::Path) -> Result<(), String> {
        let pixels = self.read_bound_pixels();
        self.write_png(path, &pixels)?;
        self.check_error()?;
        println!("RUST_OWNED_CAPTURE actual-GPU-readback path={path:?} clean_timing=false");
        Ok(())
    }
    fn write_png(&self, path: &std::path::Path, pixels: &[u8]) -> Result<(), String> {
        let mut encoder = png::Encoder::new(
            std::fs::File::create(path).map_err(|e| e.to_string())?,
            self.width,
            self.height,
        );
        encoder.set_color(png::ColorType::Rgba);
        encoder
            .write_header()
            .map_err(|e| e.to_string())?
            .write_image_data(pixels)
            .map_err(|e| e.to_string())
    }
    fn read_bound_pixels(&self) -> Vec<u8> {
        let mut pixels = vec![0; self.width as usize * self.height as usize * 4];
        unsafe {
            self.gl.read_pixels(
                0,
                0,
                self.width as i32,
                self.height as i32,
                glow::RGBA,
                glow::UNSIGNED_BYTE,
                glow::PixelPackData::Slice(Some(&mut pixels)),
            );
        }
        let stride = self.width as usize * 4;
        for y in 0..self.height as usize / 2 {
            let other = (self.height as usize - 1 - y) * stride;
            for x in 0..stride {
                pixels.swap(y * stride + x, other + x);
            }
        }
        pixels
    }
    pub fn check_error(&self) -> Result<(), String> {
        let e = unsafe { self.gl.get_error() };
        if e == glow::NO_ERROR {
            Ok(())
        } else {
            Err(format!("owned GLES error0x{e:x}"))
        }
    }
}
unsafe fn compile(gl: &glow::Context) -> Result<glow::Program, String> {
    unsafe { compile_sources(gl, VERTEX, FRAGMENT) }
}
unsafe fn compile_sources(
    gl: &glow::Context,
    vertex: &str,
    fragment: &str,
) -> Result<glow::Program, String> {
    unsafe {
        let program = gl.create_program()?;
        for (kind, source) in [
            (glow::VERTEX_SHADER, vertex),
            (glow::FRAGMENT_SHADER, fragment),
        ] {
            let shader = gl.create_shader(kind)?;
            gl.shader_source(shader, source);
            gl.compile_shader(shader);
            if !gl.get_shader_compile_status(shader) {
                let error = gl.get_shader_info_log(shader);
                gl.delete_shader(shader);
                gl.delete_program(program);
                return Err(format!("owned GLES shader compile: {error}"));
            }
            gl.attach_shader(program, shader);
            gl.delete_shader(shader);
        }
        gl.bind_attrib_location(program, 0, "a_position");
        gl.bind_attrib_location(program, 1, "a_uv");
        gl.bind_attrib_location(program, 2, "a_color");
        gl.link_program(program);
        if !gl.get_program_link_status(program) {
            let error = gl.get_program_info_log(program);
            gl.delete_program(program);
            return Err(format!("owned GLES link: {error}"));
        }
        Ok(program)
    }
}
impl Drop for Gles {
    fn drop(&mut self) {
        unsafe {
            if let Some(copy) = &self.diagnostic_copy {
                self.gl.delete_program(copy.program);
                self.gl.delete_buffer(copy.buffer);
                self.gl.delete_vertex_array(copy.vao);
            }
            for target in &self.diagnostic_targets {
                self.gl.delete_framebuffer(target.framebuffer);
                self.gl.delete_texture(target.texture);
            }
            for &texture in &self.textures {
                self.gl.delete_texture(texture);
            }
            self.lighting.delete(&self.gl);
            self.gl.delete_buffer(self.buffer);
            self.gl.delete_program(self.program);
            if let Some(plain) = &self.plain {
                self.gl.delete_program(plain.program);
            }
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn single_texture_merges_without_rewriting_quad_data() {
        let a = Quad {
            image: 1,
            corners: [[1.0, 2.0]; 4],
            uv: [[0.2, 0.3]; 4],
            color: [1.0; 4],
            palette: Vec::new(),
        };
        let mut b = a.clone();
        b.image = 9;
        assert!(!same_batch(&a, &b, false));
        assert!(same_batch(&a, &b, true));
        assert_eq!(a.corners, b.corners);
        assert_eq!(a.uv, b.uv);
    }
    #[test]
    fn game_rect_order_matches_vendor_vertex_base_without_changing_corners() {
        let corners = crate::geometry::UNIT_UV;
        assert_eq!(
            PipelineConfig::LegacyDefault.rect_order(),
            [0, 1, 2, 0, 2, 3]
        );
        assert_eq!(
            PipelineConfig::GameOpaqueRgb10
                .rect_order()
                .map(|i| corners[i]),
            [
                [0.0, 0.0],
                [0.0, 1.0],
                [1.0, 1.0],
                [1.0, 0.0],
                [0.0, 0.0],
                [1.0, 1.0]
            ]
        );
    }
    #[test]
    fn game_projection_changes_only_position_math_not_uv_or_fragment() {
        let (v, f) = game_es300_render_sources();
        let (_, control_fragment) = diagnostic_es300_render_sources();
        assert_eq!(f, control_fragment);
        assert!(v.contains("gl_Position = u_screen_transform * vec4(a_position,0.0,1.0);"));
        assert!(v.contains("v_uv=a_uv; v_color=a_color;"));
        assert!(!v.contains("a_position.x/u_viewport"));
        assert!(!v.contains("1e-5"));
        let m = game_screen_transform(640, 480);
        assert_eq!(m[0], 2.0_f32 / 640.0);
        assert_eq!(m[5], -2.0_f32 / 480.0);
        assert_eq!([m[12], m[13]], [-1.0, 1.0]);
        assert_eq!([640.0 * m[0] + m[12], 480.0 * m[5] + m[13]], [1.0, -1.0]);
    }
    #[test]
    fn es300_render_translation_changes_only_interface_syntax() {
        let (v, f) = diagnostic_es300_render_sources();
        assert!(v.starts_with("#version 300 es"));
        assert!(f.starts_with("#version 300 es"));
        assert!(f.contains("out highp vec4 diagnostic_frag_color;"));
        assert!(f.contains("diagnostic_frag_color=pixel*v_color;"));
        assert!(!f.contains("round("));
        assert!(!f.contains("floor("));
        assert!(f.contains("uniform highp sampler2D u_texture;"));
    }
    #[test]
    fn diagnostic_copy_matches_full_section_without_color_math() {
        assert!(COPY_VERTEX.contains("uv_interp=a_position*0.5+0.5;"));
        assert!(COPY_FRAGMENT.contains("vec4 color=texture(source,uv);frag_color=color;"));
        assert!(!COPY_FRAGMENT.contains("pow("));
        assert!(!COPY_FRAGMENT.contains("round("));
        assert_eq!(
            COPY_QUAD,
            [
                -1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0
            ]
        );
    }
    #[test]
    fn texture_precision_matches_godot_before_alpha_modulation() {
        assert!(FRAGMENT.contains("uniform highp sampler2D u_texture;"));
        assert!(FRAGMENT.contains("gl_FragColor=pixel*v_color;"));
    }
}
