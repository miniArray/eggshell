//! Typed row identity/common fields. The placed prefix and runtime suffix share one table.
use crate::{
    actors::{Actor, ActorKind},
    body::Body,
    items::{Pickup, PickupKind, Star},
    pad::Pad,
    Placement, World, SCALE as S,
};
use std::borrow::Cow;
pub(crate) const TOKEN_BASE: i64 = 1_000_000;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Origin {
    Placed(usize),
    Runtime(i64),
}
impl Origin {
    pub fn placed(self) -> Option<usize> {
        if let Self::Placed(index) = self {
            Some(index)
        } else {
            None
        }
    }
    pub fn index(self) -> i64 {
        self.placed().map(|v| v as i64).unwrap_or(-1)
    }
    pub fn token(self) -> i64 {
        match self {
            Self::Placed(i) => i as i64 + 1,
            Self::Runtime(serial) => TOKEN_BASE + serial,
        }
    }
}
#[derive(Clone, Debug)]
pub(crate) enum Kind {
    Goal,
    Checkpoint(crate::checkpoint::Marker),
    Decor,
    Pickup(Pickup),
    Star(Star),
    Bridge,
    Pad(Pad),
    Walker(Actor),
}
#[derive(Clone, Debug)]
pub(crate) struct Entity {
    pub origin: Origin,
    pub family_index: i64,
    pub body: Body,
    pub facing: i64,
    pub status: i64,
    pub offscreen: i64,
    pub collected: i64,
    pub checkpoint_collected: i64,
    pub spawn_mode: i64,
    pub can_despawn: i64,
    pub can_respawn: i64,
    pub layer: i64,
    pub activation_x: i64,
    pub activation_y: i64,
    pub despawn_radius: i64,
    pub respawn_radius: i64,
    pub kind: Kind,
}
impl Entity {
    pub fn placed(source: usize, p: &Placement, kind: Kind, family_index: i64) -> Self {
        let lifecycle = i64::from(matches!(kind, Kind::Walker(_) | Kind::Star(_)));
        let layer = if matches!(kind, Kind::Walker(_)) {
            8
        } else {
            7
        };
        Self {
            origin: Origin::Placed(source),
            family_index,
            body: Body {
                x: p.position.x,
                y: p.position.y,
                ..Body::default()
            },
            facing: if p.mirror == 1 { 1 } else { -1 },
            status: if lifecycle != 0 { 0 } else { 1 },
            offscreen: 0,
            collected: 0,
            checkpoint_collected: 0,
            spawn_mode: lifecycle,
            can_despawn: lifecycle,
            can_respawn: lifecycle,
            layer,
            activation_x: 416 * S,
            activation_y: 224 * S,
            despawn_radius: 832 * S,
            respawn_radius: 624 * S,
            kind,
        }
    }
    pub fn dynamic(serial: i64, kind: Kind, body: Body, facing: i64, layer: i64) -> Self {
        let can_despawn = i64::from(matches!(kind, Kind::Walker(_)));
        Self {
            origin: Origin::Runtime(serial),
            family_index: 0,
            body,
            facing,
            status: 1,
            offscreen: 0,
            collected: 0,
            checkpoint_collected: 0,
            spawn_mode: 0,
            can_despawn,
            can_respawn: 0,
            layer,
            activation_x: 416 * S,
            activation_y: 224 * S,
            despawn_radius: 832 * S,
            respawn_radius: 624 * S,
            kind,
        }
    }
    pub fn source<'a>(&self, world: &'a World) -> Option<&'a Placement> {
        self.origin.placed().map(|i| &world.maps[0].placements[i])
    }
    pub fn code<'a>(&'a self, world: &'a World) -> &'a str {
        if let Some(p) = self.source(world) {
            &p.code
        } else {
            match &self.kind {
                Kind::Walker(a) => match a.kind {
                    ActorKind::Walker => "e1",
                    ActorKind::Flyer => "e2",
                    ActorKind::Flower => "e3",
                    ActorKind::Plant => "e5",
                    ActorKind::Stilt => "e35",
                },
                Kind::Pickup(p) => match p.kind {
                    PickupKind::Coin => "o1",
                    PickupKind::RedCoin => "o2",
                    PickupKind::Flower => "o3",
                },
                Kind::Star(_) => "o4",
                _ => unreachable!("runtime constructors admit only dynamic types"),
            }
        }
    }
    pub fn id<'a>(&'a self, world: &'a World) -> Cow<'a, str> {
        match self.origin {
            Origin::Placed(i) => Cow::Borrowed(&world.maps[0].placements[i].id),
            Origin::Runtime(serial) => Cow::Owned(format!("+{serial}")),
        }
    }
    pub fn position_at_spawn(&self, world: &World) -> crate::Position {
        if let Some(p) = self.source(world) {
            p.position
        } else if let Kind::Walker(a) = &self.kind {
            crate::Position {
                x: a.spawn_x,
                y: a.spawn_y,
            }
        } else {
            crate::Position {
                x: self.body.x,
                y: self.body.y,
            }
        }
    }
    pub(crate) fn lifecycle(
        &mut self,
        map: &crate::body::Probe,
        centre: crate::Position,
        player_x: i64,
        rng: &mut crate::math::Rng,
    ) -> Result<bool, crate::Error> {
        let awake = self.status == 1;
        let held = match &self.kind {
            Kind::Walker(a) => a.held,
            Kind::Pickup(p) => p.held,
            Kind::Star(p) => p.held,
            _ => 0,
        };
        if self.status == 3 || held == 1 || (awake && self.can_despawn == 0) {
            return Ok(awake && self.status == 1);
        }
        let far = (self.body.x - centre.x).abs() > self.despawn_radius
            || (self.body.y - centre.y).abs() > self.despawn_radius;
        let Origin::Placed(index) = self.origin else {
            if awake && self.can_despawn != 0 && far {
                self.status = 3;
            }
            return Ok(awake && self.status == 1);
        };
        let source = &map.placements[index];
        if awake && self.can_despawn != 0 && far {
            self.status = 2;
            self.offscreen = 0;
        }
        if self.status == 2 && self.can_respawn != 0 {
            if (source.position.x - centre.x).abs() > self.activation_x
                || (source.position.y - centre.y).abs() > self.activation_y
            {
                self.offscreen = 1;
            }
            if self.offscreen != 0
                && (source.position.x - centre.x).abs() < self.respawn_radius
                && (source.position.y - centre.y).abs() < self.respawn_radius
            {
                let kind = match &self.kind {
                    Kind::Walker(a) => {
                        let mut a =
                            Actor::new(a.kind, source.variant, source.mirror, source.position);
                        if a.kind == ActorKind::Stilt {
                            a.height = crate::stilt::height(source)?;
                        }
                        Kind::Walker(a)
                    }
                    Kind::Star(_) => Kind::Star(Star::default()),
                    Kind::Pickup(p) => {
                        Kind::Pickup(Pickup::new(p.kind, source.variant, source.position.y))
                    }
                    Kind::Pad(_) => Kind::Pad(Pad::default()),
                    other => other.clone(),
                };
                let mut fresh = Self::placed(index, source, kind, self.family_index);
                fresh.collected = self.collected;
                fresh.checkpoint_collected = self.checkpoint_collected;
                *self = fresh;
            }
        }
        if self.status == 0 {
            let b = match &self.kind {
                Kind::Walker(a) => a.body_bounds(self.facing),
                Kind::Star(p) => p.bounds(),
                Kind::Pickup(p) => p.bounds(),
                Kind::Pad(_) => {
                    let crate::PreparedPlacement::Pad { large, .. } = source.prepared else {
                        unreachable!("placed pad")
                    };
                    crate::pad::bounds(large)
                }
                _ => [0; 4],
            };
            if self.body.x + b[2] > centre.x - self.activation_x
                && self.body.x + b[0] < centre.x + self.activation_x
                && self.body.y + b[3] > centre.y - self.activation_y
                && self.body.y + b[1] < centre.y + self.activation_y
            {
                self.status = 1;
                if source.mirror == 2 {
                    self.facing = if player_x < self.body.x { -1 } else { 1 };
                }
                if let Kind::Walker(a) = &mut self.kind {
                    a.activate(self.facing, rng);
                }
            }
        }
        Ok(awake && self.status == 1)
    }
    pub fn common_field(&self, name: &str) -> Option<i64> {
        Some(match name {
            "source_index" => self.origin.index(),
            "token" => self.origin.token(),
            "map_index" => 1,
            "family_index" => self.family_index,
            "x" => self.body.x,
            "y" => self.body.y,
            "vx" => self.body.vx,
            "vy" => self.body.vy,
            "facing" => self.facing,
            "status" => self.status,
            "offscreen" => self.offscreen,
            "collected" => self.collected,
            "checkpoint_collected" => self.checkpoint_collected,
            "spawn_mode" => self.spawn_mode,
            "can_despawn" => self.can_despawn,
            "can_respawn" => self.can_respawn,
            "layer" => self.layer,
            "activation_x" => self.activation_x,
            "activation_y" => self.activation_y,
            "despawn_radius" => self.despawn_radius,
            "respawn_radius" => self.respawn_radius,
            _ => return None,
        })
    }
    pub fn set_common(&mut self, name: &str, value: i64) -> bool {
        let target = match name {
            "x" => &mut self.body.x,
            "y" => &mut self.body.y,
            "vx" => &mut self.body.vx,
            "vy" => &mut self.body.vy,
            "facing" => &mut self.facing,
            "status" => &mut self.status,
            "offscreen" => &mut self.offscreen,
            "collected" => &mut self.collected,
            "checkpoint_collected" => &mut self.checkpoint_collected,
            "spawn_mode" => &mut self.spawn_mode,
            "can_despawn" => &mut self.can_despawn,
            "can_respawn" => &mut self.can_respawn,
            "layer" => &mut self.layer,
            "activation_x" => &mut self.activation_x,
            "activation_y" => &mut self.activation_y,
            "despawn_radius" => &mut self.despawn_radius,
            "respawn_radius" => &mut self.respawn_radius,
            _ => return false,
        };
        *target = value;
        true
    }
}
