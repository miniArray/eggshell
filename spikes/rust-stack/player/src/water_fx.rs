//! Drawing-only water geometry. Reads compiled contacts, never changes membership.
use crate::{
    gles::Quad,
    screen::{self, Plan},
};
use eggshell_spike_core::{SCALE, TileLayer};
use std::collections::HashMap;

/// Half-open world/screen rectangle: left, top, right, bottom.
pub type Rect = [f64; 4];
#[derive(Default)]
pub struct Water {
    regions: Vec<Rect>,
    surfaces: Vec<Rect>,
}
impl Water {
    pub fn prepare(layers: &[TileLayer]) -> Result<Self, String> {
        let mut contacts = Vec::new();
        let mut tiles = Vec::new();
        for layer in layers.iter().filter(|l| l.water) {
            let size = layer.tile_size_pixels as f64;
            let polygons: HashMap<_, _> = layer
                .collision
                .iter()
                .map(|c| (c.cell, &c.polygon))
                .collect();
            for (i, cell) in layer.cells.iter().enumerate().filter(|(_, c)| **c != -1) {
                let Some(p) = polygons.get(cell).filter(|p| !p.is_empty()) else {
                    continue;
                };
                let x = (i % layer.width) as f64 * size;
                let y = (i / layer.width) as f64 * size;
                let mut b = [
                    f64::INFINITY,
                    f64::INFINITY,
                    f64::NEG_INFINITY,
                    f64::NEG_INFINITY,
                ];
                for point in p.iter() {
                    let px = point.x as f64 / SCALE as f64;
                    let py = point.y as f64 / SCALE as f64;
                    b[0] = b[0].min(px);
                    b[1] = b[1].min(py);
                    b[2] = b[2].max(px);
                    b[3] = b[3].max(py);
                }
                // All shipped water contacts are rectangles, including water3's
                // ten-pixel dry cap and transformed cells. Never approximate a slope.
                if p.len() != 4
                    || p.iter().enumerate().any(|(i, a)| {
                        let z = p[(i + 1) % 4];
                        (a.x != z.x && a.y != z.y)
                            || ![b[0], b[2]].contains(&(a.x as f64 / SCALE as f64))
                            || ![b[1], b[3]].contains(&(a.y as f64 / SCALE as f64))
                    })
                {
                    return Err(format!(
                        "water FX requires rectangular contact: {} cell {cell}",
                        layer.tilemap
                    ));
                }
                contacts.push([x + b[0], y + b[1], x + b[2], y + b[3]]);
                tiles.push([x, y, x + size, y + size]);
            }
        }
        let mut surfaces = Vec::new();
        for (r, tile) in contacts.iter().zip(&tiles) {
            let mut spans = vec![(r[0], r[2])];
            // Adjacency is by water tile, not by its inset polygon. Otherwise an
            // inset water3 tile would invent a new surface on every submerged row.
            for above in tiles.iter().filter(|a| a[1] < tile[1] && a[3] >= tile[1]) {
                spans = spans
                    .into_iter()
                    .flat_map(|(l, h)| {
                        [(l, h.min(above[0])), (l.max(above[2]), h)]
                            .into_iter()
                            .filter(|(a, b)| a < b)
                    })
                    .collect();
            }
            for (l, h) in spans {
                surfaces.push([l, r[1], h, r[1] + 1.0]);
            }
        }
        Ok(Self {
            regions: union(&contacts),
            surfaces: union(&surfaces),
        })
    }
    pub fn frame(&self, plan: &Plan, container: [f64; 2], tick: i64, strength: i64) -> Frame {
        let strength = strength.clamp(0, 3) as f32;
        if strength == 0.0 {
            return Frame::default();
        }
        Frame {
            regions: self
                .regions
                .iter()
                .filter_map(|r| project(*r, plan, container))
                .collect(),
            surfaces: self
                .surfaces
                .iter()
                .filter_map(|r| project(*r, plan, container))
                .collect(),
            phase: phase(tick),
            strength,
            scale: plan.scale as f32,
            offset: plan.offset.map(|v| screen::godot_round(v) as f32),
            container,
        }
    }
}
#[derive(Default)]
pub struct Frame {
    pub regions: Vec<Rect>,
    surfaces: Vec<Rect>,
    pub phase: f32,
    pub strength: f32,
    pub scale: f32,
    pub offset: [f32; 2],
    container: [f64; 2],
}
impl Frame {
    /// Bounding copy area in top-left screen pixels. All rectangles were clipped
    /// to the actual drawable; round outward to include every sampled texel.
    pub fn copy_bounds(&self) -> Option<[i32; 4]> {
        let first = *self.regions.first()?;
        let b = self.regions.iter().fold(first, |a, r| {
            [
                a[0].min(r[0]),
                a[1].min(r[1]),
                a[2].max(r[2]),
                a[3].max(r[3]),
            ]
        });
        let l = b[0].floor() as i32;
        let t = b[1].floor() as i32;
        Some([l, t, b[2].ceil() as i32 - l, b[3].ceil() as i32 - t])
    }

    pub fn emit_surface(&self, solid: usize, out: &mut Vec<Quad>) {
        // Existing white fallback + alpha: no new art/filtering or palette.
        // Two-pixel steps and a one-pixel line keep the surface pixel-art friendly.
        for r in &self.surfaces {
            let mut x = (r[0] / 2.0).floor() * 2.0;
            while x < r[2] {
                let world_x = (x as f32 - self.offset[0]) / self.scale;
                let wave = ((world_x * 0.16 + self.phase).sin() * self.strength / 3.0 + 1.0).round()
                    as f64;
                let left = x.max(r[0]);
                let right = (x + 2.0).min(r[2]);
                let top = r[1] + wave;
                if let Some([l, t, r, b]) = clip(
                    [left, top, right, top + 1.0],
                    [0.0, 0.0, self.container[0], self.container[1]],
                ) {
                    out.push(Quad {
                        image: solid,
                        corners: [
                            [l as f32, t as f32],
                            [r as f32, t as f32],
                            [r as f32, b as f32],
                            [l as f32, b as f32],
                        ],
                        uv: crate::geometry::UNIT_UV,
                        color: [1.0, 1.0, 1.0, 0.08 * self.strength],
                        palette: Vec::new(),
                    });
                }
                x += 2.0;
            }
        }
    }
}
/// Bounded before conversion to float: replay, pause and very large saved ticks agree.
pub fn phase(tick: i64) -> f32 {
    tick.rem_euclid(360) as f32 * (std::f32::consts::TAU / 360.0)
}
fn project(r: Rect, plan: &Plan, container: [f64; 2]) -> Option<Rect> {
    clip(
        [
            r[0] * plan.scale + screen::godot_round(plan.offset[0]),
            r[1] * plan.scale + screen::godot_round(plan.offset[1]),
            r[2] * plan.scale + screen::godot_round(plan.offset[0]),
            r[3] * plan.scale + screen::godot_round(plan.offset[1]),
        ],
        [0.0, 0.0, container[0], container[1]],
    )
}
pub fn clip(r: Rect, bounds: Rect) -> Option<Rect> {
    let r = [
        r[0].max(bounds[0]),
        r[1].max(bounds[1]),
        r[2].min(bounds[2]),
        r[3].min(bounds[3]),
    ];
    (r[0] < r[2] && r[1] < r[3]).then_some(r)
}
/// Scanline union gives disjoint rectangles even when multiple water layers overlap.
fn union(rects: &[Rect]) -> Vec<Rect> {
    let mut ys: Vec<_> = rects.iter().flat_map(|r| [r[1], r[3]]).collect();
    ys.sort_by(f64::total_cmp);
    ys.dedup();
    let mut out: Vec<Rect> = Vec::new();
    for y in ys.windows(2) {
        let mut spans: Vec<_> = rects
            .iter()
            .filter(|r| r[1] <= y[0] && r[3] >= y[1])
            .map(|r| (r[0], r[2]))
            .collect();
        spans.sort_by(|a, b| a.0.total_cmp(&b.0));
        let mut merged: Vec<(f64, f64)> = Vec::new();
        for (l, h) in spans {
            if let Some(last) = merged.last_mut().filter(|last| l <= last.1) {
                last.1 = last.1.max(h);
            } else {
                merged.push((l, h));
            }
        }
        for (l, h) in merged {
            if let Some(last) = out
                .iter_mut()
                .rev()
                .find(|r| r[0] == l && r[2] == h && r[3] == y[0])
            {
                last[3] = y[1];
            } else {
                out.push([l, y[0], h, y[1]]);
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    fn lagoon() -> eggshell_spike_core::World {
        let collision = serde_json::json!({"version":2,"tilemaps": {
            "castle32": {"tile_size":[32,32],"solid_family":true,"water_family":false,"collision_disabled":[]},
            "water3": {"tile_size":[32,32],"solid_family":false,"water_family":true,"collision_disabled":[],"collision_polygons":{"0":[0,0.3125,1,0.3125,1,1,0,1]}}
        }});
        eggshell_spike_core::World::compile(
            include_str!("../../../../tests/fixtures/lagoon.level.json"),
            &collision.to_string(),
        )
        .unwrap()
    }
    #[test]
    fn lagoon_surface_uses_contact_cap_and_only_top_row() {
        let world = lagoon();
        let water = Water::prepare(&world.maps[0].layers).unwrap();
        assert_eq!(water.surfaces, vec![[1024.0, 330.0, 1792.0, 331.0]]);
        assert_eq!(water.regions.len(), 4);
        assert_eq!(water.regions[0], [1024.0, 330.0, 1792.0, 352.0]);
        let plan = screen::plan([640.0, 480.0], [2048.0, 448.0], [1408.0, 224.0], 1, 0).unwrap();
        let a = water.frame(&plan, [640.0, 480.0], 90, 2);
        let b = water.frame(&plan, [640.0, 480.0], 90, 2);
        let mut qa = Vec::new();
        let mut qb = Vec::new();
        a.emit_surface(1, &mut qa);
        b.emit_surface(1, &mut qb);
        assert!(!qa.is_empty());
        assert_eq!(qa, qb);
        assert!(water.frame(&plan, [640.0, 480.0], 90, 0).regions.is_empty());
    }
    #[test]
    fn disabled_contacts_and_layer_three_are_not_water() {
        let mut world = lagoon();
        let layers = &mut world.maps[0].layers;
        for l in layers.iter_mut().filter(|l| l.water) {
            for c in &mut l.collision {
                c.polygon.clear();
            }
        }
        assert!(Water::prepare(layers).unwrap().regions.is_empty());
        for l in layers.iter_mut() {
            l.water = false;
        }
        assert!(Water::prepare(layers).unwrap().surfaces.is_empty());
    }
    #[test]
    fn overlapping_regions_are_disjoint_and_holes_survive() {
        assert_eq!(
            union(&[
                [0.0, 0.0, 32.0, 32.0],
                [16.0, 0.0, 48.0, 32.0],
                [0.0, 32.0, 48.0, 64.0]
            ]),
            vec![[0.0, 0.0, 48.0, 64.0]]
        );
        assert_eq!(
            union(&[[0.0, 0.0, 10.0, 10.0], [20.0, 0.0, 30.0, 10.0]]).len(),
            2
        );
    }
    #[test]
    fn snapshot_bounds_cover_only_visible_water_and_round_outward() {
        let mut frame = Frame::default();
        assert_eq!(frame.copy_bounds(), None);
        frame.regions = vec![[4.2, 7.1, 20.3, 30.2], [40.0, 10.0, 60.0, 20.0]];
        assert_eq!(frame.copy_bounds(), Some([4, 7, 56, 24]));
    }
    #[test]
    fn clipping_excludes_touching_edges() {
        assert_eq!(
            clip([-10.0, -5.0, 20.0, 30.0], [0.0, 0.0, 10.0, 20.0]),
            Some([0.0, 0.0, 10.0, 20.0])
        );
        assert_eq!(clip([10.0, 0.0, 20.0, 10.0], [0.0, 0.0, 10.0, 20.0]), None);
    }
    #[test]
    fn phase_is_saved_tick_only_and_periodic() {
        assert_eq!(phase(91), phase(91));
        assert_eq!(phase(91), phase(451));
        assert_ne!(phase(91), phase(92));
        assert_eq!(phase(i64::MAX), phase(i64::MAX % 360));
    }
}
