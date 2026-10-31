//! dice_block.gd (o33 switch, o34 block): grouped switch blocks and the blocks they
//! toggle. A strike from below or a thrown egg on a switch flips every block and switch
//! of its group: solid blocks become passable outlines and outlines become solid once the
//! player has left them. The struck switch lifts briefly and pops bodies above it.
use crate::{body::Probe, entity::Kind, state::Run, Error, Placement, PropertyValue, SCALE as S};

/// 0.1 s up and 0.1 s back.
const BUMP_TICKS: i64 = 12;
const LIFT: i64 = 32 * S;
const MAX_GROUP: i64 = 1_000_000;
const BOX: [i64; 4] = [-16 * S, -16 * S, 16 * S, 16 * S];

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Dice {
    /// o33: the switch; o34: a toggled block.
    pub switch: bool,
    pub group: i64,
    pub on: i64,
    pub solid_ready: i64,
    pub home_y: i64,
    pub busy: i64,
}

fn refuse(why: String) -> Error {
    Error::Unsupported {
        requirements: vec![format!("dice block {why}")],
    }
}

impl Dice {
    /// dice_block.gd prepare + create.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        // registry.gd numeric_option, a blank E4 reading as "0".
        let group = match p.properties.iter().find(|(k, _)| k == "E4").map(|(_, v)| v) {
            None => 0.0,
            Some(PropertyValue::String(s)) if s.trim().is_empty() => 0.0,
            Some(PropertyValue::String(s)) => s
                .trim()
                .parse::<f64>()
                .map_err(|_| refuse("invalid group".into()))?,
            Some(PropertyValue::Number(v)) => *v,
            Some(_) => return Err(refuse("invalid group".into())),
        };
        if !group.is_finite() {
            return Err(refuse("invalid group".into()));
        }
        if group.abs() > MAX_GROUP as f64 {
            return Err(refuse(
                "group E4 out of range (degrades to a placeholder)".into(),
            ));
        }
        let switch = p.code == "o33";
        let on = if switch {
            0
        } else {
            let form = match p.properties.iter().find(|(k, _)| k == "F").map(|(_, v)| v) {
                None => 0.0,
                Some(PropertyValue::Number(v)) if v.is_finite() && *v == v.floor() => *v,
                Some(_) => return Err(refuse("invalid block form".into())),
            };
            if !(0.0..=1.0).contains(&form) {
                return Err(refuse(format!(
                    "block form F={form} (degrades to a placeholder)"
                )));
            }
            i64::from(form == 0.0)
        };
        Ok(Self {
            switch,
            group: group as i64,
            on,
            solid_ready: 1 - on,
            home_y: p.position.y,
            busy: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        BOX
    }
    /// dice_block.gd solid_box: a switch is always solid; a block while off and ready.
    pub fn solid(&self, status: i64, body: crate::body::Body) -> Option<[i64; 4]> {
        (status == 1 && (self.switch || (self.on == 0 && self.solid_ready != 0))).then_some([
            body.x + BOX[0],
            body.y + BOX[1],
            body.x + BOX[2],
            body.y + BOX[3],
        ])
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "group" => self.group,
            "on" => self.on,
            "solid_ready" => self.solid_ready,
            "home_y" => self.home_y,
            "busy" => self.busy,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "group" => self.group = value,
            "on" => self.on = value,
            "solid_ready" => self.solid_ready = value,
            "home_y" => self.home_y = value,
            "busy" => self.busy = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self, y: i64) -> bool {
        self.group.abs() <= MAX_GROUP
            && [0, 1].contains(&self.on)
            && [0, 1].contains(&self.solid_ready)
            && (0..=BUMP_TICKS).contains(&self.busy)
            && y <= self.home_y
            && y >= self.home_y - LIFT
    }
}

impl Run {
    /// dice_block.gd overlaps_player (registry.gd overlaps_box: open edges).
    fn dice_overlaps(&self, index: usize, player: [i64; 4]) -> bool {
        let e = &self.entities[index];
        e.body.x + BOX[2] > player[0]
            && e.body.x + BOX[0] < player[2]
            && e.body.y + BOX[3] > player[1]
            && e.body.y + BOX[1] < player[3]
    }
    fn player_box(&self) -> [i64; 4] {
        let b = self.player.bounds();
        let p = self.player.body;
        [p.x + b[0], p.y + b[1], p.x + b[2], p.y + b[3]]
    }
    /// dice_block.gd step: a block that turned off waits for the player to leave it; a
    /// struck switch lifts and drops back.
    pub(crate) fn dice_step(&mut self, index: usize) {
        let player = self.player_box();
        let Kind::Dice(d) = &self.entities[index].kind else {
            return;
        };
        if !d.switch {
            if d.on == 0 && d.solid_ready == 0 {
                let ready = i64::from(!self.dice_overlaps(index, player));
                if let Kind::Dice(d) = &mut self.entities[index].kind {
                    d.solid_ready = ready;
                }
            }
            return;
        }
        let e = &mut self.entities[index];
        let Kind::Dice(d) = &mut e.kind else {
            return;
        };
        if d.busy != 0 {
            d.busy -= 1;
            let offset = (BUMP_TICKS - d.busy).min(d.busy);
            e.body.y = d.home_y - LIFT * offset / (BUMP_TICKS / 2);
        }
    }
    /// dice_block.gd bump from below (side 0), with the player's box at the bump.
    pub(crate) fn dice_bump(
        &mut self,
        index: usize,
        player: [i64; 4],
        map: &Probe,
    ) -> Result<(), Error> {
        if matches!(&self.entities[index].kind, Kind::Dice(d) if d.switch) {
            self.dice_trigger(index, player, Some(map))?;
        }
        Ok(())
    }
    /// dice_block.gd projectile_contact for a thrown egg: 0 passes an outline, a block or
    /// a lifted switch is solid (3), a switch flips its group and takes the egg (1).
    pub(crate) fn dice_projectile_contact(
        &mut self,
        index: usize,
        map: &Probe,
    ) -> Result<i64, Error> {
        let e = &self.entities[index];
        let Kind::Dice(d) = &e.kind else {
            return Ok(0);
        };
        if d.solid(e.status, e.body).is_none() {
            return Ok(0);
        }
        if !d.switch || d.busy != 0 {
            return Ok(3);
        }
        let player = self.player_box();
        self.dice_trigger(index, player, Some(map))?;
        Ok(1)
    }
    /// dice_block.gd trigger: flip the group, lift the switch and pop what stands on it.
    fn dice_trigger(
        &mut self,
        index: usize,
        player: [i64; 4],
        map: Option<&Probe>,
    ) -> Result<bool, Error> {
        let e = &self.entities[index];
        let Kind::Dice(d) = &e.kind else {
            return Ok(false);
        };
        if !d.switch || d.busy != 0 || e.status != 1 {
            return Ok(false);
        }
        let group = d.group;
        for other in 0..self.entities.len() {
            let Kind::Dice(o) = &self.entities[other].kind else {
                continue;
            };
            if o.group != group {
                continue;
            }
            let block = !o.switch;
            let overlapping = block && self.dice_overlaps(other, player);
            if let Kind::Dice(o) = &mut self.entities[other].kind {
                o.on = 1 - o.on;
                if block {
                    o.solid_ready = i64::from(o.on == 0 && !overlapping);
                }
            }
            // An outline that turns solid grows another entity's box.
            if let (true, Some(map)) = (block, map) {
                self.refresh_block_solid(other, map);
            }
        }
        let e = &mut self.entities[index];
        if let Kind::Dice(d) = &mut e.kind {
            d.busy = BUMP_TICKS;
        }
        let probe = [
            e.body.x - 16 * S,
            e.body.y - 24 * S,
            e.body.x + 16 * S,
            e.body.y + 8 * S,
        ];
        self.bump_box(index, probe)?;
        Ok(true)
    }
}
