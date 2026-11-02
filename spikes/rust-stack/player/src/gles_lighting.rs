//! Isolated game-feel shader programs; no changes to baseline/water shaders.
use super::*;
const LIGHT_FRAGMENT: &str = r#"
precision highp float;
varying vec2 v_uv;
varying vec4 v_color;
void main() {
  float d=length(v_uv*2.0-1.0);
  float falloff=1.0-smoothstep(0.0,1.0,d);
  float alpha=v_color.a*falloff*falloff;
  gl_FragColor=vec4(v_color.rgb*alpha,alpha);
}
"#;
pub(super) struct Resources {
    radial: glow::Program,
}
impl Resources {
    pub(super) unsafe fn new(gl: &glow::Context) -> Result<Self, String> {
        unsafe {
            Ok(Self {
                radial: compile_sources(gl, VERTEX, LIGHT_FRAGMENT)?,
            })
        }
    }
    pub(super) unsafe fn delete(&self, gl: &glow::Context) {
        unsafe {
            gl.delete_program(self.radial);
        }
    }
}
impl Gles {
    /// Bounded additive sprites. Dark maps use tint-only blending, not extra holes:
    /// source.rgb <= source.a implies output.rgb <= destination.rgb everywhere.
    pub fn lights(&mut self, frame: &crate::lighting::Frame) -> Result<DrawCounts, String> {
        self.vertices.clear();
        for l in &frame.lights {
            let r = l.radius;
            let [x, y] = l.at;
            let corners = [
                [x - r, y - r],
                [x + r, y - r],
                [x + r, y + r],
                [x - r, y + r],
            ];
            for i in self.rect_vertex_order {
                self.vertices.extend_from_slice(&[
                    corners[i][0],
                    corners[i][1],
                    crate::geometry::UNIT_UV[i][0],
                    crate::geometry::UNIT_UV[i][1],
                    l.color[0],
                    l.color[1],
                    l.color[2],
                    l.intensity * 0.12,
                ]);
            }
        }
        if self.vertices.is_empty() {
            return Ok(DrawCounts::default());
        }
        unsafe {
            self.gl.use_program(Some(self.lighting.radial));
            self.gl.uniform_2_f32(
                self.gl
                    .get_uniform_location(self.lighting.radial, "u_viewport")
                    .as_ref(),
                self.width as f32,
                self.height as f32,
            );
            self.fx_blend(frame.dark_map);
            self.submit();
            self.fx_restore();
        }
        self.check_error()?;
        Ok(DrawCounts {
            quads: frame.lights.len() as u64,
            batches: 1,
            vertices: (frame.lights.len() * 6) as u64,
        })
    }
    unsafe fn fx_blend(&self, dark: bool) {
        unsafe {
            self.gl.blend_func_separate(
                if dark { glow::DST_COLOR } else { glow::ONE },
                if dark {
                    glow::ONE_MINUS_SRC_ALPHA
                } else {
                    glow::ONE
                },
                glow::ZERO,
                glow::ONE,
            );
        }
    }
    unsafe fn fx_restore(&mut self) {
        unsafe {
            self.gl.blend_func_separate(
                glow::SRC_ALPHA,
                glow::ONE_MINUS_SRC_ALPHA,
                glow::ONE,
                glow::ONE_MINUS_SRC_ALPHA,
            );
            self.gl.use_program(Some(self.program));
            self.plain_bound = false;
            self.batch_texture = None;
            self.batch_palette = None;
        }
    }
}
