//! Drawing-only sparse index. Maintained at successful state commits, never activation.
use crate::{entity::Kind, state::Run, PreparedPlacement, World, SCALE as S};
use std::collections::{BTreeSet, HashMap};
const CELL: i64 = 256 * S;
#[derive(Debug, Default)]
pub(crate) struct Index {
    guard: i64,
    chunks: HashMap<(i64, i64), Vec<usize>>,
    boxes: Vec<[i64; 4]>,
    ranges: Vec<Option<[i64; 4]>>,
    overflow: Vec<usize>,
    pub visited: usize,
    pub changed: usize,
}
fn range(b: [i64; 4]) -> Option<[i64; 4]> {
    let r = b.map(|v| v.div_euclid(CELL));
    ((r[2] - r[0] + 1)
        .checked_mul(r[3] - r[1] + 1)
        .is_some_and(|n| n <= 256))
    .then_some(r)
}
fn bounds(e: &crate::entity::Entity, w: &World, guard: i64) -> [i64; 4] {
    let source = e.source(w);
    let mut at = [e.body.x, e.body.y];
    if matches!(e.kind, Kind::Walker(_)) && [0, 2].contains(&e.status) {
        if let Some(p) = source {
            at = [p.position.x, p.position.y];
        }
    }
    let b = match &e.kind {
        Kind::Pickup(p) => p.bounds(),
        Kind::Star(p) => p.bounds(),
        Kind::Post(p) => p.bounds(),
        Kind::Walker(a) => a.body_bounds(e.facing),
        Kind::Egg(p) => p.bounds(),
        Kind::Cache(p) => p.bounds(),
        Kind::Redirect(p) => p.bounds(),
        Kind::Block(p) => p.bounds(),
        Kind::Span(p) => p.bounds(),
        Kind::Hard(p) => p.bounds(),
        Kind::Fall(p) => p.bounds(),
        Kind::Grow(p) => p.bounds(),
        Kind::Gate(p) => p.bounds(),
        Kind::Ledge(p) => p.bounds(),
        Kind::Stem(p) => p.bounds(),
        Kind::StarFlower(p) => p.bounds(),
        Kind::Switch(p) => p.bounds(),
        Kind::Lift(p) => p.bounds(),
        Kind::Melon(p) => p.bounds(),
        Kind::Seed(p) => p.bounds(),
        Kind::Hound(p) => p.bounds(e.facing),
        Kind::Launcher(p) => p.bounds(),
        Kind::Sack(p) => p.bounds(),
        Kind::EggBlock(p) => p.bounds(),
        Kind::Pillar(p) => p.bounds(),
        Kind::Balloon(p) => p.bounds(),
        Kind::Dice(p) => p.bounds(),
        Kind::SpinSpan(p) => p.bounds(),
        Kind::SpinBlock(p) => p.bounds(),
        Kind::Lamp(p) => p.bounds(),
        Kind::ElementShot(_) => crate::elements::SHOT_BOX,
        Kind::DiscBlock(p) => p.bounds(),
        Kind::Disc(p) => p.bounds(),
        Kind::Pad(_) => {
            let PreparedPlacement::Pad { large, .. } = source.unwrap().prepared else {
                unreachable!()
            };
            crate::pad::bounds(large)
        }
        Kind::Bridge => {
            let PreparedPlacement::Bridge { geometry_index } = source.unwrap().prepared else {
                unreachable!()
            };
            let b = w.maps[0].bridges[geometry_index];
            [
                b.left - at[0],
                b.top - at[1],
                b.right - at[0],
                b.top + 2 * S - at[1],
            ]
        }
        _ => [0; 4],
    };
    let mut result = [
        at[0] + b[0].min(0),
        at[1] + b[1].min(0),
        at[0] + b[2].max(0),
        at[1] + b[3].max(0),
    ];
    if let Kind::Walker(a) = &e.kind {
        if a.kind == crate::actors::ActorKind::Plant && a.head_size != 0 {
            let h = a.head_box(e.body, e.facing);
            result = [
                result[0].min(h[0]),
                result[1].min(h[1]),
                result[2].max(h[2]),
                result[3].max(h[3]),
            ];
        }
    }
    // Extendable scenery reaches its E1 height (plus lanterns and caps) from its position.
    if let (Kind::Decor, Some(p)) = (&e.kind, source.filter(|p| crate::decor::resized(&p.code))) {
        let reach = (crate::decor::height(p).unwrap_or(0) + 512).saturating_mul(S);
        result = [
            result[0].min(at[0].saturating_sub(reach)),
            result[1].min(at[1].saturating_sub(reach)),
            result[2].max(at[0].saturating_add(reach)),
            result[3].max(at[1].saturating_add(reach)),
        ];
    }
    let absolute = match &e.kind {
        Kind::Post(p) => p.height,
        Kind::Walker(a) if a.kind == crate::actors::ActorKind::Stilt => a.height,
        Kind::Pad(_) => 96 * S,
        _ => 0,
    };
    let extra = absolute.saturating_mul(guard.max(1));
    if extra > 0 {
        result = [
            result[0].min(at[0].saturating_sub(extra)),
            result[1].min(at[1].saturating_sub(extra)),
            result[2].max(at[0].saturating_add(extra)),
            result[3].max(at[1].saturating_add(extra)),
        ];
    }
    result
}
impl Index {
    pub fn configure(&mut self, guard: i64) {
        if self.guard != guard {
            *self = Self {
                guard,
                ..Default::default()
            };
        }
    }
    pub fn update(&mut self, run: &Run, world: &World) {
        if self.boxes.len() > run.entities.len() {
            *self = Self {
                guard: self.guard,
                ..Default::default()
            };
        }
        self.visited = run.entities.len();
        self.changed = 0;
        for (i, e) in run.entities.iter().enumerate() {
            let b = bounds(e, world, self.guard);
            let r = range(b);
            if i < self.boxes.len() {
                if self.ranges[i] != r {
                    if let Some(old) = self.ranges[i] {
                        for y in old[1]..=old[3] {
                            for x in old[0]..=old[2] {
                                if let Some(v) = self.chunks.get_mut(&(x, y)) {
                                    v.retain(|j| *j != i);
                                }
                            }
                        }
                    } else {
                        self.overflow.retain(|j| *j != i);
                    }
                } else {
                    self.boxes[i] = b;
                    continue;
                }
            }
            if let Some(r) = r {
                for y in r[1]..=r[3] {
                    for x in r[0]..=r[2] {
                        self.chunks.entry((x, y)).or_default().push(i);
                    }
                }
            } else {
                self.overflow.push(i);
            }
            if i == self.boxes.len() {
                self.boxes.push(b);
                self.ranges.push(r);
            } else {
                self.boxes[i] = b;
                self.ranges[i] = r;
            }
            self.changed += 1;
        }
    }
    pub fn query(&self, b: [i64; 4]) -> Vec<usize> {
        let r = b.map(|v| v.div_euclid(CELL));
        let mut ids = BTreeSet::new();
        if !(r[2] - r[0] + 1)
            .checked_mul(r[3] - r[1] + 1)
            .is_some_and(|n| (0..=65536).contains(&n))
        {
            return (0..self.boxes.len()).collect();
        }
        for y in r[1]..=r[3] {
            for x in r[0]..=r[2] {
                if let Some(v) = self.chunks.get(&(x, y)) {
                    ids.extend(v.iter().copied());
                }
            }
        }
        ids.extend(self.overflow.iter().copied());
        ids.into_iter()
            .filter(|i| {
                let a = self.boxes[*i];
                a[0] <= b[2] && a[2] >= b[0] && a[1] <= b[3] && a[3] >= b[1]
            })
            .collect()
    }
    pub fn metrics(&self) -> (usize, usize, usize, usize) {
        (
            self.boxes.len(),
            self.chunks.len(),
            self.visited,
            self.changed,
        )
    }
}
