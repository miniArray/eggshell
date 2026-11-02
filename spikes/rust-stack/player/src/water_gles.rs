//! Water-only GLES resources/pass. Deliberately separate from lighting shaders.
use super::{DrawCounts, Gles, compile_sources};
use crate::water_fx::Frame;
use glow::HasContext;

const WATER_VERTEX: &str = r#"#version 300 es
precision highp float;
uniform vec4 u_bounds;
uniform vec2 u_viewport;
const vec2 corners[6] = vec2[6](vec2(0,0),vec2(1,0),vec2(1,1),vec2(0,0),vec2(1,1),vec2(0,1));
void main() {
  vec2 p=mix(u_bounds.xy,u_bounds.zw,corners[gl_VertexID]);
  gl_Position=vec4(p.x/u_viewport.x*2.0-1.0,1.0-p.y/u_viewport.y*2.0,0,1);
}
"#;
const WATER_FRAGMENT: &str = r#"#version 300 es
precision highp float;
uniform vec2 u_viewport;
uniform vec2 u_offset;
uniform vec4 u_bounds;
uniform highp sampler2D u_scene;
uniform float u_scale;
uniform float u_phase;
uniform float u_strength;
layout(location=0) out highp vec4 frag_color;
void main() {
  vec2 screen=vec2(gl_FragCoord.x,u_viewport.y-gl_FragCoord.y);
  // Quantize in world pixels, so the pattern follows the map, not the camera.
  vec2 p=floor((screen-u_offset)/u_scale/2.0)*2.0;
  float a=sin(p.x*0.19+sin(p.y*0.12+u_phase)*1.5+u_phase);
  float b=sin(p.y*0.23+sin(p.x*0.09-u_phase)*1.5-u_phase);
  float light=max(0.0,1.0-abs(a+b)*5.0)*0.025*u_strength;
  // At most two framebuffer pixels, with nearest sampling and no vertical bend.
  float bend=floor(sin(p.y*0.11+u_phase)*u_strength*(2.0/3.0)+0.5);
  float x=clamp(screen.x+bend,u_bounds.x+0.5,u_bounds.z-0.5);
  vec2 uv=vec2(x/u_viewport.x,gl_FragCoord.y/u_viewport.y);
  vec4 scene=texture(u_scene,uv);
  frag_color=vec4(mix(scene.rgb,vec3(1),light),scene.a);
}
"#;

pub(super) struct WaterResources {
    program: glow::Program,
    vao: glow::VertexArray,
    snapshot: glow::Texture,
    snapshot_size: [u32; 2],
    scene: Option<glow::UniformLocation>,
    bounds: Option<glow::UniformLocation>,
    viewport: Option<glow::UniformLocation>,
    offset: Option<glow::UniformLocation>,
    scale: Option<glow::UniformLocation>,
    phase: Option<glow::UniformLocation>,
    strength: Option<glow::UniformLocation>,
}
impl Gles {
    pub(super) fn prepare_water_resources(&mut self) -> Result<(), String> {
        unsafe {
            let gl = &self.gl;
            let program = compile_sources(gl, WATER_VERTEX, WATER_FRAGMENT)?;
            let vao = gl.create_vertex_array()?;
            let snapshot = gl.create_texture()?;
            gl.bind_texture(glow::TEXTURE_2D, Some(snapshot));
            for (key, value) in [
                (glow::TEXTURE_MIN_FILTER, glow::NEAREST),
                (glow::TEXTURE_MAG_FILTER, glow::NEAREST),
                (glow::TEXTURE_WRAP_S, glow::CLAMP_TO_EDGE),
                (glow::TEXTURE_WRAP_T, glow::CLAMP_TO_EDGE),
            ] {
                gl.tex_parameter_i32(glow::TEXTURE_2D, key, value as i32);
            }
            self.water_resources = Some(WaterResources {
                program,
                vao,
                snapshot,
                snapshot_size: [0; 2],
                scene: gl.get_uniform_location(program, "u_scene"),
                bounds: gl.get_uniform_location(program, "u_bounds"),
                viewport: gl.get_uniform_location(program, "u_viewport"),
                offset: gl.get_uniform_location(program, "u_offset"),
                scale: gl.get_uniform_location(program, "u_scale"),
                phase: gl.get_uniform_location(program, "u_phase"),
                strength: gl.get_uniform_location(program, "u_strength"),
            });
        }
        self.check_error()
    }
    /// Only on-screen, disjoint water rectangles. No full-screen shader work.
    pub fn water_fx(&mut self, frame: &Frame) -> Result<DrawCounts, String> {
        if frame.regions.is_empty() || frame.strength == 0.0 {
            return Ok(DrawCounts::default());
        }
        let [left, top, width, height] = frame.copy_bounds().ok_or("missing water copy bounds")?;
        let water = self
            .water_resources
            .as_mut()
            .ok_or("water FX requires game GLES pipeline")?;
        unsafe {
            let gl = &self.gl;
            gl.active_texture(glow::TEXTURE0);
            gl.bind_texture(glow::TEXTURE_2D, Some(water.snapshot));
            if water.snapshot_size != [self.width, self.height] {
                // Persistent RGB10_A2 snapshot matches the game attachment. Never
                // quantize the underlying scene to RGBA8 on the way through water.
                gl.tex_image_2d(
                    glow::TEXTURE_2D,
                    0,
                    glow::RGB10_A2 as i32,
                    self.width as i32,
                    self.height as i32,
                    0,
                    glow::RGBA,
                    glow::UNSIGNED_INT_2_10_10_10_REV,
                    glow::PixelUnpackData::Slice(None),
                );
                water.snapshot_size = [self.width, self.height];
            }
            let bottom = self.height as i32 - top - height;
            // Copy only the visible water envelope, not a full-screen postprocess.
            // Sampling this separate texture avoids render-target feedback.
            gl.copy_tex_sub_image_2d(
                glow::TEXTURE_2D,
                0,
                left,
                bottom,
                left,
                bottom,
                width,
                height,
            );
            gl.disable(glow::BLEND);
            gl.use_program(Some(water.program));
            gl.uniform_1_i32(water.scene.as_ref(), 0);
            gl.bind_vertex_array(Some(water.vao));
            gl.uniform_2_f32(
                water.viewport.as_ref(),
                self.width as f32,
                self.height as f32,
            );
            gl.uniform_2_f32(water.offset.as_ref(), frame.offset[0], frame.offset[1]);
            gl.uniform_1_f32(water.scale.as_ref(), frame.scale);
            gl.uniform_1_f32(water.phase.as_ref(), frame.phase);
            gl.uniform_1_f32(water.strength.as_ref(), frame.strength);
            for r in &frame.regions {
                gl.uniform_4_f32(
                    water.bounds.as_ref(),
                    r[0] as f32,
                    r[1] as f32,
                    r[2] as f32,
                    r[3] as f32,
                );
                gl.draw_arrays(glow::TRIANGLES, 0, 6);
            }
            gl.bind_vertex_array(None);
            gl.enable(glow::BLEND);
            self.batch_texture = None;
            // The following surface, lighting and HUD draws use the normal batch
            // state. Do not leave the water program behind a stale plain flag.
            gl.use_program(Some(self.program));
            self.plain_bound = false;
        }
        self.check_error()?;
        let quads = frame.regions.len() as u64;
        Ok(DrawCounts {
            quads,
            batches: quads,
            vertices: quads * 6,
        })
    }
    pub(super) fn delete_water_resources(&self) {
        if let Some(water) = &self.water_resources {
            unsafe {
                self.gl.delete_program(water.program);
                self.gl.delete_vertex_array(water.vao);
                self.gl.delete_texture(water.snapshot);
            }
        }
    }
}
