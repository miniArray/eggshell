//! Per-step collision projection. Saved entity state remains in the ordered row table.
use crate::{
    body::Body,
    entity::{Entity, Kind},
    math::floor_div,
    Position, SCALE as S,
};
#[cfg(test)]
#[derive(Clone, Debug, Default, PartialEq, serde::Deserialize)]
pub(crate) struct SolidTrace {
    pub saved_frame: i64,
    pub rows: Vec<SolidRecord>,
    pub floor_token: i64,
    pub polygon_box_probes: Vec<bool>,
}
#[cfg(test)]
#[derive(Clone, Debug, PartialEq, serde::Deserialize)]
pub(crate) struct SolidRecord {
    pub token: i64,
    pub old_position: [i64; 2],
    pub live_position: [i64; 2],
    pub old_box: Option<[i64; 4]>,
    pub live_box: Option<[i64; 4]>,
}
const CELL: i64 = 128 * S;
#[derive(Clone, Debug)]
struct Row {
    token: i64,
    spiked: i64,
    position: Position,
    old_position: Position,
    old_box: Option<[i64; 4]>,
    live_box: Option<[i64; 4]>,
    region: [i64; 4],
    handle: Option<i64>,
}
#[derive(Clone, Copy, Debug)]
pub(crate) struct Shape {
    pub handle: i64,
    pub box_: [i64; 4],
}
#[derive(Clone, Copy, Debug)]
pub(crate) struct PostUpdate {
    pub token: i64,
    pub strike_box: [i64; 4],
    pub height: i64,
    pub status: i64,
}
#[derive(Default, Debug)]
pub(crate) struct SolidFrame {
    rows: Vec<Row>,
    handles: Vec<usize>,
    carried: bool,
    bumped: std::collections::BTreeSet<i64>,
    updates: Vec<PostUpdate>,
}
fn overlap(a: [i64; 4], b: [i64; 4]) -> bool {
    a[2] >= b[0] && a[0] <= b[2] && a[3] >= b[1] && a[1] <= b[3]
}
impl SolidFrame {
    #[cfg(test)]
    pub fn probe_positions(&self) -> Vec<Position> {
        self.rows
            .iter()
            .map(|r| Position {
                x: r.position.x - 46 * S,
                y: r.region[1] + 15 * S,
            })
            .collect()
    }
    #[cfg(test)]
    pub fn trace(&self, saved_frame: i64, floor: i64, polygon_box_probes: Vec<bool>) -> SolidTrace {
        SolidTrace {
            saved_frame,
            polygon_box_probes,
            rows: self
                .rows
                .iter()
                .map(|r| SolidRecord {
                    token: r.token,
                    old_position: [r.old_position.x, r.old_position.y],
                    live_position: [r.position.x, r.position.y],
                    old_box: r.old_box,
                    live_box: r.live_box,
                })
                .collect(),
            floor_token: if floor <= -2 {
                self.rows[self.handles[(-2 - floor) as usize]].token
            } else {
                floor
            },
        }
    }
    pub fn begin(&mut self, entities: &[Entity]) {
        self.rows.clear();
        self.handles.clear();
        self.carried = false;
        self.bumped.clear();
        self.updates.clear();
        for entity in entities {
            if let Kind::Post(post) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = post.solid(entity.body, entity.status);
                self.rows.push(Row {
                    token: entity.origin.token(),
                    spiked: post.spiked,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x - 16 * S,
                        entity.body.y - post.height,
                        entity.body.x + 16 * S,
                        entity.body.y,
                    ],
                    handle: None,
                });
            }
        }
    }
    pub fn shapes(&mut self, probe: [i64; 4]) -> Vec<Shape> {
        let cells = |q: [i64; 4]| q.map(|v| floor_div(v, CELL).expect("positive cell size"));
        let p = cells(probe);
        let scan = (p[2] - p[0] + 1) * (p[3] - p[1] + 1) > 64
            || probe[2] < probe[0]
            || probe[3] < probe[1];
        let mut result = Vec::new();
        for (index, row) in self.rows.iter_mut().enumerate() {
            let Some(box_) = row.live_box else { continue };
            if !scan && !overlap(cells(row.region), p) {
                continue;
            }
            let handle = *row.handle.get_or_insert_with(|| {
                let handle = -2 - self.handles.len() as i64;
                self.handles.push(index);
                handle
            });
            result.push(Shape { handle, box_ });
        }
        result
    }
    pub fn take_updates(&mut self) -> Vec<PostUpdate> {
        std::mem::take(&mut self.updates)
    }
    pub fn pound(
        &mut self,
        map: &crate::body::Probe,
        body: &mut Body,
        bounds: [i64; 4],
        previous_edge: i64,
    ) {
        let probe = [
            body.x + bounds[0],
            body.y + bounds[1],
            body.x + bounds[2],
            body.y + bounds[3],
        ];
        let targets: Vec<usize> = self
            .shapes(probe)
            .into_iter()
            .filter(|s| previous_edge <= s.box_[1] && overlap(s.box_, probe))
            .map(|s| self.handles[(-2 - s.handle) as usize])
            .collect();
        for index in targets {
            let row = &mut self.rows[index];
            let Some(box_) = row.live_box else { continue };
            if row.spiked != 0 || !self.bumped.insert(row.token) {
                continue;
            }
            body.y = box_[1] - bounds[3] - S / 16;
            for _ in 0..2 {
                let foot = body.y + bounds[3] + 2 * S;
                let ground = |x: i64| {
                    map.terrain_overlaps([x, foot, x, foot])
                        || map.border_overlaps([x, foot, x, foot])
                        || map.bridges.iter().any(|b| {
                            x >= b.left && x <= b.right && foot >= b.top && foot <= b.top + 32 * S
                        })
                };
                if ground(body.x - 12 * S) || ground(body.x + 12 * S) {
                    break;
                }
                body.y += 16 * S;
            }
            body.vy = 0;
            let height = box_[3] - box_[1];
            let (status, height) = if height <= 48 * S {
                (3, 16 * S)
            } else {
                (1, height - 32 * S)
            };
            row.live_box = (status == 1).then_some([box_[0], box_[3] - height, box_[2], box_[3]]);
            row.region = [box_[0], box_[3] - height, box_[2], box_[3]];
            self.updates.push(PostUpdate {
                token: row.token,
                strike_box: box_,
                height,
                status,
            });
        }
    }
    pub fn touches(&mut self, probe: [i64; 4]) -> bool {
        self.shapes(probe)
            .into_iter()
            .any(|s| overlap(s.box_, probe))
    }
    pub fn carry(&mut self, body: &mut Body, bounds: [i64; 4], on_floor: i64) {
        if self.carried {
            return;
        }
        self.carried = true;
        if body.vy != 0 || on_floor == 0 {
            return;
        }
        let probe = [
            body.x + bounds[0],
            body.y + bounds[1] + S,
            body.x + bounds[2],
            body.y + bounds[3] + S,
        ];
        for row in &self.rows {
            if row
                .old_box
                .is_some_and(|b| body.y + bounds[3] <= b[1] && overlap(probe, b))
                && row.live_box.is_some()
            {
                body.x += row.position.x - row.old_position.x;
                body.y += row.position.y - row.old_position.y;
                return;
            }
        }
    }
}
