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
// The baseline shader is untouched. This program replaces a base draw only on
// normal-bearing, light-intersecting quads, in the same painter order.
const NORMAL_FRAGMENT: &str = r#"
precision highp float;
uniform highp sampler2D u_texture;
uniform highp sampler2D u_normal;
uniform vec2 u_texel;
uniform vec4 u_uv_bounds;
uniform int u_auto;
uniform int u_dark;
uniform vec2 u_viewport;
uniform vec4 u_light;
uniform vec4 u_light_color;
uniform mat2 u_basis;
uniform vec3 u_keys[8];
uniform vec3 u_values[8];
uniform int u_count;
varying vec2 v_uv;
varying vec4 v_color;
float alpha_at(vec2 uv) { return texture2D(u_texture,clamp(uv,u_uv_bounds.xy,u_uv_bounds.zw)).a; }
void main() {
  vec4 pixel=texture2D(u_texture,v_uv);
  vec3 n;
  if(u_auto!=0) {
    // Four extra taps only when the explicit opt-in fallback is active.
    float dx=alpha_at(v_uv+vec2(u_texel.x,0.0))-alpha_at(v_uv-vec2(u_texel.x,0.0));
    float dy=alpha_at(v_uv+vec2(0.0,u_texel.y))-alpha_at(v_uv-vec2(0.0,u_texel.y));
    n=normalize(vec3(-dx,dy,1.0));
  } else { n=normalize(texture2D(u_normal,v_uv).xyz*2.0-1.0); }
  vec2 p=vec2(gl_FragCoord.x,u_viewport.y-gl_FragCoord.y);
  vec2 delta=u_light.xy-p;
  float falloff=1.0-smoothstep(0.0,u_light.z,length(delta));
  n=vec3(u_basis*n.xy,n.z);
  float diffuse=max(dot(n,normalize(vec3(delta,u_light.z*0.35))),0.0);
  float gain=falloff*falloff*diffuse*u_light_color.a;
  for(int i=0;i<8;i++) {
    if(i<u_count && all(lessThan(abs(pixel.rgb-u_keys[i]),vec3(0.5/255.0)))) pixel.rgb=u_values[i];
  }
  // Dark-map normal lighting also only tints. Alpha and the darkness mask stay exact.
  if(u_dark!=0) pixel.rgb*=mix(vec3(1.0),u_light_color.rgb,gain);
  else pixel.rgb+=pixel.rgb*u_light_color.rgb*gain;
  gl_FragColor=pixel*v_color;
}
"#;
struct NormalImage {
    texture: Option<usize>,
    size: [u32; 2],
}
pub(super) struct Resources {
    radial: glow::Program,
    radial_viewport: Option<glow::UniformLocation>,
    normal: glow::Program,
    normal_uniforms: std::collections::HashMap<&'static str, Option<glow::UniformLocation>>,
    images: std::collections::HashMap<usize, NormalImage>,
}
impl Resources {
    pub(super) unsafe fn new(gl: &glow::Context, game: bool) -> Result<Self, String> {
        unsafe {
            let radial = compile_sources(gl, VERTEX, LIGHT_FRAGMENT)?;
            let normal = if game {
                let (v, f) = game_es300_sources_for(NORMAL_FRAGMENT);
                compile_sources(gl, &v, &f)?
            } else {
                compile_sources(gl, VERTEX, NORMAL_FRAGMENT)?
            };
            let normal_uniforms = [
                "u_screen_transform",
                "u_texture",
                "u_normal",
                "u_texel",
                "u_uv_bounds",
                "u_auto",
                "u_dark",
                "u_viewport",
                "u_light",
                "u_light_color",
                "u_basis",
                "u_keys",
                "u_values",
                "u_count",
            ]
            .into_iter()
            .map(|n| {
                (
                    n,
                    gl.get_uniform_location(
                        normal,
                        match n {
                            "u_keys" => "u_keys[0]",
                            "u_values" => "u_values[0]",
                            _ => n,
                        },
                    ),
                )
            })
            .collect();
            Ok(Self {
                radial,
                radial_viewport: gl.get_uniform_location(radial, "u_viewport"),
                normal,
                normal_uniforms,
                images: Default::default(),
            })
        }
    }
    pub(super) unsafe fn delete(&self, gl: &glow::Context) {
        unsafe {
            gl.delete_program(self.radial);
            gl.delete_program(self.normal);
        }
    }
}
impl Gles {
    pub fn upload_normal(
        &mut self,
        image: usize,
        normal: Option<&Image>,
        size: [u32; 2],
    ) -> Result<(), String> {
        let texture = normal
            .map(|n| self.upload_texture(n.width, n.height, &n.rgba))
            .transpose()?;
        self.lighting
            .images
            .insert(image, NormalImage { texture, size });
        Ok(())
    }
    /// At most 128 replacement draws; other quads keep the original batched path.
    /// Nearest contributing light per quad keeps fragment cost independent of emitter count.
    pub fn draw_lit_world(
        &mut self,
        quads: &[Quad],
        frame: &crate::lighting::Frame,
    ) -> Result<DrawCounts, String> {
        if frame.lights.iter().all(|l| l.intensity <= 0.0)
            || (!frame.auto_normals && self.lighting.images.values().all(|n| n.texture.is_none()))
        {
            return self.draw(quads);
        }
        let mut counts = DrawCounts::default();
        let mut first = 0;
        let mut used = 0;
        for (i, q) in quads.iter().enumerate() {
            let eligible = self
                .lighting
                .images
                .get(&q.image)
                .is_some_and(|n| n.texture.is_some() || frame.auto_normals);
            if !eligible || used >= 128 {
                continue;
            }
            let Some(light) = nearest_light(q, &frame.lights) else {
                continue;
            };
            let c = self.draw(&quads[first..i])?;
            counts.quads += c.quads;
            counts.batches += c.batches;
            counts.vertices += c.vertices;
            self.draw_normal(q, light, frame.dark_map)?;
            counts.quads += 1;
            counts.batches += 1;
            counts.vertices += 6;
            first = i + 1;
            used += 1;
        }
        let c = self.draw(&quads[first..])?;
        counts.quads += c.quads;
        counts.batches += c.batches;
        counts.vertices += c.vertices;
        Ok(counts)
    }
    fn draw_normal(
        &mut self,
        q: &Quad,
        light: &crate::lighting::Light,
        dark: bool,
    ) -> Result<(), String> {
        let image = &self.lighting.images[&q.image];
        let normal = image.texture;
        let size = image.size;
        let texture = self
            .placements
            .get(q.image)
            .ok_or("normal base image missing")?
            .standalone;
        if q.palette.len() > 8 {
            return Err("normal palette exceeds eight swaps".into());
        }
        self.vertices.clear();
        for i in self.rect_vertex_order {
            self.vertices.extend_from_slice(&[
                q.corners[i][0],
                q.corners[i][1],
                q.uv[i][0],
                q.uv[i][1],
                q.color[0],
                q.color[1],
                q.color[2],
                q.color[3],
            ]);
        }
        unsafe {
            let gl = &self.gl;
            let u = &self.lighting.normal_uniforms;
            gl.use_program(Some(self.lighting.normal));
            gl.uniform_matrix_4_f32_slice(
                u["u_screen_transform"].as_ref(),
                false,
                &game_screen_transform(self.width, self.height),
            );
            gl.active_texture(glow::TEXTURE0);
            gl.bind_texture(glow::TEXTURE_2D, Some(self.textures[texture]));
            gl.active_texture(glow::TEXTURE1);
            gl.bind_texture(
                glow::TEXTURE_2D,
                Some(self.textures[normal.unwrap_or(texture)]),
            );
            gl.uniform_1_i32(u["u_texture"].as_ref(), 0);
            gl.uniform_1_i32(u["u_normal"].as_ref(), 1);
            gl.uniform_1_i32(u["u_auto"].as_ref(), i32::from(normal.is_none()));
            gl.uniform_1_i32(u["u_dark"].as_ref(), i32::from(dark));
            gl.uniform_2_f32(
                u["u_texel"].as_ref(),
                1.0 / size[0] as f32,
                1.0 / size[1] as f32,
            );
            let bounds = uv_bounds(q, size);
            gl.uniform_4_f32(
                u["u_uv_bounds"].as_ref(),
                bounds[0],
                bounds[1],
                bounds[2],
                bounds[3],
            );
            gl.uniform_2_f32(
                u["u_viewport"].as_ref(),
                self.width as f32,
                self.height as f32,
            );
            gl.uniform_4_f32(
                u["u_light"].as_ref(),
                light.at[0],
                light.at[1],
                light.radius,
                0.0,
            );
            gl.uniform_4_f32(
                u["u_light_color"].as_ref(),
                light.color[0],
                light.color[1],
                light.color[2],
                light.intensity * 0.24,
            );
            gl.uniform_matrix_2_f32_slice(u["u_basis"].as_ref(), false, &normal_basis(q));
            let mut keys = [0.0; 24];
            let mut values = [0.0; 24];
            for (i, p) in q.palette.iter().enumerate() {
                for j in 0..3 {
                    keys[i * 3 + j] = p.from[j] as f32 / 255.0;
                    values[i * 3 + j] = p.to[j] as f32 / 255.0;
                }
            }
            gl.uniform_1_i32(u["u_count"].as_ref(), q.palette.len() as i32);
            gl.uniform_3_f32_slice(u["u_keys"].as_ref(), &keys);
            gl.uniform_3_f32_slice(u["u_values"].as_ref(), &values);
            self.submit();
            gl.active_texture(glow::TEXTURE0);
            self.fx_restore();
        }
        Ok(())
    }
    /// Bounded additive sprites. Dark maps use tint-only blending, not extra holes:
    /// source.rgb <= source.a implies output.rgb <= destination.rgb everywhere.
    pub fn lights(&mut self, frame: &crate::lighting::Frame) -> Result<DrawCounts, String> {
        self.vertices.clear();
        let mut sprites = 0;
        for l in &frame.lights {
            // Broad additive light plus a smaller prefiltered glow, submitted once.
            for (r, alpha) in [
                (l.radius, l.intensity * 0.12),
                (l.radius * 0.45, l.glow * 0.10),
            ] {
                if alpha <= 0.0 {
                    continue;
                }
                sprites += 1;
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
                        alpha,
                    ]);
                }
            }
        }
        if self.vertices.is_empty() {
            return Ok(DrawCounts::default());
        }
        unsafe {
            self.gl.use_program(Some(self.lighting.radial));
            self.gl.uniform_2_f32(
                self.lighting.radial_viewport.as_ref(),
                self.width as f32,
                self.height as f32,
            );
            self.fx_blend(frame.dark_map);
            self.submit();
            self.fx_restore();
        }
        self.check_error()?;
        Ok(DrawCounts {
            quads: sprites,
            batches: 1,
            vertices: sprites * 6,
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

fn nearest_light<'a>(
    q: &Quad,
    lights: &'a [crate::lighting::Light],
) -> Option<&'a crate::lighting::Light> {
    let lo = [
        q.corners.iter().map(|c| c[0]).fold(f32::INFINITY, f32::min),
        q.corners.iter().map(|c| c[1]).fold(f32::INFINITY, f32::min),
    ];
    let hi = [
        q.corners
            .iter()
            .map(|c| c[0])
            .fold(f32::NEG_INFINITY, f32::max),
        q.corners
            .iter()
            .map(|c| c[1])
            .fold(f32::NEG_INFINITY, f32::max),
    ];
    let d = |l: &crate::lighting::Light| {
        (l.at[0] - l.at[0].clamp(lo[0], hi[0])).powi(2)
            + (l.at[1] - l.at[1].clamp(lo[1], hi[1])).powi(2)
    };
    lights
        .iter()
        .filter(|l| l.intensity > 0.0 && d(l) < l.radius * l.radius)
        .min_by(|a, b| (d(a) / a.intensity).total_cmp(&(d(b) / b.intensity)))
}
fn uv_bounds(q: &Quad, size: [u32; 2]) -> [f32; 4] {
    let mut out = [0.0; 4];
    for axis in 0..2 {
        let lo = q.uv.iter().map(|v| v[axis]).fold(f32::INFINITY, f32::min);
        let hi =
            q.uv.iter()
                .map(|v| v[axis])
                .fold(f32::NEG_INFINITY, f32::max);
        let half = 0.5 / size[axis] as f32;
        out[axis] = (lo + half).min((lo + hi) / 2.0);
        out[axis + 2] = (hi - half).max((lo + hi) / 2.0);
    }
    out
}
// Solve d(screen)/d(uv); handles mirrors, rotations and Tiled transpose flags.
fn normal_basis(q: &Quad) -> [f32; 4] {
    let sub = |a: [f32; 2], b: [f32; 2]| [a[0] - b[0], a[1] - b[1]];
    let a = sub(q.uv[1], q.uv[0]);
    let b = sub(q.uv[3], q.uv[0]);
    let x = sub(q.corners[1], q.corners[0]);
    let y = sub(q.corners[3], q.corners[0]);
    let det = a[0] * b[1] - b[0] * a[1];
    if det.abs() < 1e-12 {
        return [1.0, 0.0, 0.0, -1.0];
    }
    let unit = |v: [f32; 2]| {
        let n = v[0].hypot(v[1]).max(1e-12);
        [v[0] / n, v[1] / n]
    };
    let u = unit([
        (x[0] * b[1] - y[0] * a[1]) / det,
        (x[1] * b[1] - y[1] * a[1]) / det,
    ]);
    let v = unit([
        (y[0] * a[0] - x[0] * b[0]) / det,
        (y[1] * a[0] - x[1] * b[0]) / det,
    ]);
    [u[0], u[1], -v[0], -v[1]]
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn normal_basis_tracks_tile_mirrors_and_transpose() {
        let mut q = Quad {
            image: 0,
            corners: [[0.0, 0.0], [32.0, 0.0], [32.0, 32.0], [0.0, 32.0]],
            uv: crate::geometry::UNIT_UV,
            color: [1.0; 4],
            palette: vec![],
        };
        assert_eq!(normal_basis(&q), [1.0, 0.0, 0.0, -1.0]);
        q.uv = q.uv.map(|[u, v]| [1.0 - u, v]);
        assert_eq!(normal_basis(&q), [-1.0, 0.0, 0.0, -1.0]);
        q.uv = crate::geometry::UNIT_UV.map(|[u, v]| [v, u]);
        assert_eq!(normal_basis(&q), [0.0, 1.0, -1.0, 0.0]);
        assert!(nearest_light(&q, &[]).is_none());
    }
}
