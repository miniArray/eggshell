//! One typed authoritative table. Schema-indexed arrays exist only at codec boundaries.
use crate::{
    body::Body,
    math::{screen_centre, Rng},
    player::{Player, Sound},
    schema::{Field, Schema},
    wire::{WireEntity, WireSnapshot},
    Error, Position, World, SCALE as S,
};
#[derive(Clone, Debug, Default)]
pub(crate) struct Walker {
    pub phase: i64,
    pub timer: i64,
    pub cycles: i64,
    pub mode: i64,
    pub started: i64,
    pub contact: i64,
}
#[derive(Clone, Debug)]
pub(crate) enum Kind {
    Goal,
    Walker(Walker),
}
#[derive(Clone, Debug)]
pub(crate) struct Entity {
    pub source: usize,
    pub body: Body,
    pub facing: i64,
    pub status: i64,
    pub offscreen: i64,
    pub kind: Kind,
}
#[derive(Clone, Debug)]
pub(crate) struct Run {
    pub frame: i64,
    pub camera: Position,
    pub rng: Rng,
    pub player: Player,
    pub entities: Vec<Entity>,
    pub sound: Sound,
    pub play_ticks: i64,
    pub total_play_ticks: i64,
    pub attempt_ticks: i64,
    pub coins: i64,
    pub goal_reached: i64,
}
const WALKER_BOX: [i64; 4] = [-10 * S, -18 * S, 10 * S, 16 * S];
fn unsupported(reason: &str) -> Error {
    Error::Unsupported {
        requirements: vec![reason.into()],
    }
}
fn overlap(a: Body, ab: [i64; 4], b: Body, bb: [i64; 4]) -> bool {
    a.x + ab[2] > b.x + bb[0]
        && a.x + ab[0] < b.x + bb[2]
        && a.y + ab[3] > b.y + bb[1]
        && a.y + ab[1] < b.y + bb[3]
}
impl Run {
    pub fn create(world: &World, stats: &mut crate::Stats) -> Result<Self, Error> {
        let identity = crate::schema::decode_hash(
            "75c8a5af059df0550d21119c4bcd962a46c1549839da6d09da9aa74cf7b0e0fd",
        )?;
        if world.identity != identity {
            return Err(unsupported("Only unchanged Stride dry-land fixture is admitted; target gameplay closure is not implemented"));
        }
        let mut entities = Vec::new();
        for (source, p) in world.maps[0].placements.iter().enumerate() {
            let kind = match p.code.as_str() {
                "o5" => Kind::Goal,
                "e1" if p.variant == 0 && p.mirror == 0 && p.rotation == 0 => {
                    Kind::Walker(Walker::default())
                }
                _ => return Err(unsupported("fixture entity form")),
            };
            let status = if matches!(kind, Kind::Goal) { 1 } else { 0 };
            entities.push(Entity {
                source,
                body: Body {
                    x: p.position.x,
                    y: p.position.y,
                    ..Body::default()
                },
                facing: -1,
                status,
                offscreen: 0,
                kind,
            });
        }
        let player = Player::new(
            Body {
                x: world.spawn.x,
                y: world.spawn.y,
                ..Body::default()
            },
            world.spawn_facing,
        );
        let mut run = Self {
            frame: 0,
            camera: Position {
                x: world.spawn.x,
                y: world.spawn.y - 28 * S,
            },
            rng: Rng::from_saved(1)?,
            player,
            entities,
            sound: Sound::default(),
            play_ticks: 0,
            total_play_ticks: 0,
            attempt_ticks: 0,
            coins: 0,
            goal_reached: 0,
        };
        let map = crate::body::Probe::new(&world.maps[0]);
        for _ in 0..2 {
            run.entities_step(&map, stats);
            run.player.advance(&map, 0, 0, 0, 0, &mut run.sound);
            run.player.attach();
            run.player.finish(&map, 0);
        }
        stats.terrain_queries += map.terrain_queries.get();
        run.camera = Position {
            x: run.player.body.x,
            y: run.player.body.y - 28 * S,
        };
        Ok(run)
    }
    fn activate(w: &mut Walker, rng: &mut Rng) {
        w.timer = rng.ticks(60, 150);
        w.cycles = rng.cycles();
    }
    fn entities_step(&mut self, map: &crate::body::Probe, stats: &mut crate::Stats) {
        let centre = screen_centre(self.camera, map.width_pixels * S, map.height_pixels * S);
        for e in &mut self.entities {
            let Kind::Walker(w) = &mut e.kind else {
                continue;
            };
            let awake = e.status == 1;
            if e.status != 3 {
                let source = &map.placements[e.source];
                let far =
                    (e.body.x - centre.x).abs() > 832 * S || (e.body.y - centre.y).abs() > 832 * S;
                if e.status == 1 && far {
                    e.status = 2;
                    e.offscreen = 0;
                }
                if e.status == 2 {
                    if (source.position.x - centre.x).abs() > 416 * S
                        || (source.position.y - centre.y).abs() > 224 * S
                    {
                        e.offscreen = 1;
                    }
                    if e.offscreen != 0
                        && (source.position.x - centre.x).abs() < 624 * S
                        && (source.position.y - centre.y).abs() < 624 * S
                    {
                        *w = Walker::default();
                        e.body = Body {
                            x: source.position.x,
                            y: source.position.y,
                            ..Body::default()
                        };
                        e.facing = -1;
                        e.status = 0;
                        e.offscreen = 0;
                    }
                }
                if e.status == 0
                    && e.body.x + 10 * S > centre.x - 416 * S
                    && e.body.x - 10 * S < centre.x + 416 * S
                    && e.body.y + 16 * S > centre.y - 224 * S
                    && e.body.y - 18 * S < centre.y + 224 * S
                {
                    e.status = 1;
                    Self::activate(w, &mut self.rng);
                }
            }
            if !awake || e.status != 1 {
                continue;
            }
            stats.entity_steps += 1;
            w.started = 1;
            if w.timer == 0 && w.mode == 0 {
                Self::activate(w, &mut self.rng);
            }
            w.timer -= 1;
            if w.mode == 0 {
                w.phase += 1;
                if w.phase % 30 == 0 {
                    e.facing = -e.facing;
                }
                if w.timer == 0 {
                    w.mode = 1;
                    w.timer = 15;
                }
            } else if w.timer == 0 {
                if w.cycles != 0 {
                    w.cycles -= 1;
                    w.timer = 15;
                } else {
                    w.mode = 0;
                    w.phase = 0;
                    Self::activate(w, &mut self.rng);
                }
            }
            e.body.vx = if w.mode == 1 { e.facing * 48 * 60 } else { 0 };
            let mut started = false;
            if e.body.prepare(map, WALKER_BOX) {
                let support = e.body.floor(map, WALKER_BOX);
                started = support != 0 && e.body.vy >= 0;
                let distance = e.body.vx;
                e.body.horizontal(
                    map,
                    WALKER_BOX,
                    distance,
                    support,
                    crate::body::HorizontalMove::Actor,
                );
            }
            if e.body.gravity(map, WALKER_BOX, started) && w.mode == 1 {
                let left = if e.facing > 0 {
                    e.body.x
                } else {
                    e.body.x - 12 * S
                };
                let bottom = e.body.y + 16 * S;
                if !(map.terrain_overlaps([left, bottom, left + 12 * S, bottom + 28 * S])
                    || map.border_overlaps([left, bottom, left + 12 * S, bottom + 28 * S]))
                {
                    e.facing = -e.facing;
                }
            }
        }
    }
    pub fn advance(
        &mut self,
        input: u8,
        world: &World,
        stats: &mut crate::Stats,
    ) -> Result<(), Error> {
        if input & !7 != 0 {
            return Err(unsupported(
                "Stride slice supports LEFT/RIGHT/JUMP only; actions are not implemented",
            ));
        }
        if self.goal_reached != 0 {
            return Ok(());
        }
        self.frame = self.frame.checked_add(1).ok_or_else(|| {
            unsupported("saved frame increment exceeds the admitted Stride state range")
        })?;
        if self.player.life_phase == 7 {
            let p = &mut self.player;
            p.life_ticks = (p.life_ticks - 1).max(0);
            let age = (180 - p.life_ticks).min(60);
            let blend = age * (120 - age);
            p.body.x = p.goal_from_x + (p.goal_x - p.goal_from_x) * blend / 3600;
            p.body.y = p.goal_from_y + (p.goal_y - p.goal_from_y) * blend / 3600;
            p.attach();
            self.camera = Position {
                x: p.body.x,
                y: p.body.y - 28 * S,
            };
            if p.life_ticks == 0 {
                self.goal_reached = 1;
                p.life_phase = 8;
            }
            return Ok(());
        }
        if self.player.life_phase != 0 {
            return Err(unsupported("lifetime phase"));
        }
        self.play_ticks = self.play_ticks.saturating_add(1);
        self.total_play_ticks = self.total_play_ticks.saturating_add(1);
        self.attempt_ticks = self.attempt_ticks.saturating_add(1);
        let pressed = input & !(self.player.previous_input as u8);
        let released = self.player.previous_input as u8 & !input;
        self.player.previous_input = input as i64;
        self.player.pressed_input = pressed as i64;
        let map = crate::body::Probe::new(&world.maps[0]);
        self.entities_step(&map, stats);
        self.player
            .advance(&map, input, pressed, released, self.frame, &mut self.sound);
        for e in &mut self.entities {
            let Kind::Walker(w) = &mut e.kind else {
                continue;
            };
            if e.status != 1 {
                continue;
            }
            stats.contacts += 1;
            let touching = overlap(self.player.body, self.player.bounds(), e.body, WALKER_BOX);
            if touching {
                if e.body.y > self.player.body.y - 8 * S && w.contact == 0 {
                    self.player.stomp(e.body.vy, input, &mut self.sound);
                    e.status = 3;
                } else if e.body.y < self.player.body.y - 8 * S {
                    return Err(unsupported(
                        "walker damage/separation/rescue is not implemented",
                    ));
                }
                w.contact = 1;
            } else {
                w.contact = 0;
            }
        }
        for e in &self.entities {
            if !matches!(e.kind, Kind::Goal) {
                continue;
            }
            stats.contacts += 1;
            if overlap(
                self.player.body,
                [-12 * S, -56 * S, 12 * S, 0],
                e.body,
                [-8 * S, -8 * S, 8 * S, 8 * S],
            ) {
                let p = &mut self.player;
                p.life_phase = 7;
                p.life_ticks = 180;
                p.goal_from_x = p.body.x;
                p.goal_from_y = p.body.y;
                p.goal_x = e.body.x;
                p.goal_y = e.body.y + 32 * S;
                p.body.vx = 0;
                p.body.vy = 0;
                p.movement = 5;
                self.sound.player(p.body);
                break;
            }
        }
        if self.player.life_phase == 7 {
            let centre = screen_centre(self.camera, map.width_pixels * S, map.height_pixels * S);
            for e in &mut self.entities {
                if matches!(e.kind, Kind::Walker(_))
                    && e.status == 1
                    && e.body.x + 10 * S > centre.x - 416 * S
                    && e.body.x - 10 * S < centre.x + 416 * S
                    && e.body.y + 16 * S > centre.y - 224 * S
                    && e.body.y - 18 * S < centre.y + 224 * S
                {
                    e.status = 3;
                    self.coins = self.coins.saturating_add(1);
                }
            }
        }
        if self.player.life_phase == 0 {
            if self.player.body.y > map.height_pixels * S + 66 * S {
                return Err(unsupported("pit death/lifetime is not implemented"));
            }
            self.player.attach();
        }
        self.camera = Position {
            x: self.player.body.x,
            y: self.player.body.y - 28 * S,
        };
        if self.player.life_phase == 0 {
            self.player.finish(&map, input);
        }
        stats.terrain_queries += map.terrain_queries.get();
        Ok(())
    }
    pub fn wire(&self, world: &World, schema: &Schema) -> WireSnapshot {
        let level = schema
            .level()
            .iter()
            .map(|Field(n, d)| self.level_value(n, world).unwrap_or(*d))
            .collect();
        let player = schema
            .player()
            .iter()
            .map(|Field(n, d)| self.player_value(n).unwrap_or(*d))
            .collect();
        let entities = self
            .entities
            .iter()
            .map(|e| {
                let p = &world.maps[0].placements[e.source];
                let values = schema
                    .entity_fields(&p.code)
                    .iter()
                    .map(|Field(n, d)| self.entity_value(e, n, world).unwrap_or(*d))
                    .collect();
                WireEntity {
                    code: p.code.clone(),
                    id: p.id.clone(),
                    values,
                }
            })
            .collect();
        WireSnapshot {
            identity: world.identity,
            level,
            player,
            entities,
        }
    }
    fn level_value(&self, n: &str, world: &World) -> Option<i64> {
        Some(match n {
            "frame" => self.frame,
            "camera_x" => self.camera.x,
            "camera_y" => self.camera.y,
            "rng" => self.rng.saved(),
            "goal_reached" => self.goal_reached,
            "life_ready" => 1,
            "run_spawn_x" => world.spawn.x,
            "run_spawn_y" => world.spawn.y,
            "run_spawn_facing" => world.spawn_facing,
            "play_ticks" => self.play_ticks,
            "total_play_ticks" => self.total_play_ticks,
            "coins" => self.coins,
            "sound_serial" => self.sound.serial,
            "sound_kind" => self.sound.kind,
            "sound_x" => self.sound.x,
            "sound_y" => self.sound.y,
            _ => return None,
        })
    }
    fn player_value(&self, n: &str) -> Option<i64> {
        if n == "attempt_ticks" {
            Some(self.attempt_ticks)
        } else {
            self.player.field(n)
        }
    }
    fn entity_value(&self, e: &Entity, n: &str, world: &World) -> Option<i64> {
        let p = &world.maps[0].placements[e.source];
        Some(match n {
            "source_index" => e.source as i64,
            "token" => e.source as i64 + 1,
            "map_index" => 1,
            "family_index" => 0,
            "x" => e.body.x,
            "y" => e.body.y,
            "vx" => e.body.vx,
            "vy" => e.body.vy,
            "facing" => e.facing,
            "status" => e.status,
            "offscreen" => e.offscreen,
            "spawn_mode" | "can_despawn" | "can_respawn" => {
                i64::from(matches!(e.kind, Kind::Walker(_)))
            }
            "layer" => {
                if matches!(e.kind, Kind::Walker(_)) {
                    8
                } else {
                    7
                }
            }
            "spawn_x" | "home_x" => p.position.x,
            "spawn_y" | "home_y" => p.position.y,
            "phase" => {
                if let Kind::Walker(w) = &e.kind {
                    w.phase
                } else {
                    return None;
                }
            }
            "timer" => {
                if let Kind::Walker(w) = &e.kind {
                    w.timer
                } else {
                    return None;
                }
            }
            "cycles" => {
                if let Kind::Walker(w) = &e.kind {
                    w.cycles
                } else {
                    return None;
                }
            }
            "mode" => {
                if let Kind::Walker(w) = &e.kind {
                    w.mode
                } else {
                    return None;
                }
            }
            "started" => {
                if let Kind::Walker(w) = &e.kind {
                    w.started
                } else {
                    return None;
                }
            }
            "contact" => {
                if let Kind::Walker(w) = &e.kind {
                    w.contact
                } else {
                    return None;
                }
            }
            _ => return None,
        })
    }
    pub fn validate(&self) -> Result<(), Error> {
        let p = &self.player;
        let position_limit = i64::MAX / 16384;
        if self.frame < 0
            || self.play_ticks < 0
            || self.total_play_ticks < self.play_ticks
            || self.attempt_ticks < 0
            || self.coins < 0
            || !(0..=1).contains(&self.goal_reached)
            || ![-1, 1].contains(&p.facing)
            || !(0..=1).contains(&p.on_floor)
            || !(0..=6).contains(&p.movement)
            || !(0..=7).contains(&p.previous_input)
            || !(0..=7).contains(&p.pressed_input)
            || ![0, 9, 10].contains(&p.action)
            || p.action_tick < 0
            || p.action_tick
                >= if p.action == 9 {
                    10
                } else if p.action == 10 {
                    4
                } else {
                    36
                }
            || !(0..=6).contains(&p.jump_buffer)
            || !(0..=72).contains(&p.flutter_remaining)
            || !(0..=17).contains(&p.flutter_cooldown)
            || !(0..=1).contains(&p.flutter_ready)
            || !(0..=1).contains(&p.boosted_flutter)
            || !(0..=24).contains(&p.gravity_tick)
            || !(0..=2).contains(&p.bounce)
            || !(0..=1).contains(&p.jump_carry)
            || ![-1, 0, 1].contains(&p.turn)
            || !(0..=30).contains(&p.turn_ticks)
            || !(0..=6).contains(&p.pound_delay)
            || !(0..=1).contains(&p.push)
            || ![0, 7, 8].contains(&p.life_phase)
            || !(0..=180).contains(&p.life_ticks)
            || (p.life_phase == 0 && p.life_ticks != 0)
            || (p.life_phase == 8) != (self.goal_reached != 0)
            || !(-400 * 60..=400 * 60).contains(&p.body.vx)
            || p.body.vy < -2000 * 60
            || p.body.vy > 704 * 60
            || self.sound.serial < 0
            || !(0..=4).contains(&self.sound.kind)
        {
            return Err(unsupported("state outside implemented Stride semantics"));
        }
        for v in [
            p.body.x,
            p.body.y,
            self.camera.x,
            self.camera.y,
            p.recovery_x,
            p.recovery_y,
            p.goal_x,
            p.goal_y,
            p.goal_from_x,
            p.goal_from_y,
            self.sound.x,
            self.sound.y,
        ] {
            if !(-position_limit..=position_limit).contains(&v) {
                return Err(unsupported("coordinate headroom"));
            }
        }
        for e in &self.entities {
            if !(0..=3).contains(&e.status)
                || ![-1, 1].contains(&e.facing)
                || !(0..=1).contains(&e.offscreen)
                || !(-position_limit..=position_limit).contains(&e.body.x)
                || !(-position_limit..=position_limit).contains(&e.body.y)
            {
                return Err(unsupported("entity lifecycle validation"));
            }
            if let Kind::Walker(w) = &e.kind {
                if !(0..=360).contains(&w.phase)
                    || !(0..=210).contains(&w.timer)
                    || !(-1..=180).contains(&w.cycles)
                    || !(0..=1).contains(&w.mode)
                    || !(0..=1).contains(&w.started)
                    || !(0..=1).contains(&w.contact)
                    || !(-512 * 60..=512 * 60).contains(&e.body.vx)
                    || e.body.vy < -944 * 60
                    || e.body.vy > 704 * 60
                {
                    return Err(unsupported("walker validation"));
                }
            }
        }
        Ok(())
    }
}
macro_rules! fields {($($name:literal=>$($path:ident).+),*$(,)?)=>{
impl Player{
    pub fn field(&self,n:&str)->Option<i64>{Some(match n{$($name=>self.$($path).+,)*_=>return None})}
    pub fn set_field(&mut self,n:&str,v:i64)->bool{match n{$($name=>{self.$($path).+ = v;true},)*_=>false}}
}};}
fields! {
"x"=>body.x,"y"=>body.y,"vx"=>body.vx,"vy"=>body.vy,"facing"=>facing,"movement"=>movement,"on_floor"=>on_floor,"previous_input"=>previous_input,"pressed_input"=>pressed_input,
"jump_buffer"=>jump_buffer,"flutter_remaining"=>flutter_remaining,"flutter_cooldown"=>flutter_cooldown,"flutter_ready"=>flutter_ready,"boosted_flutter"=>boosted_flutter,
"move_action"=>action,"move_action_tick"=>action_tick,"move_turn"=>turn,"move_turn_ticks"=>turn_ticks,"move_push"=>push,"move_pound_delay"=>pound_delay,"move_gravity_tick"=>gravity_tick,"move_bounce"=>bounce,"move_brake_vx"=>brake_vx,"move_jump_carry"=>jump_carry,
"life_phase"=>life_phase,"life_ticks"=>life_ticks,"recovery_x"=>recovery_x,"recovery_y"=>recovery_y,"goal_from_x"=>goal_from_x,"goal_from_y"=>goal_from_y,"goal_x"=>goal_x,"goal_y"=>goal_y
}
