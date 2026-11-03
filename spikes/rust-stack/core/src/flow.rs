//! water_flow.gd: the `flowWater` tilemap's tiles push the player; and moves.gd _snow:
//! the `snow64` tilemap under the feet makes the player slide.
use crate::{body::Probe, math::floor_div, player::Player, Map, Position, SCALE as S};
pub(crate) const DOWN: u8 = 1;
pub(crate) const LEFT: u8 = 2;
pub(crate) const RIGHT: u8 = 4;
pub(crate) const LEFT_DOWN: u8 = 8;
pub(crate) const RIGHT_DOWN: u8 = 16;
const LOW: &[f64] = &[0.0, 0.5625, 1.0, 0.5625, 1.0, 1.0, 0.0, 1.0];
const FULL: &[f64] = &[0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];
const LEFT_SLOPE: &[f64] = &[0.0, 0.375, 0.375, 0.0, 1.0, 0.0, 0.0, 1.0];
const RIGHT_SLOPE: &[f64] = &[0.625, 0.0, 1.0, 0.375, 1.0, 1.0, 0.0, 0.0];
/// Pushes in 1/3600 px per step: 96 px/s along a flat flow, 200 px/s down a slope.
const PUSH: i64 = 96 * S / 60;
const SLOPE_PUSH: i64 = 200 * S / 60;
/// Tiled's flip bits (level_code.gd TILE_ID_MASK keeps the rest).
const TILE_ID_MASK: i64 = 0x1fff_ffff;

/// water_flow.gd SHAPES: flowWater tile id -> (kind, tile shape).
fn shape(id: i64) -> Option<(u8, &'static [f64])> {
    Some(match id {
        0 => (DOWN, LOW),
        1 | 12 => (DOWN, FULL),
        2 => (DOWN, &[0.0, 0.5, 0.5, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0]),
        3 => (DOWN, &[0.0, 0.0, 0.5, 0.0, 1.0, 0.5, 1.0, 1.0, 0.0, 1.0]),
        4 | 15 => (LEFT, LOW),
        8 | 16 => (RIGHT, LOW),
        6 | 7 => (LEFT_DOWN, LEFT_SLOPE),
        10 | 11 => (RIGHT_DOWN, RIGHT_SLOPE),
        _ => return None,
    })
}

/// world.gd tile_polygon for an unflipped cell of `size` px: physical vertices are
/// quantized once.
fn points(shape: &[f64], size: i64) -> Vec<Position> {
    shape
        .chunks(2)
        .map(|c| Position {
            x: (c[0] * (size * S) as f64).round() as i64,
            y: (c[1] * (size * S) as f64).round() as i64,
        })
        .collect()
}

/// water_flow.gd kinds: the flow kinds (bit set) the box touches.
pub(crate) fn kinds(map: &Map, [left, top, right, bottom]: [i64; 4]) -> u8 {
    let mut found = 0;
    for layer in map.layers.iter().filter(|l| l.tilemap == "flowWater") {
        let size = layer.tile_size_pixels * S;
        let cell = |v: i64| floor_div(v, size).unwrap_or(0);
        let x0 = cell(left - 1).max(0);
        let x1 = cell(right).min(layer.width as i64 - 1);
        let y0 = cell(top - 1).max(0);
        let y1 = cell(bottom).min(layer.height as i64 - 1);
        for row in y0..=y1 {
            for column in x0..=x1 {
                let id = i64::from(layer.cells[row as usize * layer.width + column as usize])
                    & TILE_ID_MASK;
                let Some((kind, tile)) = shape(id) else {
                    continue;
                };
                if found & kind != 0 {
                    continue;
                }
                let (ox, oy) = (column * size, row * size);
                if crate::polygon::overlaps_box(
                    &points(tile, layer.tile_size_pixels),
                    [left - ox, top - oy, right - ox, bottom - oy],
                ) {
                    found |= kind;
                }
            }
        }
    }
    found
}

/// world.gd named_overlaps: a tilemap by name in layer1 or layer2 overlaps the box.
pub(crate) fn named_overlaps(map: &Map, name: &str, box_: [i64; 4]) -> bool {
    map.layers
        .iter()
        .any(|l| l.tilemap == name && l.source_layer != "layer3" && l.overlaps_box(box_))
}

/// moves.gd _snow: snow64 terrain 4 px under the box (2 px while already sliding).
pub(crate) fn on_snow(map: &Map, box_: [i64; 4], sliding: bool) -> bool {
    let offset = if sliding { 2 * S } else { 4 * S };
    let probe = [box_[0], box_[1] + offset, box_[2], box_[3] + offset];
    map.layers
        .iter()
        .any(|l| l.tilemap == "snow64" && l.overlaps_box(probe))
}

impl Player {
    /// collision.gd by_wall (reach 1, lift 1).
    fn by_wall(&self, map: &Probe, b: [i64; 4], direction: i64) -> bool {
        self.body.overlaps(map, b, direction * S, 0)
            && self.body.overlaps(map, b, direction * S, -S)
    }
    /// water_flow.gd apply. Returns -1 or 1 when a jump press leaves a sloped flow that
    /// way, else 0.
    /// A frozen step reads the flow kinds and the jump press but does not push the body.
    pub(crate) fn flow(
        &mut self,
        map: &Probe,
        b: [i64; 4],
        pressed: u8,
        pounding: bool,
        frozen: bool,
    ) -> i64 {
        let p = self.body;
        let box_ = [p.x + b[0], p.y + b[1], p.x + b[2], p.y + b[3]];
        let touching = kinds(map, box_);
        let below = kinds(map, [box_[0], box_[1] + 4 * S, box_[2], box_[3] + 4 * S]);
        if touching | below == 0 {
            return 0;
        }
        if !frozen && touching & DOWN != 0 && !pounding && self.on_floor == 0 {
            self.body.vy += 384;
        }
        if !frozen && touching & LEFT != 0 && !self.by_wall(map, b, -1) {
            self.body.x -= PUSH;
        }
        if !frozen && touching & RIGHT != 0 && !self.by_wall(map, b, 1) {
            self.body.x += PUSH;
        }
        let mut jump = 0;
        for kind in [LEFT_DOWN, RIGHT_DOWN] {
            // Touching it, or 4 px above it (an OR block).
            if (touching | below) & kind == 0 {
                continue;
            }
            let way = if kind == LEFT_DOWN { -1 } else { 1 };
            if !frozen && self.body.vx * way < 0 {
                // Moving against the slope loses half the speed.
                self.body.x -= self.body.vx / 2;
            }
            if pressed & 4 != 0 {
                jump = way;
            }
            if !frozen && !self.by_wall(map, b, way) {
                self.body.x += way * SLOPE_PUSH;
            }
            if self.body.vy >= 0 {
                self.body.vy = 400 * 60;
            }
        }
        jump
    }
}
