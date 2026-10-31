//! item_block.gd for o9 (egg block), o15 (linked on/off block), o18 (message block) and
//! o24 (the shrinking clear block).
use crate::{
    entity::{Entity, Kind},
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};

pub(crate) const CLOSED: i64 = 0;
pub(crate) const OPENING: i64 = 1;
pub(crate) const READING: i64 = 2;
pub(crate) const CLOSING: i64 = 3;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum BlockKind {
    Egg,
    Linked,
    Message,
    /// o24: each bump from below clears the screen of enemies and shrinks it; the third
    /// bump uses it up.
    Clear,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Block {
    pub kind: BlockKind,
    pub home_x: i64,
    pub home_y: i64,
    pub busy: i64,
    pub bump_direction: i64,
    pub enabled: i64,
    pub solid_ready: i64,
    pub charges: i64,
    pub height: i64,
    pub height_from: i64,
}

/// Static full solids broken by eggs: hard_block.gd (o28), colour_block.gd (o29) and
/// thorn_block.gd (o12).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum HardKind {
    /// o28: 64 x 64; even forms crack, odd forms break; stops the tongue.
    Rock,
    /// o29: 64 x 32; forms 0..2 change colour, the last breaks.
    Colour,
    /// o12: 32 x 32; any egg breaks it; touching it kills the player.
    Thorn,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Hard {
    pub kind: HardKind,
    pub form: i64,
}

impl Hard {
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let (kind, last) = match p.code.as_str() {
            "o28" => (HardKind::Rock, 17),
            "o29" => (HardKind::Colour, 2),
            _ => (HardKind::Thorn, 1),
        };
        if !(0..=last).contains(&p.variant) {
            return Err(Error::Unsupported {
                requirements: vec![format!("{} form F={}", p.code, p.variant)],
            });
        }
        Ok(Self {
            kind,
            form: p.variant,
        })
    }
    pub fn last_form(&self) -> i64 {
        match self.kind {
            HardKind::Rock => 17,
            HardKind::Colour => 2,
            HardKind::Thorn => 1,
        }
    }
    pub fn bounds(&self) -> [i64; 4] {
        match self.kind {
            HardKind::Rock => [-32 * S, -32 * S, 32 * S, 32 * S],
            HardKind::Colour => [-32 * S, -16 * S, 32 * S, 16 * S],
            HardKind::Thorn => [-16 * S, -16 * S, 16 * S, 16 * S],
        }
    }
    pub fn solid(&self, e: &Entity) -> Option<[i64; 4]> {
        let b = self.bounds();
        (e.status == 1).then(|| {
            [
                e.body.x + b[0],
                e.body.y + b[1],
                e.body.x + b[2],
                e.body.y + b[3],
            ]
        })
    }
    pub fn animation(&self) -> &'static str {
        match self.kind {
            HardKind::Rock => "Rock",
            HardKind::Colour => "Color",
            HardKind::Thorn => "Default",
        }
    }
    /// Whether projectile_contact refunds the bounce its own ricochet spends.
    pub fn refunds_bounce(&self) -> bool {
        self.kind != HardKind::Thorn
    }
    /// The type's hit with Hits.EGG.
    pub fn egg_hit(&mut self, status: &mut i64) {
        if *status != 1 {
            return;
        }
        match self.kind {
            HardKind::Rock if self.form % 2 == 0 => self.form += 1,
            HardKind::Colour if self.form < 2 => self.form += 1,
            _ => *status = 3,
        }
    }
}
/// falling_span.gd (o20): a 32 px top-only support that arms while stood on, falls from
/// age 73 and is removed (or reset, form 1) far below the screen.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Fall {
    pub age: i64,
    pub home_y: i64,
    pub respawns: i64,
}

impl Fall {
    pub fn new(p: &Placement) -> Result<Self, Error> {
        if !(0..=1).contains(&p.variant) {
            return Err(Error::Unsupported {
                requirements: vec![format!("falling span form F={}", p.variant)],
            });
        }
        Ok(Self {
            age: 0,
            home_y: p.position.y,
            respawns: i64::from(p.variant == 1),
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        [-16 * S, -16 * S, 16 * S, 16 * S]
    }
    pub fn solid(&self, e: &Entity) -> Option<[i64; 4]> {
        (e.status == 1).then(|| {
            [
                e.body.x - 16 * S,
                e.body.y - 16 * S,
                e.body.x + 16 * S,
                e.body.y - 14 * S,
            ]
        })
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "age" => self.age,
            "home_y" => self.home_y,
            "respawns" => self.respawns,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        let slot = match n {
            "age" => &mut self.age,
            "home_y" => &mut self.home_y,
            "respawns" => &mut self.respawns,
            _ => return false,
        };
        *slot = value;
        true
    }
    pub fn valid(&self, vy: i64) -> bool {
        (0..=125).contains(&self.age)
            && [0, 1].contains(&self.respawns)
            && (0..=192 * 60).contains(&vy)
    }
    /// falling_span.gd view_state: animation and frame.
    pub fn view(&self) -> (&'static str, i64) {
        let mut frame = 0;
        if self.age > 1 {
            let units = (self.age - 1) * 32;
            if units >= 66 * 60 {
                frame = 4;
            } else if units >= 18 * 60 {
                frame = 1 + (units / 60 - 18) % 4;
            }
        }
        (if self.age == 0 { "Idle" } else { "Falling" }, frame)
    }
}

/// grow_block.gd (o10): a small full solid that doubles when touched, holds, then shrinks.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Grow {
    pub phase: i64,
    pub ticks: i64,
    pub timer: i64,
    pub size: i64,
    pub lift: i64,
}

const GROW_TWEEN: i64 = 12;
const GROW_HOLD: i64 = 360;
const GROW_SMALL: i64 = 32 * S;
const GROW_LARGE: i64 = 64 * S;
const GROW_RISE: i64 = -62 * S;
const GROW_HELD: i64 = -32 * S;

fn ease_in_out(from: i64, to: i64, tick: i64) -> i64 {
    // Quadratic in-out over GROW_TWEEN ticks, in exact integer steps.
    let span = GROW_TWEEN * GROW_TWEEN;
    let part = if 2 * tick < GROW_TWEEN {
        2 * tick * tick
    } else {
        span - 2 * (GROW_TWEEN - tick) * (GROW_TWEEN - tick)
    };
    from + (to - from) * part / span
}

impl Default for Grow {
    fn default() -> Self {
        Self {
            phase: 0,
            ticks: 0,
            timer: 0,
            size: GROW_SMALL,
            lift: 0,
        }
    }
}

impl Grow {
    pub fn bounds(&self) -> [i64; 4] {
        // The block grows around its bottom centre; lift moves that bottom.
        let half = self.size / 2;
        let bottom = 16 * S + self.lift;
        [-half, bottom - self.size, half, bottom]
    }
    pub fn solid(&self, e: &Entity) -> Option<[i64; 4]> {
        let b = self.bounds();
        (e.status == 1).then(|| {
            [
                e.body.x + b[0],
                e.body.y + b[1],
                e.body.x + b[2],
                e.body.y + b[3],
            ]
        })
    }
    pub fn step(&mut self) {
        if self.phase == 0 {
            return;
        }
        self.timer += 1;
        if self.phase == 3 {
            if self.timer >= GROW_HOLD {
                self.phase = 4;
                self.ticks = 0;
            }
            return;
        }
        self.ticks += 1;
        match self.phase {
            1 => {
                self.lift = ease_in_out(0, GROW_RISE, self.ticks);
                self.size = GROW_SMALL + (GROW_LARGE - GROW_SMALL) * self.ticks / GROW_TWEEN;
            }
            2 => self.lift = ease_in_out(GROW_RISE, GROW_HELD, self.ticks),
            4 => {
                self.lift = ease_in_out(GROW_HELD, 0, self.ticks);
                self.size = GROW_LARGE + (GROW_SMALL - GROW_LARGE) * self.ticks / GROW_TWEEN;
            }
            _ => {}
        }
        if self.ticks < GROW_TWEEN {
            return;
        }
        self.ticks = 0;
        match self.phase {
            1 => self.phase = 2,
            2 => self.phase = if self.timer < GROW_HOLD { 3 } else { 4 },
            4 => {
                self.phase = 0;
                self.timer = 0;
            }
            _ => {}
        }
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "phase" => self.phase,
            "ticks" => self.ticks,
            "timer" => self.timer,
            "size" => self.size,
            "lift" => self.lift,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        let slot = match n {
            "phase" => &mut self.phase,
            "ticks" => &mut self.ticks,
            "timer" => &mut self.timer,
            "size" => &mut self.size,
            "lift" => &mut self.lift,
            _ => return false,
        };
        *slot = value;
        true
    }
    pub fn valid(&self) -> bool {
        (0..=4).contains(&self.phase)
            && (0..=GROW_TWEEN).contains(&self.ticks)
            && (0..=GROW_HOLD + 2 * GROW_TWEEN).contains(&self.timer)
            && (GROW_SMALL..=GROW_LARGE).contains(&self.size)
            && (GROW_RISE..=0).contains(&self.lift)
    }
}

/// The modal message state (item_block.gd LEVEL_FIELDS plus registry modal_token).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct Message {
    pub modal_token: i64,
    pub stage: i64,
    pub ticks: i64,
    pub section: i64,
    pub scroll: i64,
    pub previous: i64,
}

impl Message {
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "modal_token" => self.modal_token,
            "message_stage" => self.stage,
            "message_ticks" => self.ticks,
            "message_section" => self.section,
            "message_scroll" => self.scroll,
            "message_previous" => self.previous,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        let slot = match n {
            "modal_token" => &mut self.modal_token,
            "message_stage" => &mut self.stage,
            "message_ticks" => &mut self.ticks,
            "message_section" => &mut self.section,
            "message_scroll" => &mut self.scroll,
            "message_previous" => &mut self.previous,
            _ => return false,
        };
        *slot = value;
        true
    }
    /// item_block.gd reset_map: the message fields only (modal_token is the registry's).
    pub fn reset_fields(&mut self) {
        let token = self.modal_token;
        *self = Self::default();
        self.modal_token = token;
    }
}

impl Block {
    /// item_block.gd prepare + create.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let kind = match p.code.as_str() {
            "o9" => BlockKind::Egg,
            "o15" => BlockKind::Linked,
            "o18" => BlockKind::Message,
            "o24" => BlockKind::Clear,
            _ => {
                return Err(Error::Unsupported {
                    requirements: vec![format!("item block {}", p.code)],
                })
            }
        };
        // item_block.gd prepare: a clear block hangs from 32 px above its placement.
        let y = p.position.y - if kind == BlockKind::Clear { 32 * S } else { 0 };
        let height = if kind == BlockKind::Clear { 56 } else { 32 } * S;
        if kind == BlockKind::Message {
            let text = p.properties.iter().find(|(k, _)| k == "E1").map(|(_, v)| v);
            if !matches!(text, None | Some(PropertyValue::String(_))) {
                return Err(Error::Unsupported {
                    requirements: vec!["message text".into()],
                });
            }
        }
        let enabled = i64::from(kind != BlockKind::Linked || p.variant == 1);
        Ok(Self {
            kind,
            home_x: p.position.x,
            home_y: y,
            busy: 0,
            bump_direction: 1,
            enabled,
            solid_ready: enabled,
            charges: 3,
            height,
            height_from: height,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        if self.kind == BlockKind::Clear {
            [-28 * S, 0, 28 * S, self.height]
        } else {
            [-16 * S, -16 * S, 16 * S, 16 * S]
        }
    }
    pub fn solid(&self, e: &Entity) -> Option<[i64; 4]> {
        (e.status == 1 && e.collected == 0 && self.enabled != 0 && self.solid_ready != 0).then(
            || {
                let b = self.bounds();
                [
                    e.body.x + b[0],
                    e.body.y + b[1],
                    e.body.x + b[2],
                    e.body.y + b[3],
                ]
            },
        )
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "home_x" => self.home_x,
            "home_y" => self.home_y,
            "busy" => self.busy,
            "bump_direction" => self.bump_direction,
            "enabled" => self.enabled,
            "solid_ready" => self.solid_ready,
            "charges" => self.charges,
            "height" => self.height,
            "height_from" => self.height_from,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        let slot = match n {
            "home_x" => &mut self.home_x,
            "home_y" => &mut self.home_y,
            "busy" => &mut self.busy,
            "bump_direction" => &mut self.bump_direction,
            "enabled" => &mut self.enabled,
            "solid_ready" => &mut self.solid_ready,
            "charges" => &mut self.charges,
            "height" => &mut self.height,
            "height_from" => &mut self.height_from,
            _ => return false,
        };
        *slot = value;
        true
    }
    pub fn valid(&self) -> bool {
        (0..=20).contains(&self.busy)
            && [-1, 1].contains(&self.bump_direction)
            && [0, 1].contains(&self.enabled)
            && [0, 1].contains(&self.solid_ready)
            && (0..=3).contains(&self.charges)
            && (0..=56 * S).contains(&self.height)
            && (0..=56 * S).contains(&self.height_from)
    }
}

fn overlap(a: [i64; 4], b: [i64; 4]) -> bool {
    // registry.gd overlaps_box: closed edges.
    a[2] >= b[0] && a[0] <= b[2] && a[3] >= b[1] && a[1] <= b[3]
}

impl Run {
    fn block(&self, index: usize) -> &Block {
        match &self.entities[index].kind {
            Kind::Block(b) => b,
            _ => unreachable!("block index"),
        }
    }
    fn block_mut(&mut self, index: usize) -> &mut Block {
        match &mut self.entities[index].kind {
            Kind::Block(b) => b,
            _ => unreachable!("block index"),
        }
    }
    fn player_overlaps(&self, index: usize) -> bool {
        let e = &self.entities[index];
        let b = self.block(index).bounds();
        let pb = self.player.bounds();
        let p = self.player.body;
        overlap(
            [
                e.body.x + b[0],
                e.body.y + b[1],
                e.body.x + b[2],
                e.body.y + b[3],
            ],
            [p.x + pb[0], p.y + pb[1], p.x + pb[2], p.y + pb[3]],
        )
    }
    /// collision.gd refresh for a block row after its step or bump.
    pub(crate) fn refresh_block_solid(&self, index: usize, map: &crate::body::Probe) {
        let e = &self.entities[index];
        if let Kind::Walker(w) = &e.kind {
            // flat_walker.gd: a flattened e4 is a moving top-only support.
            if [
                crate::actors::ActorKind::Flat,
                crate::actors::ActorKind::Bulk,
            ]
            .contains(&w.kind)
            {
                let r = w.body_bounds(e.facing);
                map.refresh_solid(
                    e.origin.token(),
                    crate::Position {
                        x: e.body.x,
                        y: e.body.y,
                    },
                    w.flat_solid(e.body, e.facing).filter(|_| e.status == 1),
                    [
                        e.body.x + r[0],
                        e.body.y + r[1],
                        e.body.x + r[2],
                        e.body.y + r[3],
                    ],
                );
            }
            return;
        }
        if let Kind::Grow(g) = &e.kind {
            let r = g.bounds();
            map.refresh_solid(
                e.origin.token(),
                crate::Position {
                    x: e.body.x,
                    y: e.body.y,
                },
                g.solid(e),
                [
                    e.body.x + r[0],
                    e.body.y + r[1],
                    e.body.x + r[2],
                    e.body.y + r[3],
                ],
            );
            return;
        }
        if let Kind::Fall(f) = &e.kind {
            let r = f.bounds();
            map.refresh_solid(
                e.origin.token(),
                crate::Position {
                    x: e.body.x,
                    y: e.body.y,
                },
                f.solid(e),
                [
                    e.body.x + r[0],
                    e.body.y + r[1],
                    e.body.x + r[2],
                    e.body.y + r[3],
                ],
            );
            return;
        }
        if let Kind::Launcher(l) = &e.kind {
            let r = l.bounds();
            map.refresh_solid(
                e.origin.token(),
                crate::Position {
                    x: e.body.x,
                    y: e.body.y,
                },
                l.solid(e),
                [
                    e.body.x + r[0],
                    e.body.y + r[1],
                    e.body.x + r[2],
                    e.body.y + r[3],
                ],
            );
            return;
        }
        if let Kind::Hound(h) = &e.kind {
            let r = h.bounds(e.facing);
            map.refresh_solid(
                e.origin.token(),
                crate::Position {
                    x: e.body.x,
                    y: e.body.y,
                },
                crate::hound::Hound::solid_at(e.body, e.status),
                [
                    e.body.x + r[0],
                    e.body.y + r[1],
                    e.body.x + r[2],
                    e.body.y + r[3],
                ],
            );
            return;
        }
        if let Kind::Lift(l) = &e.kind {
            let r = l.bounds();
            map.refresh_solid(
                e.origin.token(),
                crate::Position {
                    x: e.body.x,
                    y: e.body.y,
                },
                l.solid(e),
                [
                    e.body.x + r[0],
                    e.body.y + r[1],
                    e.body.x + r[2],
                    e.body.y + r[3],
                ],
            );
            return;
        }
        if let Kind::Ledge(l) = &e.kind {
            let r = l.bounds();
            map.refresh_solid(
                e.origin.token(),
                crate::Position {
                    x: e.body.x,
                    y: e.body.y,
                },
                l.solid(e),
                [
                    e.body.x + r[0],
                    e.body.y + r[1],
                    e.body.x + r[2],
                    e.body.y + r[3],
                ],
            );
            return;
        }
        if let Kind::Gate(g) = &e.kind {
            let r = g.bounds();
            map.refresh_solid(
                e.origin.token(),
                crate::Position {
                    x: e.body.x,
                    y: e.body.y,
                },
                g.solid(e),
                [
                    e.body.x + r[0],
                    e.body.y + r[1],
                    e.body.x + r[2],
                    e.body.y + r[3],
                ],
            );
            return;
        }
        if let Kind::Dice(d) = &e.kind {
            let r = d.bounds();
            map.refresh_solid(
                e.origin.token(),
                crate::Position {
                    x: e.body.x,
                    y: e.body.y,
                },
                d.solid(e.status, e.body),
                [
                    e.body.x + r[0],
                    e.body.y + r[1],
                    e.body.x + r[2],
                    e.body.y + r[3],
                ],
            );
            return;
        }
        if let Kind::Balloon(b) = &e.kind {
            let r = b.bounds();
            map.refresh_solid(
                e.origin.token(),
                crate::Position {
                    x: e.body.x,
                    y: e.body.y,
                },
                b.solid(e),
                [
                    e.body.x + r[0],
                    e.body.y + r[1],
                    e.body.x + r[2],
                    e.body.y + r[3],
                ],
            );
            return;
        }
        if let Kind::EggBlock(b) = &e.kind {
            let r = b.bounds();
            map.refresh_solid(
                e.origin.token(),
                crate::Position {
                    x: e.body.x,
                    y: e.body.y,
                },
                b.solid(e.status, e.body),
                [
                    e.body.x + r[0],
                    e.body.y + r[1],
                    e.body.x + r[2],
                    e.body.y + r[3],
                ],
            );
            return;
        }
        if let Kind::Hard(h) = &e.kind {
            let r = h.bounds();
            map.refresh_solid(
                e.origin.token(),
                crate::Position {
                    x: e.body.x,
                    y: e.body.y,
                },
                h.solid(e),
                [
                    e.body.x + r[0],
                    e.body.y + r[1],
                    e.body.x + r[2],
                    e.body.y + r[3],
                ],
            );
            return;
        }
        let Kind::Block(b) = &e.kind else {
            return;
        };
        let r = b.bounds();
        map.refresh_solid(
            e.origin.token(),
            crate::Position {
                x: e.body.x,
                y: e.body.y,
            },
            b.solid(e),
            [
                e.body.x + r[0],
                e.body.y + r[1],
                e.body.x + r[2],
                e.body.y + r[3],
            ],
        );
    }
    /// falling_span.gd step.
    pub(crate) fn fall_step(
        &mut self,
        index: usize,
        map: &crate::body::Probe,
        centre: crate::Position,
    ) {
        let Kind::Fall(f) = &mut self.entities[index].kind else {
            return;
        };
        if f.age == 0 {
            return;
        }
        f.age = (f.age + 1).min(125);
        let (age, respawns, home_y) = (f.age, f.respawns, f.home_y);
        let e = &mut self.entities[index];
        let b = [-16 * S, -16 * S, 16 * S, 16 * S];
        if age >= 73 {
            if e.body.prepare(map, b) {
                let support = e.body.floor(map, b);
                let vy = e.body.vy;
                e.body.vertical_support(map, b, vy, support);
            }
            e.body.vy = (e.body.vy + 256).min(192 * 60);
        }
        if e.body.y <= centre.y + 832 * S {
            return;
        }
        if respawns != 0 {
            if let Kind::Fall(f) = &mut e.kind {
                f.age = 0;
            }
            e.body.y = home_y;
            e.body.vy = 0;
        } else {
            e.status = 3;
        }
    }
    /// falling_span.gd contact: standing on its top arms it; stepping off disarms it.
    pub(crate) fn fall_contact(&mut self, index: usize) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let on_floor = self.player.on_floor != 0;
        let e = &mut self.entities[index];
        let Kind::Fall(f) = &mut e.kind else {
            return;
        };
        if f.age >= 73 {
            return;
        }
        let top = e.body.y - 16 * S;
        let standing = on_floor
            && p.x + pb[2] >= e.body.x - 16 * S
            && p.x + pb[0] <= e.body.x + 16 * S
            && p.y + pb[3] <= top
            && p.y + pb[3] + 2 * S >= top;
        if standing && f.age == 0 {
            f.age = 1;
        } else if !standing {
            f.age = 0;
        }
    }
    /// item_block.gd step.
    pub(crate) fn block_step(
        &mut self,
        index: usize,
        centre: crate::Position,
    ) -> Result<(), Error> {
        let block = self.block(index).clone();
        if block.kind == BlockKind::Linked && block.enabled != 0 && block.solid_ready == 0 {
            let ready = i64::from(!self.player_overlaps(index));
            self.block_mut(index).solid_ready = ready;
        }
        if block.busy == 0 {
            return Ok(());
        }
        let busy = block.busy - 1;
        self.block_mut(index).busy = busy;
        if block.kind == BlockKind::Egg {
            let offset = (12 - busy).min(busy);
            let e = &mut self.entities[index];
            e.body.x = block.home_x + block.bump_direction * 8 * S * offset / 6;
            e.body.y = block.home_y - 32 * S * offset / 6;
            if busy == 6 && self.active_eggs(centre) < 6 {
                let (x, y) = (
                    self.entities[index].body.x,
                    self.entities[index].body.y - 16 * S,
                );
                let vx = block.bump_direction * self.rng.ticks(128 * 60, 192 * 60);
                self.spawn_block_egg(x, y, vx, -256 * 60)?;
            }
        } else if block.kind == BlockKind::Clear {
            let target = [0, 22, 34, 56][block.charges as usize] * S;
            let b = self.block_mut(index);
            b.height = b.height_from + (target - b.height_from) * (6 - busy) / 6;
            if busy == 0 && block.charges == 0 {
                self.entities[index].status = 3;
            }
        }
        Ok(())
    }
    /// item_block.gd bump, side 0 (from below) only.
    pub(crate) fn block_bump(
        &mut self,
        index: usize,
        centre: crate::Position,
    ) -> Result<(), Error> {
        let e = &self.entities[index];
        let block = self.block(index).clone();
        if e.status != 1
            || block.busy != 0
            || e.collected != 0
            || block.enabled == 0
            || self.player.blocks_step()
        {
            return Ok(());
        }
        match block.kind {
            BlockKind::Egg => {
                self.bump_above(index)?;
                let direction = if self.player.body.x < self.entities[index].body.x {
                    1
                } else {
                    -1
                };
                let b = self.block_mut(index);
                b.busy = 12;
                b.bump_direction = direction;
            }
            BlockKind::Message => self.open_message(index)?,
            BlockKind::Clear => {
                if block.charges != 0 {
                    self.bump_above(index)?;
                    self.clear_area(centre)?;
                    let b = self.block_mut(index);
                    b.charges -= 1;
                    b.height_from = b.height;
                    b.busy = 6;
                }
            }
            BlockKind::Linked => {}
        }
        Ok(())
    }
    /// item_block.gd clear_area: Hits.CLEAR on every active, visible entity with a hit
    /// rule on the reference screen, in table order (entities it spawns included).
    fn clear_area(&mut self, centre: crate::Position) -> Result<(), Error> {
        let probe = [
            centre.x - 416 * S,
            centre.y - 224 * S,
            centre.x + 416 * S,
            centre.y + 224 * S,
        ];
        let mut other = 0;
        while other < self.entities.len() {
            let current = other;
            other += 1;
            let o = &self.entities[current];
            // Of the hit rules, only enemies react to CLEAR: pickups, clouds, eggs,
            // producers and blocks ignore it.
            let Kind::Walker(w) = &o.kind else {
                continue;
            };
            if o.status != 1 || w.held == 1 || w.hidden == 1 {
                continue;
            }
            let b = crate::egg::entity_bounds(o);
            if !(o.body.x + b[2] > probe[0]
                && o.body.x + b[0] < probe[2]
                && o.body.y + b[3] > probe[1]
                && o.body.y + b[1] < probe[3])
            {
                continue;
            }
            self.clear_hit(current)?;
        }
        Ok(())
    }
    /// Each enemy's `hit` with Hits.CLEAR.
    fn clear_hit(&mut self, index: usize) -> Result<(), Error> {
        use crate::actors::ActorKind;
        let Kind::Walker(w) = &self.entities[index].kind else {
            return Ok(());
        };
        match w.kind {
            // stilt_walker.gd hit: POUND and CLEAR unseat the rider.
            ActorKind::Stilt => self.unseat_stilt(index),
            // shell_walker.gd hit: removed (with on_remove).
            ActorKind::Shell | ActorKind::Runner => {
                self.shell_remove(index);
                Ok(())
            }
            // spear_guard.gd hit: the spear drops and it is removed.
            ActorKind::Spear => {
                let e = &mut self.entities[index];
                if let Kind::Walker(w) = &mut e.kind {
                    w.has_spear = 0;
                    w.remove(&mut e.status, &mut e.can_respawn);
                }
                Ok(())
            }
            // armored_walker.gd and flat_walker.gd remove it; actor.gd removes any other.
            _ => self.hit_actor(index),
        }
    }
    /// item_block.gd projectile_contact: 1 consumed (message opened), 3 solid, 0 pass.
    /// (item_block.gd hit with Hits.EGG opens the message too; its callers, shells and
    /// other projectiles, are not ported, so it has no Rust caller yet.)
    pub(crate) fn block_projectile_contact(&mut self, index: usize) -> Result<i64, Error> {
        let block = self.block(index).clone();
        if block.kind == BlockKind::Message
            && block.enabled != 0
            && block.busy == 0
            && self.message.modal_token == 0
        {
            self.open_message(index)?;
            return Ok(1);
        }
        Ok(if block.solid(&self.entities[index]).is_some() {
            3
        } else {
            0
        })
    }
    fn open_message(&mut self, index: usize) -> Result<(), Error> {
        if self.message.modal_token != 0 || self.block(index).busy != 0 || self.player.blocks_step()
        {
            return Ok(());
        }
        self.bump_above(index)?;
        self.message = Message {
            modal_token: self.entities[index].origin.token(),
            stage: OPENING,
            ticks: 78,
            section: 0,
            scroll: 0,
            previous: self.player.previous_input,
        };
        Ok(())
    }
    /// item_block.gd consume_level_requests: a message opened this step stops being solid.
    pub(crate) fn block_level_requests(&mut self) {
        if self.message.stage != OPENING || self.message.ticks != 78 {
            return;
        }
        if let Some(i) = self.find_token(self.message.modal_token) {
            if let Kind::Block(b) = &mut self.entities[i].kind {
                if b.kind == BlockKind::Message && b.enabled != 0 {
                    b.enabled = 0;
                    b.solid_ready = 0;
                }
            }
        }
    }
    /// registry.gd modal_step + item_block.gd modal_step. True: the step is consumed.
    pub(crate) fn modal_step(&mut self, input: u8, world: &crate::World) -> Result<bool, Error> {
        if self.message.modal_token == 0 {
            return Ok(false);
        }
        let Some(index) = self.find_token(self.message.modal_token) else {
            self.message.modal_token = 0;
            return Ok(false);
        };
        if matches!(self.entities[index].kind, Kind::Switch(_)) {
            return self.switch_modal_step(index, i64::from(input));
        }
        if !matches!(&self.entities[index].kind, Kind::Block(b) if b.kind == BlockKind::Message) {
            self.message.modal_token = 0;
            return Ok(false);
        }
        Ok(self.message_modal_step(index, input, world))
    }
    /// item_block.gd modal_step for the open message at `index`.
    fn message_modal_step(&mut self, index: usize, input: u8, world: &crate::World) -> bool {
        if self.message.stage == OPENING && self.block(index).enabled != 0 {
            let b = self.block_mut(index);
            b.enabled = 0;
            b.solid_ready = 0;
        }
        let input = i64::from(input);
        let pressed = input & !self.message.previous;
        self.message.previous = input;
        self.player.previous_input = input;
        self.player.pressed_input = 0;
        if self.message.ticks != 0 {
            self.message.ticks -= 1;
            if self.message.ticks == 0 {
                if self.message.stage == OPENING {
                    self.message.stage = READING;
                } else if self.message.stage == CLOSING {
                    let b = self.block_mut(index);
                    b.enabled = 1;
                    b.solid_ready = 1;
                    b.busy = 20;
                    self.message.reset_fields();
                    self.message.modal_token = 0;
                    return false;
                }
            }
            return true;
        }
        if self.message.scroll != 0 {
            self.message.scroll -= 1;
        }
        if self.message.stage == READING {
            let sections = self.message_sections(index, world);
            const UP: i64 = 16;
            const DOWN: i64 = 32;
            const THROW: i64 = 64;
            if pressed & THROW != 0 || pressed & DOWN != 0 && self.message.section >= sections - 1 {
                self.message.stage = CLOSING;
                self.message.ticks = 30;
            } else if self.message.scroll == 0 && pressed & DOWN != 0 {
                self.message.section += 1;
                self.message.scroll = 48;
            } else if self.message.scroll == 0 && pressed & UP != 0 && self.message.section != 0 {
                self.message.section -= 1;
                self.message.scroll = 48;
            }
        }
        true
    }
    /// item_block.gd message: the holder's placed E1 text.
    pub(crate) fn message_text(&self, index: usize, world: &crate::World) -> String {
        let Some(placed) = self.entities[index].origin.placed() else {
            return String::new();
        };
        world.maps[0]
            .placements
            .get(placed)
            .and_then(|p| p.properties.iter().find(|(k, _)| k == "E1"))
            .and_then(|(_, v)| match v {
                PropertyValue::String(s) => Some(s.clone()),
                _ => None,
            })
            .unwrap_or_default()
    }
    pub(crate) fn message_sections(&self, index: usize, world: &crate::World) -> i64 {
        (text_rows(&self.message_text(index, world)) * 20 + 167)
            .div_euclid(168)
            .max(1)
    }
    /// grow_block.gd contact: the player (raised 2 px) touching an idle block grows it and
    /// knocks whatever stands on it.
    pub(crate) fn grow_contact(&mut self, index: usize) -> Result<(), Error> {
        let e = &self.entities[index];
        let Kind::Grow(g) = &e.kind else {
            return Ok(());
        };
        if e.status != 1 || g.phase != 0 || self.player.captured_by != 0 {
            return Ok(());
        }
        let Some(block) = g.solid(e) else {
            return Ok(());
        };
        let pb = self.player.bounds();
        let p = self.player.body;
        if p.x + pb[2] > block[0]
            && p.x + pb[0] < block[2]
            && p.y + pb[3] - 2 * S > block[1]
            && p.y + pb[1] - 2 * S < block[3]
        {
            if let Kind::Grow(g) = &mut self.entities[index].kind {
                g.phase = 1;
                g.ticks = 0;
                g.timer = 0;
            }
            self.knock_above_box(index, block)?;
        }
        Ok(())
    }
    /// item_block.gd bump_above: BUMP hits on whatever stands just above the block.
    fn bump_above(&mut self, index: usize) -> Result<(), Error> {
        let e = &self.entities[index];
        let b = self.block(index).bounds();
        let block = [
            e.body.x + b[0],
            e.body.y + b[1],
            e.body.x + b[2],
            e.body.y + b[3],
        ];
        self.knock_above_box(index, block)
    }
    /// BUMP hits on whatever overlaps `block` raised 8 px (item_block.gd bump_above and
    /// grow_block.gd knock_above), in table order.
    fn knock_above_box(&mut self, index: usize, block: [i64; 4]) -> Result<(), Error> {
        let probe = [block[0], block[1] - 8 * S, block[2], block[3] - 8 * S];
        self.bump_box(index, probe)
    }
    /// BUMP hits on whatever overlaps `probe` (near_query.gd strike with Hits.BUMP), in
    /// table order, skipping the striking entity at `index`.
    pub(crate) fn bump_box(&mut self, index: usize, probe: [i64; 4]) -> Result<(), Error> {
        let e = &self.entities[index];
        let token = e.origin.token();
        let from_x = e.body.x;
        let mut other = 0;
        while other < self.entities.len() {
            let current = other;
            other += 1;
            let o = &self.entities[current];
            let held = match &o.kind {
                Kind::Walker(w) => w.held == 1,
                Kind::Pickup(p) => p.held == 1,
                Kind::Star(p) => p.held == 1,
                Kind::Melon(m) => m.held == 1,
                _ => false,
            };
            let hidden = matches!(&o.kind, Kind::Walker(w) if w.hidden == 1);
            if o.origin.token() == token || o.status != 1 || held || hidden {
                continue;
            }
            // Types with a `hit`: actors, pickups, eggs, stilts, release clouds, blocks.
            let ob = match &o.kind {
                Kind::Walker(_) | Kind::Pickup(_) | Kind::Egg(_) | Kind::Cache(_) => {
                    crate::egg::entity_bounds(o)
                }
                Kind::Block(bl) => bl.bounds(),
                Kind::Stem(s) => s.bounds(),
                _ => continue,
            };
            let ob = [
                o.body.x + ob[0],
                o.body.y + ob[1],
                o.body.x + ob[2],
                o.body.y + ob[3],
            ];
            // registry.gd overlaps_box: open edges.
            if !(ob[2] > probe[0] && ob[0] < probe[2] && ob[3] > probe[1] && ob[1] < probe[3]) {
                continue;
            }
            self.bump_hit(current, from_x)?;
        }
        Ok(())
    }
    /// Each type's `hit` with Hits.BUMP.
    fn bump_hit(&mut self, index: usize, from_x: i64) -> Result<(), Error> {
        // sneak_thief.gd hit with Hits.BUMP: struck.
        if matches!(&self.entities[index].kind, Kind::Walker(w) if w.kind == crate::actors::ActorKind::Thief)
        {
            return self.thief_struck(index, from_x);
        }
        // hanging_roller.gd hit ignores BUMP; enemy_pellet.gd has no hit.
        if matches!(&self.entities[index].kind, Kind::Walker(w) if [crate::actors::ActorKind::Roller, crate::actors::ActorKind::Pellet].contains(&w.kind))
        {
            return Ok(());
        }
        let e = &mut self.entities[index];
        match &mut e.kind {
            Kind::Walker(w) if w.kind == crate::actors::ActorKind::Stilt => {
                w.stilt_knock(&mut e.body, &mut e.facing, from_x);
            }
            // needle_juggler.gd has no `hit`.
            Kind::Walker(w) if w.kind == crate::actors::ActorKind::Juggler => {}
            // leap_bulk.gd hit: defeat (with its loot).
            Kind::Walker(w) if w.kind == crate::actors::ActorKind::Bulk => {
                self.bulk_defeat(index)?
            }
            // armored_walker.gd hit: BUMP is not one of its kinds.
            Kind::Walker(w) if w.kind == crate::actors::ActorKind::Armored => {}
            // shell_walker.gd hit: any other kind removes it (with on_remove).
            Kind::Walker(w)
                if [
                    crate::actors::ActorKind::Shell,
                    crate::actors::ActorKind::Runner,
                ]
                .contains(&w.kind) =>
            {
                self.shell_remove(index);
            }
            // spear_guard.gd hit: the spear drops and it is removed.
            Kind::Walker(w) if w.kind == crate::actors::ActorKind::Spear => {
                w.has_spear = 0;
                w.remove(&mut e.status, &mut e.can_respawn);
            }
            Kind::Walker(w) => {
                if w.held == 0 && e.status == 1 {
                    if w.kind == crate::actors::ActorKind::Plant {
                        return Err(Error::Unsupported {
                            requirements: vec!["block bump under a plant (on_remove)".into()],
                        });
                    }
                    w.remove(&mut e.status, &mut e.can_respawn);
                }
            }
            Kind::Egg(_) => self.egg_bump(index),
            // item_stem.gd hit with BUMP: a hop.
            Kind::Stem(_) => e.body.vy = -384 * 60,
            // pickup.gd and release_cloud.gd ignore BUMP; item_block.gd hit is EGG only.
            _ => {}
        }
        Ok(())
    }
    /// item_egg.gd active_count: carried eggs plus loose on-screen eggs.
    pub(crate) fn active_eggs(&self, centre: crate::Position) -> i64 {
        let mut count = self.player.food.eggs;
        for e in &self.entities {
            if let Kind::Egg(_) = &e.kind {
                if e.status == 1 && e.collected == 0 && self.egg_on_screen(e, centre) {
                    count += 1;
                }
            }
        }
        count
    }
}

/// item_block.gd text_rows: message paging at a fixed reference width.
pub(crate) fn text_rows(text: &str) -> i64 {
    let mut rows = 1;
    let mut width: i64 = 0;
    for line in text.split('\n') {
        if width < 0 {
            rows += 1;
        }
        width = 0;
        for word in line.split(' ') {
            let size: i64 = word.chars().map(glyph_width).sum();
            if width != 0 && width + 16 + size > 304 {
                rows += 1;
                width = 0;
            } else if width != 0 {
                width += 16;
            }
            width += size;
            while width > 304 {
                rows += 1;
                width -= 304;
            }
        }
        width = -1;
    }
    rows
}

fn glyph_width(c: char) -> i64 {
    if ".,;:'|".contains(c) {
        6
    } else if "Ii$()[]\\/\"°{}²³".contains(c) {
        12
    } else if "1=<>§".contains(c) {
        14
    } else {
        16
    }
}
