//! item_stem.gd (o17): a periodic producer that releases eggs (o7) or health drops (o4)
//! into the saved runtime table; a pound landing nearby switches it to a fast burst.
use crate::{
    body::Body,
    egg::Egg,
    entity::{Entity, Kind},
    items::Star,
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};
const BOUNDS: [i64; 4] = [-10 * S, -24 * S, 10 * S, 16 * S];

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Stem {
    /// item_stem.gd PAYLOADS index: 0 o7, 1 o4, 2 e40, 3 nothing.
    pub payload: i64,
    pub phase: i64,
    pub fast: i64,
    pub fast_loop: i64,
    pub impact_cursor: i64,
    pub unavailable: i64,
}

impl Stem {
    /// item_stem.gd prepare + create.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let payload = match p.properties.iter().find(|(k, _)| k == "E1").map(|(_, v)| v) {
            None => 0,
            Some(PropertyValue::String(s)) => match s.as_str() {
                "" | "o7" => 0,
                "o4" => 1,
                "e40" => 2,
                _ => 3,
            },
            Some(_) => {
                return Err(Error::Unsupported {
                    requirements: vec!["o17 producer payload".into()],
                })
            }
        };
        Ok(Self {
            payload,
            phase: 0,
            fast: 0,
            fast_loop: 0,
            impact_cursor: 0,
            unavailable: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        BOUNDS
    }
    /// item_stem.gd activate: the first loop begins at frame one.
    pub fn activate(&mut self, impact: i64) {
        self.phase = 3;
        self.impact_cursor = impact;
    }
    fn period(&self) -> i64 {
        if self.fast_loop != 0 {
            30
        } else {
            66
        }
    }
    /// item_stem.gd view_state: (animation, frame).
    pub fn view(&self) -> (&'static str, i64) {
        let mut frame = 0;
        if self.phase >= 3 {
            let tail = if self.fast_loop != 0 { 21 } else { 57 };
            frame = if self.phase < tail {
                1 + (self.phase - 3) / 6
            } else {
                (if self.fast_loop != 0 { 4 } else { 10 }) + (self.phase - tail) / 3
            };
        }
        (
            if self.fast_loop != 0 {
                "FastLoop"
            } else {
                "Loop"
            },
            frame,
        )
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "payload" => self.payload,
            "phase" => self.phase,
            "fast" => self.fast,
            "fast_loop" => self.fast_loop,
            "impact_cursor" => self.impact_cursor,
            "unavailable" => self.unavailable,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "payload" => self.payload = value,
            "phase" => self.phase = value,
            "fast" => self.fast = value,
            "fast_loop" => self.fast_loop = value,
            "impact_cursor" => self.impact_cursor = value,
            "unavailable" => self.unavailable = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self, body: Body) -> bool {
        (0..=3).contains(&self.payload)
            && (0..self.period()).contains(&self.phase)
            && [0, 1].contains(&self.fast)
            && [0, 1].contains(&self.fast_loop)
            && self.impact_cursor >= 0
            && [0, 1].contains(&self.unavailable)
            && (-1024 * 60..=1024 * 60).contains(&body.vx)
            && (-1024 * 60..=1024 * 60).contains(&body.vy)
    }
}

impl Run {
    fn stem(&mut self, index: usize) -> &mut Stem {
        match &mut self.entities[index].kind {
            Kind::Stem(s) => s,
            _ => unreachable!("stem index"),
        }
    }
    /// item_stem.gd consume_requests: a new pound impact switches a standing producer to
    /// a burst. Its step and the registry's entity consumer pass both run it.
    pub(crate) fn stem_consume(&mut self, index: usize) {
        let impact = self.player.impact;
        let status = self.entities[index].status;
        let s = self.stem(index);
        if s.impact_cursor != impact {
            s.impact_cursor = impact;
            if status == 1 && impact != 0 {
                s.fast = 1;
                if s.fast_loop == 0 && (3..51).contains(&s.phase) {
                    s.phase = 51;
                }
            }
        }
    }
    /// item_stem.gd step.
    pub(crate) fn stem_step(
        &mut self,
        index: usize,
        map: &crate::body::Probe,
        centre: crate::Position,
    ) -> Result<(), Error> {
        self.stem_consume(index);
        let e = &mut self.entities[index];
        e.body.fall_item(map, BOUNDS, 2048, 704 * 60, false);
        let s = self.stem(index);
        s.phase += 1;
        if s.phase < s.period() {
            return Ok(());
        }
        let payload = s.payload;
        let available = match payload {
            // item_stem.gd amount: egg and hopper producers both count active eggs.
            0 | 2 => (6 - self.active_eggs(centre)).max(0),
            1 => (30 - self.player.life.health).max(0),
            _ => 0,
        };
        let s = self.stem(index);
        let burst = (if s.fast != 0 { 10 } else { 1 }).min(available);
        s.fast_loop = s.fast;
        for _ in 0..burst {
            self.stem_release(index)?;
        }
        let s = self.stem(index);
        if s.fast != 0 && burst >= 2 {
            s.fast = 0;
            s.fast_loop = 0;
        }
        s.phase = 0;
        Ok(())
    }
    /// item_stem.gd release: registry.gd spawn_dynamic of the payload above the stem.
    fn stem_release(&mut self, index: usize) -> Result<(), Error> {
        let s = self.stem(index);
        if s.unavailable != 0 {
            return Ok(());
        }
        let payload = s.payload;
        let gravity = [1600, 1024, 1536, 1600][payload as usize];
        let vx = self.rng.ticks(-176 * 60, 176 * 60);
        let vy = -crate::math::root(2 * gravity * 144 * 3600);
        if payload == 3 {
            // An unknown payload code has no type; spawn_dynamic fails.
            self.stem(index).unavailable = 1;
            return Ok(());
        }
        let Ok(serial) = self.next_serial() else {
            self.stem(index).unavailable = 1;
            return Ok(());
        };
        let e = &self.entities[index];
        let body = Body {
            x: e.body.x,
            y: e.body.y - 40 * S,
            vx,
            vy,
        };
        // spike_hopper.gd create through registry.gd spawn_dynamic: a runtime enemy with
        // the next family index; spiked bodies collide (no pickup delay or ghosting).
        if payload == 2 {
            let hopper = crate::actors::Actor::new(
                crate::actors::ActorKind::Hopper,
                0,
                0,
                crate::Position {
                    x: body.x,
                    y: body.y,
                },
            );
            let family = self.entities.iter().filter(|e| e.is_enemy()).count() as i64;
            let mut row = Entity::dynamic(serial, Kind::Walker(Box::new(hopper)), body, -1, 8);
            row.family_index = family;
            self.dynamic_serial = serial + 1;
            self.entities.push(row);
            return Ok(());
        }
        let kind = if payload == 0 {
            let mut egg = Egg::new(0);
            egg.pickup_delay = 6;
            egg.ignore_terrain = 1;
            Kind::Egg(egg)
        } else {
            Kind::Star(Star {
                phase: 10,
                pickup_delay: 6,
                ignore_terrain: 1,
                wait_for_land: 1,
                ..Star::default()
            })
        };
        let mut row = Entity::dynamic(serial, kind, body, -1, 7);
        row.can_despawn = 1;
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        Ok(())
    }
}
