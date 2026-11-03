//! Immutable union broad phase. One byte per cell; sparse exact polygons at edges.
use crate::{polygon, Map, Position, TerrainHazard, TileLayer, SCALE};
use std::collections::HashMap;
pub(crate) const SOLID: u8 = 1;
pub(crate) const WATER: u8 = 2;
pub(crate) const LAVA: u8 = 4;
pub(crate) const SPIKES: u8 = 8;
#[derive(Clone, Debug, PartialEq, Eq)]
struct Contact {
    layer: usize,
    polygon: usize,
    origin: Position,
    size: i64,
    classes: u8,
}
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct Grid {
    size: i64,
    width: usize,
    height: usize,
    flags: Vec<u8>,
    partial: HashMap<u32, Vec<Contact>>,
}
pub(crate) fn classes(l: &TileLayer) -> u8 {
    (u8::from(l.solid) * SOLID)
        | (u8::from(l.water) * WATER)
        | match l.hazard {
            TerrainHazard::None => 0,
            TerrainHazard::Lava => LAVA,
            TerrainHazard::Spikes => SPIKES,
        }
}
fn square(p: &[Position], size: i64) -> bool {
    p.len() == 4
        && p.iter()
            .all(|p| [0, size].contains(&p.x) && [0, size].contains(&p.y))
        && (0..4)
            .all(|i| (p[i].x - p[(i + 1) % 4].x).abs() + (p[i].y - p[(i + 1) % 4].y).abs() == size)
        && (0..4).all(|i| (i + 1..4).all(|j| p[i] != p[j]))
}
/// Equals `v.div_euclid(s)` for s > 0. `inv` is `1.0 / s as f64`.
fn fast_floor_div(v: i64, s: i64, inv: f64) -> i64 {
    // Up to 2^52, v is exact in f64, the truncated estimate is within a step or
    // two of the answer, and q*s stays near v, so the i64 products cannot
    // overflow. Beyond that, use the exact division.
    const LIMIT: i64 = 1 << 52;
    if !(-LIMIT..=LIMIT).contains(&v) || s > LIMIT {
        return v.div_euclid(s);
    }
    let mut q = (v as f64 * inv) as i64;
    while q * s > v {
        q -= 1;
    }
    while (q + 1) * s <= v {
        q += 1;
    }
    q
}
#[cfg(test)]
#[test]
fn fast_floor_div_equals_div_euclid() {
    let mut x = 0x9e37_79b9_7f4a_7c15_u64;
    let mut next = || {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        x
    };
    for s in [1_i64, 3600, 32 * 3600, 64 * 3600, 7, 1 << 20] {
        let inv = 1.0 / s as f64;
        for v in [
            0,
            1,
            -1,
            s,
            -s,
            s - 1,
            1 - s,
            i64::MAX,
            i64::MIN,
            i64::MAX / 16384,
            -(i64::MAX / 16384),
        ] {
            assert_eq!(fast_floor_div(v, s, inv), v.div_euclid(s), "{v} {s}");
        }
        for _ in 0..200_000 {
            let r = next();
            let v = match r % 3 {
                0 => (r as i64) >> 16,
                1 => (r as i64) >> 40,
                _ => r as i64,
            };
            assert_eq!(fast_floor_div(v, s, inv), v.div_euclid(s), "{v} {s}");
            let k = ((r >> 8) % 100_000) as i64 - 50_000;
            for e in [k * s - 1, k * s, k * s + 1] {
                assert_eq!(fast_floor_div(e, s, inv), e.div_euclid(s), "{e} {s}");
            }
        }
    }
}
fn meet(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] <= b[2] && a[2] >= b[0] && a[1] <= b[3] && a[3] >= b[1]
}
impl Grid {
    pub fn build(layers: &[TileLayer]) -> Self {
        let active: Vec<_> = layers.iter().filter(|l| classes(l) != 0).collect();
        if active.is_empty() {
            return Self::default();
        }
        let mut size = active
            .iter()
            .map(|l| l.tile_size_pixels * SCALE)
            .min()
            .unwrap();
        let extent = [
            active
                .iter()
                .map(|l| l.width as i64 * l.tile_size_pixels * SCALE)
                .max()
                .unwrap(),
            active
                .iter()
                .map(|l| l.height as i64 * l.tile_size_pixels * SCALE)
                .max()
                .unwrap(),
        ];
        let mut width = ((extent[0] + size - 1) / size) as usize;
        let mut height = ((extent[1] + size - 1) / size) as usize;
        while width.saturating_mul(height) > 4_000_000 {
            size *= 2;
            width = ((extent[0] + size - 1) / size) as usize;
            height = ((extent[1] + size - 1) / size) as usize;
        }
        let mut grid = Self {
            size,
            width,
            height,
            flags: vec![0; width * height],
            partial: HashMap::new(),
        };
        for (li, l) in layers.iter().enumerate() {
            let class = classes(l);
            if class == 0 {
                continue;
            }
            let ts = l.tile_size_pixels * SCALE;
            for (i, &cell) in l.cells.iter().enumerate() {
                if cell == -1 {
                    continue;
                }
                let Some(&pi) = l.collision_index.get(&cell) else {
                    continue;
                };
                let p = &l.collision[pi].polygon;
                if p.is_empty() {
                    continue;
                }
                let origin = Position {
                    x: (i % l.width) as i64 * ts,
                    y: (i / l.width) as i64 * ts,
                };
                let full = square(p, ts);
                for y in origin.y / size..=(origin.y + ts - 1) / size {
                    for x in origin.x / size..=(origin.x + ts - 1) / size {
                        let key = y as usize * width + x as usize;
                        if full
                            && x * size >= origin.x
                            && (x + 1) * size <= origin.x + ts
                            && y * size >= origin.y
                            && (y + 1) * size <= origin.y + ts
                        {
                            grid.flags[key] |= class;
                        } else {
                            grid.flags[key] |= class << 4;
                            grid.partial.entry(key as u32).or_default().push(Contact {
                                layer: li,
                                polygon: pi,
                                origin,
                                size: ts,
                                classes: class,
                            });
                        }
                    }
                }
            }
        }
        grid.partial.retain(|key, contacts| {
            let full = grid.flags[*key as usize] & 15;
            contacts.retain_mut(|c| {
                c.classes &= !full;
                c.classes != 0
            });
            let bits = contacts.iter().fold(0, |bits, c| bits | c.classes);
            grid.flags[*key as usize] = full | (bits << 4);
            !contacts.is_empty()
        });
        grid
    }
    fn range(&self, b: [i64; 4]) -> Option<[i64; 4]> {
        if self.size == 0 {
            return None;
        }
        let s = self.size;
        // Floor division without four 64-bit divides: an f64 estimate, then an
        // exact integer correction in i128, equals div_euclid for s > 0.
        let inv = 1.0 / s as f64;
        let d = |v: i64| fast_floor_div(v, s, inv);
        Some([
            d(b[0].saturating_sub(1)).max(0),
            d(b[1].saturating_sub(1)).max(0),
            d(b[2]).min(self.width as i64 - 1),
            d(b[3]).min(self.height as i64 - 1),
        ])
    }
    pub fn overlaps(&self, map: &Map, b: [i64; 4], class: u8) -> bool {
        if b[0] > b[2]
            || b[1] > b[3]
            || b.iter()
                .any(|v| v.unsigned_abs() > (i64::MAX / 16384) as u64)
        {
            return map
                .layers
                .iter()
                .any(|l| classes(l) & class != 0 && l.overlaps_box(b));
        }
        let Some([x0, y0, x1, y1]) = self.range(b) else {
            return false;
        };
        for y in y0..=y1 {
            for x in x0..=x1 {
                let key = y as usize * self.width + x as usize;
                let flags = self.flags[key];
                if flags & class != 0 {
                    return true;
                }
                if flags & (class << 4) == 0 {
                    continue;
                }
                for c in &self.partial[&(key as u32)] {
                    if c.classes & class == 0
                        || !meet(
                            b,
                            [
                                c.origin.x,
                                c.origin.y,
                                c.origin.x + c.size,
                                c.origin.y + c.size,
                            ],
                        )
                    {
                        continue;
                    }
                    if polygon::overlaps_box(
                        &map.layers[c.layer].collision[c.polygon].polygon,
                        [
                            b[0] - c.origin.x,
                            b[1] - c.origin.y,
                            b[2] - c.origin.x,
                            b[3] - c.origin.y,
                        ],
                    ) {
                        return true;
                    }
                }
            }
        }
        false
    }
    pub fn polygon(&self, map: &Map, points: &[Position], b: [i64; 4]) -> bool {
        let Some([x0, y0, x1, y1]) = self.range(b) else {
            return false;
        };
        for y in y0..=y1 {
            for x in x0..=x1 {
                let key = y as usize * self.width + x as usize;
                let flags = self.flags[key];
                if flags & SOLID != 0
                    && polygon::overlaps_box(
                        points,
                        [
                            x * self.size,
                            y * self.size,
                            (x + 1) * self.size,
                            (y + 1) * self.size,
                        ],
                    )
                {
                    return true;
                }
                if flags & (SOLID << 4) == 0 {
                    continue;
                }
                for c in &self.partial[&(key as u32)] {
                    if c.classes & SOLID == 0
                        || !meet(
                            b,
                            [
                                c.origin.x,
                                c.origin.y,
                                c.origin.x + c.size,
                                c.origin.y + c.size,
                            ],
                        )
                    {
                        continue;
                    }
                    let local: Vec<_> = points
                        .iter()
                        .map(|p| Position {
                            x: p.x - c.origin.x,
                            y: p.y - c.origin.y,
                        })
                        .collect();
                    if polygon::overlaps_polygon(
                        &local,
                        &map.layers[c.layer].collision[c.polygon].polygon,
                    ) {
                        return true;
                    }
                }
            }
        }
        false
    }
    pub fn metrics(&self) -> (usize, usize, usize) {
        (
            self.flags.len(),
            self.partial.len(),
            self.partial.values().map(Vec::len).sum(),
        )
    }
}
