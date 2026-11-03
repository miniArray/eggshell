//! Checkpoint contact, frozen awards, saved recovery and row-flag retention.
use crate::{
    entity::{Entity, Kind, Origin},
    player::Player,
    state::Run,
    Error, Placement, Position, PropertyValue, SCALE as S,
};
fn refuse(reason: &str) -> Error {
    Error::Unsupported {
        requirements: vec![format!("checkpoint: {reason}")],
    }
}
#[derive(Clone, Debug)]
pub(crate) struct Marker {
    pub respawn: Position,
    pub health_bonus: i64,
}
impl Marker {
    pub fn new(source: &Placement) -> Result<Self, Error> {
        let coordinate = |key: &str| -> Result<i64, Error> {
            let raw = source
                .properties
                .iter()
                .find(|(k, _)| k == key)
                .map(|(_, v)| v);
            let number = match raw {
                Some(PropertyValue::Number(v)) => Some(*v),
                Some(PropertyValue::String(v)) => v.trim().parse::<f64>().ok(),
                _ => None,
            }
            .filter(|v| v.is_finite())
            .ok_or_else(|| refuse("invalid required respawn position"))?;
            let units = (number * S as f64).round();
            if !units.is_finite() || units.abs() > (i64::MAX / 16384) as f64 {
                return Err(refuse("respawn coordinate headroom"));
            }
            Ok(units as i64)
        };
        Ok(Self {
            respawn: Position {
                x: coordinate("E1")?,
                y: coordinate("E2")?,
            },
            health_bonus: if source.variant == 1 { 30 } else { 10 },
        })
    }
    pub fn field(&self, name: &str) -> Option<i64> {
        Some(match name {
            "respawn_x" => self.respawn.x,
            "respawn_y" => self.respawn.y,
            "health_bonus" => self.health_bonus,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, name: &str, value: i64) -> bool {
        let slot = match name {
            "respawn_x" => &mut self.respawn.x,
            "respawn_y" => &mut self.respawn.y,
            "health_bonus" => &mut self.health_bonus,
            _ => return false,
        };
        *slot = value;
        true
    }
    pub fn valid(&self) -> bool {
        [10, 30].contains(&self.health_bonus)
            && [self.respawn.x, self.respawn.y]
                .iter()
                .all(|v| (-(i64::MAX / 16384)..=i64::MAX / 16384).contains(v))
    }
}
#[derive(Clone, Debug)]
pub(crate) struct Memory {
    pub id: i64,
    pub map: i64,
    pub position: Position,
    pub health: i64,
    pub redcoins: i64,
    pub flowers: i64,
    pub play_ticks: i64,
}
impl Default for Memory {
    fn default() -> Self {
        Self {
            id: 0,
            map: 1,
            position: Position::default(),
            health: 10,
            redcoins: 0,
            flowers: 0,
            play_ticks: 0,
        }
    }
}
impl Memory {
    pub fn field(&self, name: &str) -> Option<i64> {
        Some(match name {
            "checkpoint_id" => self.id,
            "checkpoint_map" => self.map,
            "checkpoint_x" => self.position.x,
            "checkpoint_y" => self.position.y,
            "checkpoint_health" => self.health,
            "checkpoint_redcoins" => self.redcoins,
            "checkpoint_flowers" => self.flowers,
            "checkpoint_play_ticks" => self.play_ticks,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, name: &str, value: i64) -> bool {
        let slot = match name {
            "checkpoint_id" => &mut self.id,
            "checkpoint_map" => &mut self.map,
            "checkpoint_x" => &mut self.position.x,
            "checkpoint_y" => &mut self.position.y,
            "checkpoint_health" => &mut self.health,
            "checkpoint_redcoins" => &mut self.redcoins,
            "checkpoint_flowers" => &mut self.flowers,
            "checkpoint_play_ticks" => &mut self.play_ticks,
            _ => return false,
        };
        *slot = value;
        true
    }
    pub fn valid(&self, entities: &[Entity]) -> bool {
        self.id >= 0
            && self.map == 1
            && (10..=30).contains(&self.health)
            && self.redcoins >= 0
            && self.flowers >= 0
            && self.play_ticks >= 0
            && [self.position.x, self.position.y]
                .iter()
                .all(|v| (-(i64::MAX / 16384)..=i64::MAX / 16384).contains(v))
            && (self.id == 0
                || entities.iter().any(|e| {
                    e.origin.index() + 1 == self.id && matches!(e.kind, Kind::Checkpoint(_))
                }))
    }
    pub fn step(&mut self, player: &mut Player) {
        player.life_ticks = (player.life_ticks - 1).max(0);
        if player.life_ticks != 0 {
            return;
        }
        if player.life.checkpoint_awards > 0 && player.life.health < 30 {
            player.life.health += 1;
            player.life.checkpoint_awards -= 1;
            if player.life.checkpoint_awards > 0 && player.life.health < 30 {
                player.life_ticks = 6;
                return;
            }
            player.life.checkpoint_awards = 0;
            self.health = player.life.health.max(10);
            player.life_ticks = 45;
        } else {
            player.life_phase = 0;
        }
    }
}
impl Run {
    pub(crate) fn touch_checkpoint(&mut self, index: usize) -> bool {
        let e = &mut self.entities[index];
        let Kind::Checkpoint(marker) = &e.kind else {
            return false;
        };
        let p = &mut self.player;
        if p.life_phase != 0
            || p.captured_by != 0
            || e.collected != 0
            || (p.body.x - e.body.x).abs() >= 16 * S
            || p.body.y <= e.body.y - 48 * S
            || p.body.y - 56 * S >= e.body.y + 48 * S
        {
            return false;
        }
        let Origin::Placed(source) = e.origin else {
            return false;
        };
        e.collected = 1;
        self.checkpoint.id = source as i64 + 1;
        self.checkpoint.map = 1;
        self.checkpoint.position = marker.respawn;
        self.checkpoint.redcoins = self.redcoins;
        self.checkpoint.flowers = self.flowers;
        self.checkpoint.play_ticks = self.play_ticks;
        p.life.checkpoint_awards = marker.health_bonus.clamp(0, 30);
        if p.life.separated != 0 {
            p.life.health_wait = 60;
        }
        p.life_phase = 6;
        if p.life.checkpoint_awards > 0 && p.life.health < 30 {
            p.life_ticks = 6;
        } else {
            p.life.checkpoint_awards = 0;
            self.checkpoint.health = p.life.health.max(10);
            p.life_ticks = 45;
        }
        for entity in &mut self.entities {
            entity.checkpoint_collected = entity.collected;
        }
        true
    }
}
