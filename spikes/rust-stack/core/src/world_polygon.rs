//! Polygon-body terrain contact for the companion bubble, with closed edges.
use crate::{math::floor_div, polygon, Map, Position, SCALE};
impl Map {
    pub(crate) fn terrain_polygon_overlaps(&self, points: &[Position], bounds: [i64; 4]) -> bool {
        for layer in &self.layers {
            if !layer.solid {
                continue;
            }
            let size = layer.tile_size_pixels * SCALE;
            let x0 = floor_div(bounds[0] - 1, size).unwrap_or(0).max(0);
            let y0 = floor_div(bounds[1] - 1, size).unwrap_or(0).max(0);
            let x1 = floor_div(bounds[2], size)
                .unwrap_or(-1)
                .min(layer.width as i64 - 1);
            let y1 = floor_div(bounds[3], size)
                .unwrap_or(-1)
                .min(layer.height as i64 - 1);
            for row in y0..=y1 {
                for col in x0..=x1 {
                    let cell = layer.cells[row as usize * layer.width + col as usize];
                    let Some(contact) = layer.collision.iter().find(|c| c.cell == cell) else {
                        continue;
                    };
                    if contact.polygon.is_empty() {
                        continue;
                    }
                    let local: Vec<_> = points
                        .iter()
                        .map(|p| Position {
                            x: p.x - col * size,
                            y: p.y - row * size,
                        })
                        .collect();
                    if polygon::overlaps_polygon(&local, &contact.polygon) {
                        return true;
                    }
                }
            }
        }
        false
    }
}
