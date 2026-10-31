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
    /// item_block.gd and egg_block.gd rows: bumped from below, never pounded.
    block: bool,
    /// egg_block.gd rows: the bump clears the solid at once (busy), so the rest of the
    /// head's move no longer meets it.
    vanish: bool,
    /// pound_post.gd rows: the only rows a ground pound reaches here.
    post: bool,
    /// collision.gd SOLID: 1 full, 2 top-only.
    mode: i64,
    spiked: i64,
    position: Position,
    old_position: Position,
    old_box: Option<[i64; 4]>,
    live_box: Option<[i64; 4]>,
    region: [i64; 4],
    handle: Option<i64>,
    /// A type with solid_touches (one_way_gate.gd): the angle and unturned rectangle.
    turn: Option<(i64, [i64; 4])>,
}
/// A turned solid's narrow phase: `rect` turned by `angle` at `at`.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Turned {
    pub angle: i64,
    pub rect: [i64; 4],
    pub at: Position,
}
#[derive(Clone, Copy, Debug)]
pub(crate) struct Shape {
    pub handle: i64,
    pub mode: i64,
    pub box_: [i64; 4],
    pub turn: Option<Turned>,
}
impl Shape {
    /// collision.gd _shape_overlap: the box test, then the type's solid_touches.
    pub fn touches(&self, probe: [i64; 4]) -> bool {
        overlap(self.box_, probe)
            && self
                .turn
                .is_none_or(|t| crate::turn::overlaps(t.angle, t.rect, probe, t.at.x, t.at.y))
    }
}
fn turned(row: &Row) -> Option<Turned> {
    row.turn.map(|(angle, rect)| Turned {
        angle,
        rect,
        at: row.position,
    })
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
    /// collision.gd context.bumps for side 0 (head bumps), in contact order.
    head_bumped: std::collections::BTreeSet<i64>,
    /// Bumped tokens with the bumping body's world box at the bump.
    head_bumps: Vec<(i64, [i64; 4])>,
    /// Broad phase for `shapes`: rows listed under every CELL their region has
    /// ever covered this step (a superset). `shapes` still applies the exact
    /// region test in row order, so results and handle order are unchanged.
    cells: std::collections::HashMap<(i64, i64), Vec<usize>>,
    /// Rows whose region covers too many cells to list.
    wide: Vec<usize>,
}
const MAX_INDEXED_CELLS: i64 = 256;
/// The union of a region and an optional box.
fn cover(region: [i64; 4], b: Option<[i64; 4]>) -> [i64; 4] {
    b.map_or(region, |b| {
        [
            region[0].min(b[0]),
            region[1].min(b[1]),
            region[2].max(b[2]),
            region[3].max(b[3]),
        ]
    })
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
    fn index_region(&mut self, index: usize, region: [i64; 4]) {
        let c = region.map(|v| floor_div(v, CELL).expect("positive cell size"));
        let count = (c[2] - c[0] + 1).saturating_mul(c[3] - c[1] + 1);
        if c[2] < c[0] || c[3] < c[1] || count > MAX_INDEXED_CELLS {
            if !self.wide.contains(&index) {
                self.wide.push(index);
            }
            return;
        }
        for y in c[1]..=c[3] {
            for x in c[0]..=c[2] {
                let list = self.cells.entry((x, y)).or_default();
                if list.last() != Some(&index) {
                    list.push(index);
                }
            }
        }
    }
    pub fn begin(&mut self, entities: &[Entity]) {
        self.rows.clear();
        self.handles.clear();
        self.carried = false;
        self.bumped.clear();
        self.updates.clear();
        self.head_bumped.clear();
        self.head_bumps.clear();
        self.cells.clear();
        self.wide.clear();
        for entity in entities {
            if let Kind::Grow(grow) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = grow.solid(entity);
                let b = grow.bounds();
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: false,
                    vanish: false,
                    post: false,
                    mode: 1,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x + b[0],
                        entity.body.y + b[1],
                        entity.body.x + b[2],
                        entity.body.y + b[3],
                    ],
                    handle: None,
                    turn: None,
                });
            }
            if let Kind::Fall(fall) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = fall.solid(entity);
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: false,
                    vanish: false,
                    post: false,
                    mode: 2,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x - 16 * S,
                        entity.body.y - 16 * S,
                        entity.body.x + 16 * S,
                        entity.body.y + 16 * S,
                    ],
                    handle: None,
                    turn: None,
                });
            }
            if let Kind::Hard(hard) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = hard.solid(entity);
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: false,
                    vanish: false,
                    post: false,
                    mode: 1,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x + hard.bounds()[0],
                        entity.body.y + hard.bounds()[1],
                        entity.body.x + hard.bounds()[2],
                        entity.body.y + hard.bounds()[3],
                    ],
                    handle: None,
                    turn: None,
                });
            }
            if let Kind::Walker(w) = &entity.kind {
                if [
                    crate::actors::ActorKind::Flat,
                    crate::actors::ActorKind::Bulk,
                ]
                .contains(&w.kind)
                {
                    let position = Position {
                        x: entity.body.x,
                        y: entity.body.y,
                    };
                    let box_ = w
                        .flat_solid(entity.body, entity.facing)
                        .filter(|_| entity.status == 1);
                    let b = w.body_bounds(entity.facing);
                    self.rows.push(Row {
                        token: entity.origin.token(),
                        block: false,
                        vanish: false,
                        post: false,
                        mode: 2,
                        spiked: 0,
                        position,
                        old_position: position,
                        old_box: box_,
                        live_box: box_,
                        region: [
                            entity.body.x + b[0],
                            entity.body.y + b[1],
                            entity.body.x + b[2],
                            entity.body.y + b[3],
                        ],
                        handle: None,
                        turn: None,
                    });
                }
            }
            if let Kind::Span(span) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = span.solid(entity);
                let b = span.bounds();
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: false,
                    vanish: false,
                    post: false,
                    mode: 2,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: box_.unwrap_or([
                        entity.body.x + b[0],
                        entity.body.y + b[1],
                        entity.body.x + b[2],
                        entity.body.y + b[3],
                    ]),
                    handle: None,
                    turn: None,
                });
            }
            // decor_platform.gd: a static top-only strip.
            if let Kind::Platform(platform) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = platform.solid(entity.status, entity.body);
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: false,
                    vanish: false,
                    post: false,
                    mode: 2,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: box_.unwrap_or([entity.body.x, entity.body.y, entity.body.x, entity.body.y]),
                    handle: None,
                    turn: None,
                });
            }
            // dice_block.gd: full solids; switches are bumped from below.
            if let Kind::Dice(dice) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = dice.solid(entity.status, entity.body);
                let b = dice.bounds();
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: dice.switch,
                    vanish: false,
                    post: false,
                    mode: 1,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x + b[0],
                        entity.body.y + b[1],
                        entity.body.x + b[2],
                        entity.body.y + b[3],
                    ],
                    handle: None,
                    turn: None,
                });
            }
            // rise_balloon.gd: a moving top-only deck.
            if let Kind::Balloon(balloon) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = balloon.solid(entity);
                let b = balloon.bounds();
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: false,
                    vanish: false,
                    post: false,
                    mode: 2,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x + b[0],
                        entity.body.y + b[1],
                        entity.body.x + b[2],
                        entity.body.y + b[3],
                    ],
                    handle: None,
                    turn: None,
                });
            }
            // spike_pillar.gd: a static full solid.
            if let Kind::Pillar(pillar) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = pillar.solid(entity.status, entity.body);
                let b = pillar.bounds();
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: false,
                    vanish: false,
                    post: false,
                    mode: 1,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x + b[0],
                        entity.body.y + b[1],
                        entity.body.x + b[2],
                        entity.body.y + b[3],
                    ],
                    handle: None,
                    turn: None,
                });
            }
            // egg_block.gd: a full solid, bumped from below like an item block.
            if let Kind::EggBlock(block) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = block.solid(entity.status, entity.body);
                let b = block.bounds();
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: true,
                    vanish: true,
                    post: false,
                    mode: 1,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x + b[0],
                        entity.body.y + b[1],
                        entity.body.x + b[2],
                        entity.body.y + b[3],
                    ],
                    handle: None,
                    turn: None,
                });
            }
            if let Kind::Block(block) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = block.solid(entity);
                let b = block.bounds();
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: true,
                    vanish: false,
                    post: false,
                    mode: 1,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x + b[0],
                        entity.body.y + b[1],
                        entity.body.x + b[2],
                        entity.body.y + b[3],
                    ],
                    handle: None,
                    turn: None,
                });
            }
            // shot_launcher.gd: a solid block while active and not frozen.
            if let Kind::Launcher(launcher) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = launcher.solid(entity);
                let b = launcher.bounds();
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: false,
                    vanish: false,
                    post: false,
                    mode: 1,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x + b[0],
                        entity.body.y + b[1],
                        entity.body.x + b[2],
                        entity.body.y + b[3],
                    ],
                    handle: None,
                    turn: None,
                });
            }
            // ride_hound.gd: a running top-only back.
            if let Kind::Hound(hound) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = crate::hound::Hound::solid_at(entity.body, entity.status);
                let b = hound.bounds(entity.facing);
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: false,
                    vanish: false,
                    post: false,
                    mode: 2,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x + b[0],
                        entity.body.y + b[1],
                        entity.body.x + b[2],
                        entity.body.y + b[3],
                    ],
                    handle: None,
                    turn: None,
                });
            }
            // arrow_lift.gd: a moving top-only deck.
            if let Kind::Lift(lift) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = lift.solid(entity);
                let b = lift.bounds();
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: false,
                    vanish: false,
                    post: false,
                    mode: 2,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x + b[0],
                        entity.body.y + b[1],
                        entity.body.x + b[2],
                        entity.body.y + b[3],
                    ],
                    handle: None,
                    turn: None,
                });
            }
            // count_ledge.gd: a 2 px top-only edge.
            if let Kind::Ledge(ledge) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = ledge.solid(entity);
                let b = ledge.bounds();
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: false,
                    vanish: false,
                    post: false,
                    mode: 2,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x + b[0],
                        entity.body.y + b[1],
                        entity.body.x + b[2],
                        entity.body.y + b[3],
                    ],
                    handle: None,
                    turn: None,
                });
            }
            // one_way_gate.gd: a full barrier, gone while opened.
            if let Kind::Gate(gate) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = gate.solid(entity);
                let b = gate.bounds();
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: false,
                    vanish: false,
                    post: false,
                    mode: 1,
                    spiked: 0,
                    position,
                    old_position: position,
                    old_box: box_,
                    live_box: box_,
                    region: [
                        entity.body.x + b[0],
                        entity.body.y + b[1],
                        entity.body.x + b[2],
                        entity.body.y + b[3],
                    ],
                    handle: None,
                    turn: Some((gate.angle, crate::gate::BARRIER)),
                });
            }
            if let Kind::Post(post) = &entity.kind {
                let position = Position {
                    x: entity.body.x,
                    y: entity.body.y,
                };
                let box_ = post.solid(entity.body, entity.status);
                self.rows.push(Row {
                    token: entity.origin.token(),
                    block: false,
                    vanish: false,
                    post: true,
                    mode: 1,
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
                    turn: None,
                });
            }
        }
        for index in 0..self.rows.len() {
            // collision.gd _place: the region covers the type's bounds and its boxes.
            let row = &mut self.rows[index];
            row.region = cover(row.region, row.live_box);
            self.index_region(index, self.rows[index].region);
        }
    }
    pub fn shapes(&mut self, probe: [i64; 4]) -> Vec<Shape> {
        let cells = |q: [i64; 4]| q.map(|v| floor_div(v, CELL).expect("positive cell size"));
        let p = cells(probe);
        let scan = (p[2] - p[0] + 1) * (p[3] - p[1] + 1) > 64
            || probe[2] < probe[0]
            || probe[3] < probe[1];
        let mut result = Vec::new();
        if self.rows.is_empty() {
            return result;
        }
        let candidates: Vec<usize> = if scan {
            (0..self.rows.len()).collect()
        } else {
            let mut found = self.wide.clone();
            for y in p[1]..=p[3] {
                for x in p[0]..=p[2] {
                    if let Some(list) = self.cells.get(&(x, y)) {
                        found.extend_from_slice(list);
                    }
                }
            }
            found.sort_unstable();
            found.dedup();
            found
        };
        for index in candidates {
            let row = &mut self.rows[index];
            let Some(box_) = row.live_box else { continue };
            if !scan && !overlap(cells(row.region), p) {
                continue;
            }
            let handle = *row.handle.get_or_insert_with(|| {
                let handle = -2 - self.handles.len() as i64;
                self.handles.push(index);
                handle
            });
            result.push(Shape {
                handle,
                mode: row.mode,
                box_,
                turn: turned(row),
            });
        }
        result
    }
    /// collision.gd _selected: the live shape behind a handle (status checked by begin).
    pub fn selected(&self, handle: i64) -> Option<Shape> {
        if handle > -2 {
            return None;
        }
        let index = *self.handles.get((-2 - handle) as usize)?;
        let row = &self.rows[index];
        row.live_box.map(|box_| Shape {
            handle,
            mode: row.mode,
            box_,
            turn: turned(row),
        })
    }
    pub fn take_updates(&mut self) -> Vec<PostUpdate> {
        std::mem::take(&mut self.updates)
    }
    /// collision.gd _bump side 0 for the player: blocks whose bottom the head crossed.
    pub fn bump_below(&mut self, body: &Body, bounds: [i64; 4], previous_edge: i64) {
        let probe = [
            body.x + bounds[0],
            body.y + bounds[1],
            body.x + bounds[2],
            body.y + bounds[3],
        ];
        let targets: Vec<usize> = self
            .shapes(probe)
            .into_iter()
            .filter(|s| s.mode == 1 && previous_edge >= s.box_[3] && s.touches(probe))
            .map(|s| self.handles[(-2 - s.handle) as usize])
            .collect();
        for index in targets {
            let row = &mut self.rows[index];
            if row.block && self.head_bumped.insert(row.token) {
                self.head_bumps.push((row.token, probe));
                if row.vanish {
                    row.live_box = None;
                }
            }
        }
    }
    pub fn take_head_bumps(&mut self) -> Vec<(i64, [i64; 4])> {
        std::mem::take(&mut self.head_bumps)
    }
    /// collision.gd refresh: a solid moved or changed during its step.
    pub fn refresh(
        &mut self,
        token: i64,
        position: Position,
        live_box: Option<[i64; 4]>,
        region: [i64; 4],
    ) {
        let Some(index) = self.rows.iter().position(|r| r.token == token) else {
            return;
        };
        let row = &mut self.rows[index];
        row.position = position;
        row.live_box = live_box;
        row.region = cover(region, live_box);
        let region = row.region;
        self.index_region(index, region);
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
            .filter(|s| previous_edge <= s.box_[1] && s.touches(probe))
            .map(|s| self.handles[(-2 - s.handle) as usize])
            .collect();
        for index in targets {
            let row = &mut self.rows[index];
            let Some(box_) = row.live_box else { continue };
            if !row.post || row.spiked != 0 || !self.bumped.insert(row.token) {
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
            let region = row.region;
            self.updates.push(PostUpdate {
                token: row.token,
                strike_box: box_,
                height,
                status,
            });
            self.index_region(index, region);
        }
    }
    /// collision.gd support_in_box: a top-only shape counts only when the probe's top
    /// is at or above its top edge.
    pub fn touches(&mut self, probe: [i64; 4]) -> bool {
        self.shapes(probe)
            .into_iter()
            .any(|s| !(s.mode == 2 && probe[1] > s.box_[1]) && s.touches(probe))
    }
    /// collision.gd _carry: the offset the supporting solid moved this step, applied to
    /// the body. Returns it so the caller can retreat out of terrain.
    pub fn carry(
        &mut self,
        body: &mut Body,
        bounds: [i64; 4],
        on_floor: i64,
    ) -> Option<(i64, i64)> {
        if self.carried {
            return None;
        }
        self.carried = true;
        if body.vy != 0 || on_floor == 0 {
            return None;
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
                let (dx, dy) = (
                    row.position.x - row.old_position.x,
                    row.position.y - row.old_position.y,
                );
                body.x += dx;
                body.y += dy;
                return Some((dx, dy));
            }
        }
        None
    }
}
