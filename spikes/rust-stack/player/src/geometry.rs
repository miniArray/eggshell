//! Drawing geometry only. It never supplies collision, activation or simulation state.
use crate::{
    binding::{Fill, Slices},
    gles::Quad,
    screen::{Plan, godot_round},
};
use eggshell_spike_core::PaletteSwap;

pub const UNIT_UV: [[f32; 2]; 4] = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]];
#[derive(Clone, Copy, Debug)]
pub struct Transform {
    pub position: [f64; 2],
    pub scale: [f64; 2],
    pub rotation: f64,
    pub origin: [f64; 2],
    pub flip: [bool; 2],
}
impl Default for Transform {
    fn default() -> Self {
        Self {
            position: [0.0; 2],
            scale: [1.0; 2],
            rotation: 0.0,
            origin: [0.0; 2],
            flip: [false; 2],
        }
    }
}
impl Transform {
    pub fn basis(&self, p: [f64; 2]) -> [f64; 2] {
        let (s, c) = self.rotation.to_radians().sin_cos();
        let x = p[0] * self.scale[0];
        let y = p[1] * self.scale[1];
        [c * x - s * y, s * x + c * y]
    }
    pub fn point(&self, p: [f64; 2]) -> [f64; 2] {
        let b = self.basis(p);
        [self.position[0] + b[0], self.position[1] + b[1]]
    }
    /// Semantic ratios multiply the selected frame/absolute-size binding first.
    pub fn ratio(mut self, ratio: Option<[f64; 2]>) -> Result<Self, String> {
        if let Some(ratio) = ratio {
            for (axis, value) in ratio.iter().enumerate() {
                if !value.is_finite() {
                    return Err("nonfinite presentation scale ratio".into());
                }
                self.scale[axis] *= value;
            }
        }
        Ok(self)
    }
    /// The exact pack_frames.gd opt-in dense-pixel transform policy.
    pub fn snap_dense(mut self, world_scale: f64) -> Self {
        for axis in 0..2 {
            let v = self.scale[axis] * world_scale;
            let sign = if v > 0.0 {
                1.0
            } else if v < 0.0 {
                -1.0
            } else {
                0.0
            };
            self.scale[axis] = sign * godot_round(v.abs()).max(1.0) / world_scale;
        }
        let corner = self.point([-self.origin[0], -self.origin[1]]);
        for (axis, c) in corner.iter().enumerate() {
            self.position[axis] += godot_round(c * world_scale) / world_scale - c;
        }
        self
    }
}
// This adapter keeps the source rectangle, local rectangle and transform explicit.
#[allow(clippy::too_many_arguments)]
pub fn rect_quad(
    image: usize,
    source: [f64; 4],
    texture_size: [f64; 2],
    local: [f64; 4],
    transform: Transform,
    plan: &Plan,
    color: [f32; 4],
    palette: &[PaletteSwap],
) -> Quad {
    let points = [
        [local[0], local[1]],
        [local[0] + local[2], local[1]],
        [local[0] + local[2], local[1] + local[3]],
        [local[0], local[1] + local[3]],
    ];
    let corners = points.map(|p| {
        let p = transform.point(p);
        [
            (p[0] * plan.scale + godot_round(plan.offset[0])) as f32,
            (p[1] * plan.scale + godot_round(plan.offset[1])) as f32,
        ]
    });
    let uv = UNIT_UV.map(|p| {
        let u = if transform.flip[0] { 1.0 - p[0] } else { p[0] };
        let v = if transform.flip[1] { 1.0 - p[1] } else { p[1] };
        [
            ((source[0] + u as f64 * source[2]) / texture_size[0]) as f32,
            ((source[1] + v as f64 * source[3]) / texture_size[1]) as f32,
        ]
    });
    Quad {
        image,
        corners,
        uv,
        color,
        palette: palette.to_vec(),
    }
}
pub fn sprite_quad(
    image: usize,
    size: [f64; 2],
    transform: Transform,
    plan: &Plan,
    color: [f32; 4],
    palette: &[PaletteSwap],
) -> Quad {
    rect_quad(
        image,
        [0.0, 0.0, size[0], size[1]],
        size,
        [-transform.origin[0], -transform.origin[1], size[0], size[1]],
        transform,
        plan,
        color,
        palette,
    )
}
pub fn tile_uv(source: [f64; 4], texture_size: [f64; 2], flags: u32) -> [[f32; 2]; 4] {
    UNIT_UV.map(|p| {
        let mut p = [p[0] as f64, p[1] as f64];
        if flags & 0x8000_0000 != 0 {
            p[0] = 1.0 - p[0];
        }
        if flags & 0x4000_0000 != 0 {
            p[1] = 1.0 - p[1];
        }
        if flags & 0x2000_0000 != 0 {
            p.swap(0, 1);
        }
        [
            ((source[0] + p[0] * source[2]) / texture_size[0]) as f32,
            ((source[1] + p[1] * source[3]) / texture_size[1]) as f32,
        ]
    })
}
pub fn visible(quad: &Quad, container: [f64; 2]) -> bool {
    let minx = quad
        .corners
        .iter()
        .map(|p| p[0])
        .fold(f32::INFINITY, f32::min);
    let maxx = quad
        .corners
        .iter()
        .map(|p| p[0])
        .fold(f32::NEG_INFINITY, f32::max);
    let miny = quad
        .corners
        .iter()
        .map(|p| p[1])
        .fold(f32::INFINITY, f32::min);
    let maxy = quad
        .corners
        .iter()
        .map(|p| p[1])
        .fold(f32::NEG_INFINITY, f32::max);
    maxx >= -2.0
        && maxy >= -2.0
        && minx <= container[0] as f32 + 2.0
        && miny <= container[1] as f32 + 2.0
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Patch {
    pub source: [f64; 4],
    pub destination: [f64; 4],
}
/// NinePatchRect's minimum margins and partial final tile; no stretched-art shortcut.
pub fn slices(size: [f64; 2], target: [f64; 2], cuts: Slices) -> Result<Vec<Patch>, String> {
    slices_uniform(size, target, cuts, [false; 2])
}
/// As `slices`, but a tiled middle band whose source columns (x) or rows (y) are all
/// identical is drawn as one stretched patch: the same pixels with one quad, not many.
pub fn slices_uniform(
    size: [f64; 2],
    target: [f64; 2],
    cuts: Slices,
    uniform: [bool; 2],
) -> Result<Vec<Patch>, String> {
    if size.iter().any(|v| *v <= 0.0 || !v.is_finite())
        || target.iter().any(|v| *v < 0.0 || !v.is_finite())
    {
        return Err("invalid nine-slice size".into());
    }
    let left = cuts.left.min(size[0]);
    let right = cuts.right.min(size[0]);
    let top = cuts.top.min(size[1]);
    let bottom = cuts.bottom.min(size[1]);
    if left + right > size[0] || top + bottom > size[1] {
        return Err("overlapping slice margins not admitted".into());
    }
    let target = [target[0].max(left + right), target[1].max(top + bottom)];
    let sx = [0.0, left, size[0] - right, size[0]];
    let sy = [0.0, top, size[1] - bottom, size[1]];
    let dx = [0.0, left, target[0] - right, target[0]];
    let dy = [0.0, top, target[1] - bottom, target[1]];
    let mut result = Vec::new();
    for y in 0..3 {
        for x in 0..3 {
            let sw = sx[x + 1] - sx[x];
            let sh = sy[y + 1] - sy[y];
            let dw = dx[x + 1] - dx[x];
            let dh = dy[y + 1] - dy[y];
            if sw <= 0.0 || sh <= 0.0 || dw <= 0.0 || dh <= 0.0 {
                continue;
            }
            let tile_x = x == 1 && cuts.fill == Fill::Tile && !uniform[0];
            let tile_y = y == 1 && cuts.fill == Fill::Tile && !uniform[1];
            let step_x = if tile_x { sw } else { dw };
            let step_y = if tile_y { sh } else { dh };
            let mut py = 0.0;
            while py < dh {
                let h = step_y.min(dh - py);
                let mut px = 0.0;
                while px < dw {
                    let w = step_x.min(dw - px);
                    result.push(Patch {
                        source: [
                            sx[x],
                            sy[y],
                            if tile_x { w } else { sw },
                            if tile_y { h } else { sh },
                        ],
                        destination: [dx[x] + px, dy[y] + py, w, h],
                    });
                    if result.len() > 100_000 {
                        return Err("nine-slice tessellation bound exceeded".into());
                    }
                    px += step_x;
                }
                py += step_y;
            }
        }
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn adjacent_fractional_terrain_quads_share_edges_and_cull_by_actual_extent() {
        for scale in [1.25, 1.5] {
            let p = crate::screen::plan(
                [640.0, 480.0],
                [2048.0, 448.0],
                [800.0, 224.0],
                1,
                scale - 1.0,
            )
            .unwrap();
            let tile = |x| {
                rect_quad(
                    0,
                    [0.0, 0.0, 32.0, 32.0],
                    [32.0; 2],
                    [x, 200.0, 32.0, 32.0],
                    Transform::default(),
                    &p,
                    [1.0; 4],
                    &[],
                )
            };
            let left = tile(768.0);
            let right = tile(800.0);
            assert_eq!(left.corners[1], right.corners[0]);
            assert_eq!(left.corners[2], right.corners[3]);
            assert_eq!(
                left.corners[1][0] - left.corners[0][0],
                (32.0 * scale) as f32
            );
            assert!(visible(&left, [640.0, 480.0]));
            assert!(!visible(&tile(0.0), [640.0, 480.0]));
        }
    }
    #[test]
    fn all_eight_tiled_transforms_are_permutations() {
        for flags in 0..8 {
            let uv = tile_uv([0.0, 0.0, 1.0, 1.0], [1.0, 1.0], flags << 29);
            for point in UNIT_UV {
                assert_eq!(uv.iter().filter(|p| **p == point).count(), 1);
            }
        }
    }
    #[test]
    fn source_transpose_order_is_inverse_of_h_v_d() {
        assert_eq!(
            tile_uv([0.0, 0.0, 1.0, 1.0], [1.0, 1.0], 0xa000_0000)[0],
            [0.0, 1.0]
        );
    }
    #[test]
    fn dense_negative_scale_keeps_anchor_pixels_integral() {
        let t = Transform {
            position: [0.3, -0.2],
            scale: [-0.9, 0.7],
            origin: [3.0, 7.0],
            ..Transform::default()
        }
        .snap_dense(2.0);
        let p = t.point([-3.0, -7.0]);
        assert_eq!(t.scale, [-1.0, 0.5]);
        assert_eq!(p[0] * 2.0, godot_round(p[0] * 2.0));
        assert_eq!(p[1] * 2.0, godot_round(p[1] * 2.0));
    }
    #[test]
    fn zero_scale_stays_zero_under_dense_snapping() {
        let t = Transform {
            scale: [0.0, -0.0],
            ..Transform::default()
        }
        .snap_dense(4.0);
        assert_eq!(t.scale, [0.0, 0.0]);
    }
    #[test]
    fn semantic_ratio_follows_absolute_size_and_preserves_anchor() {
        let t = Transform {
            position: [9.0, 17.0],
            scale: [-2.0, 0.5],
            origin: [16.0, 32.0],
            ..Transform::default()
        };
        assert_eq!(t.ratio(None).unwrap().scale, t.scale);
        assert_eq!(t.ratio(Some([1.0, 1.0])).unwrap().scale, t.scale);
        let scaled = t.ratio(Some([1.5, 0.5])).unwrap();
        assert_eq!(scaled.scale, [-3.0, 0.25]);
        assert_eq!(scaled.position, t.position);
        assert_eq!(scaled.origin, t.origin);
        assert!(t.ratio(Some([f64::NAN, 1.0])).is_err());
    }
    #[test]
    fn tiled_slices_cover_without_gaps_or_scaled_caps() {
        let p = slices(
            [10.0, 10.0],
            [27.0, 18.0],
            Slices {
                left: 2.0,
                right: 2.0,
                top: 2.0,
                bottom: 2.0,
                fill: Fill::Tile,
            },
        )
        .unwrap();
        assert_eq!(
            p.iter()
                .map(|p| p.destination[2] * p.destination[3])
                .sum::<f64>(),
            27.0 * 18.0
        );
        for p in p {
            assert_eq!(p.source[2], p.destination[2]);
            assert_eq!(p.source[3], p.destination[3]);
        }
    }
}
