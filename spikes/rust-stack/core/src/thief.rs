//! sneak_thief.gd (e10): a patrolling thief. It chases a near player, snatches the
//! companion on a side touch and runs off with the bubble; when a bubble appears it
//! races to grab it. Stomps and strikes wear it down. The body lives in `Actor`
//! (ActorKind::Thief).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, HorizontalMove, Probe},
    eating::{After, HitKind, Hold},
    entity::Kind,
    items::PickupKind,
    state::Run,
    Error, Placement, SCALE as S,
};
// Poses (the animation that drives the source logic).
pub(crate) const WALK: i64 = 0;
pub(crate) const IDLE: i64 = 1;
pub(crate) const PREPARE: i64 = 2;
pub(crate) const HIGH_PREPARE: i64 = 3;
pub(crate) const JUMP: i64 = 4;
pub(crate) const JUMP_MOVE: i64 = 5;
pub(crate) const FALL: i64 = 6;
pub(crate) const FALL_MOVE: i64 = 7;
pub(crate) const SIT: i64 = 8;
pub(crate) const GET_UP: i64 = 9;
pub(crate) const SPRINT: i64 = 10;
const NAMES: [&str; 11] = [
    "Walk",
    "Idle",
    "PrepareJump",
    "PrepareHighJump",
    "Jump",
    "JumpAndMove",
    "Fall",
    "FallAndMove",
    "Sit",
    "GetUp",
    "Sprint",
];
// Plans.
pub(crate) const PATROL: i64 = 0;
pub(crate) const CHASE: i64 = 1;
pub(crate) const EVADE: i64 = 2;
pub(crate) const AFTER: i64 = 3;
pub(crate) const IGNORE: i64 = 4;
pub(crate) const SLOW: i64 = 48 * 60;
pub(crate) const FAST: i64 = 368 * 60;
const ACCELERATION: i64 = 512;
const DECELERATION: i64 = 64;
const IDLE_FRAME: i64 = 20;
pub(crate) const BOX: [i64; 4] = [-14 * S, -26 * S, 14 * S, 16 * S];
/// life.gd BUBBLE_BOX
const BUBBLE_BOX: [i64; 4] = [-30 * S, -60 * S, 30 * S, 0];
/// life.gd BUBBLE companion mode.
const BUBBLE: i64 = 2;

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}
/// sneak_thief.gd POSE_TICKS
fn pose_ticks(pose: i64) -> i64 {
    match pose {
        PREPARE | HIGH_PREPARE => 8,
        SIT | GET_UP => 12,
        _ => 0,
    }
}

impl Actor {
    /// sneak_thief.gd prepare (Options.prepare with one form) + create.
    pub fn thief(p: &Placement) -> Result<Self, Error> {
        if p.variant != 0 || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e10 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        Ok(Actor::new(ActorKind::Thief, 0, p.mirror, p.position))
    }
    pub fn thief_valid(&self) -> bool {
        self.variant == 0
            && (WALK..=SPRINT).contains(&self.pose)
            && (0..=12).contains(&self.timer)
            && (PATROL..=IGNORE).contains(&self.plan)
            && [SLOW, FAST].contains(&self.max_speed)
            && (0..=6).contains(&self.idle_frames)
            && self.idle_tick >= 0
            && self.jump_health <= 3
            && self.hit_health <= 6
            && [
                self.carrying,
                self.get_up,
                self.grounded,
                self.saw_bubble,
                self.contact,
            ]
            .iter()
            .all(|v| [0, 1].contains(v))
    }
    /// sneak_thief.gd _pose
    pub(crate) fn thief_pose(&mut self, pose: i64) {
        self.pose = pose;
        self.timer = pose_ticks(pose);
        self.idle_tick = 0;
    }
    /// sneak_thief.gd view_state animation.
    pub fn thief_animation(&self) -> &'static str {
        NAMES[self.pose.clamp(WALK, SPRINT) as usize]
    }
    /// sneak_thief.gd _bubble_plans
    fn thief_bubble_plans(&mut self, body: &mut Body, out: bool) {
        if out && self.saw_bubble == 0 && [PATROL, CHASE].contains(&self.plan) {
            self.plan = AFTER;
            self.max_speed = FAST;
        }
        if !out && self.saw_bubble != 0 {
            if self.plan == AFTER {
                self.plan = CHASE;
            } else if self.plan == IGNORE {
                self.plan = PATROL;
            } else if self.plan == EVADE {
                self.plan = PATROL;
                self.max_speed = SLOW;
                body.vx = 0;
                self.thief_pose(SIT);
            }
        }
        self.saw_bubble = i64::from(out);
    }
    /// sneak_thief.gd _grab, for the thief itself (Run::thief_grab tells the others).
    fn thief_grab_self(&mut self, body: &mut Body) {
        self.carrying = 1;
        self.plan = EVADE;
        body.vx = 0;
        body.vy = 0;
    }
    /// sneak_thief.gd _decide: (control, grabbed the bubble).
    fn thief_decide(
        &mut self,
        body: &mut Body,
        facing: &mut i64,
        step: &mut ActorStep,
    ) -> (i64, bool) {
        // sneak_thief.gd _face
        let face = |facing: &mut i64, x: i64, target_x: i64, away: bool| {
            if target_x == x {
                return;
            }
            let toward = if target_x > x { 1 } else { -1 };
            *facing = if away { -toward } else { toward };
        };
        let player_x = step.player.body.x;
        let recovery_x = step.player.recovery_x;
        let recovery_y = step.player.recovery_y;
        match self.plan {
            CHASE => face(facing, body.x, player_x, false),
            EVADE => face(facing, body.x, player_x, true),
            AFTER => face(facing, body.x, recovery_x, false),
            _ => {}
        }
        if self.timer > 0 {
            self.timer -= 1;
            if self.timer == 0 {
                match self.pose {
                    PREPARE => {
                        self.thief_pose(JUMP_MOVE);
                        body.vy = -576 * 60;
                        self.grounded = 0;
                    }
                    HIGH_PREPARE => {
                        self.thief_pose(JUMP_MOVE);
                        body.vy = -768 * 60;
                        body.vx /= 4;
                        self.grounded = 0;
                    }
                    SIT => self.get_up = 1,
                    GET_UP => {
                        self.thief_pose(if self.plan == PATROL { IDLE } else { SPRINT });
                        if self.pose == IDLE {
                            self.idle_frames = 0;
                        }
                    }
                    _ => {}
                }
            }
        }
        if self.get_up != 0 && self.grounded != 0 {
            self.get_up = 0;
            body.vx = 0;
            self.thief_pose(GET_UP);
        }
        let map = step.map;
        // enemy_motion.gd overlaps: World.overlaps_box, terrain and borders only.
        let wall_ahead = |body: &Body, facing: i64| {
            let q = [
                body.x + BOX[0] + facing * S,
                body.y + BOX[1] - S,
                body.x + BOX[2] + facing * S,
                body.y + BOX[3] - S,
            ];
            map.border_overlaps(q) || map.terrain_overlaps(q)
        };
        let hurried = [CHASE, EVADE, AFTER].contains(&self.plan);
        if self.pose == WALK {
            if (body.x - self.home_x).abs() > 64 * S {
                self.idle_frames = step.rng.ticks(3, 6);
                body.vx = 0;
                self.thief_pose(IDLE);
            } else if self.grounded != 0 {
                // enemy_motion.gd edge
                let left = if *facing > 0 { body.x } else { body.x - 12 * S };
                let bottom = body.y + BOX[3];
                if !map.support_in_box([left, bottom, left + 12 * S, bottom + 28 * S]) {
                    *facing = -*facing;
                }
            }
        } else if self.pose == IDLE {
            self.idle_tick += 1;
            if self.idle_tick % IDLE_FRAME == 0 {
                if self.idle_frames > 0 {
                    self.idle_frames -= 1;
                }
                if self.idle_frames <= 0 {
                    let frame = (self.idle_tick / IDLE_FRAME) % 2;
                    if *facing < 0 && frame == 1 {
                        *facing = 1;
                    } else if *facing > 0 && frame == 0 {
                        *facing = -1;
                    }
                    self.home_x = body.x;
                    self.thief_pose(WALK);
                }
            }
        }
        if [PATROL, IGNORE].contains(&self.plan) && wall_ahead(body, *facing) {
            *facing = -*facing;
        }
        if hurried
            && self.grounded != 0
            && ![PREPARE, HIGH_PREPARE, SIT, GET_UP].contains(&self.pose)
            && wall_ahead(body, *facing)
        {
            self.thief_pose(PREPARE);
        }
        if self.plan == PATROL
            && (body.x - player_x).abs() < 160 * S
            && ![SIT, GET_UP].contains(&self.pose)
            && step.player.captured_by == 0
        {
            self.plan = CHASE;
            body.vy = -320 * 60;
            self.grounded = 0;
            self.max_speed = FAST;
            self.thief_pose(JUMP);
        }
        let mut grabbed = false;
        if self.plan == AFTER {
            if self.grounded != 0
                && self.pose != HIGH_PREPARE
                && (body.x - recovery_x).abs() < 96 * S
            {
                self.thief_pose(HIGH_PREPARE);
            }
            if [WALK, IDLE].contains(&self.pose) {
                self.thief_pose(SIT);
            }
            let bubble = [
                recovery_x + BUBBLE_BOX[0],
                recovery_y + BUBBLE_BOX[1],
                recovery_x + BUBBLE_BOX[2],
                recovery_y + BUBBLE_BOX[3],
            ];
            if self.carrying == 0
                && ![SIT, GET_UP].contains(&self.pose)
                && strict(world_box(*body, BOX), bubble)
            {
                self.thief_grab_self(body);
                grabbed = true;
            }
        }
        let control = if [WALK, SPRINT, JUMP_MOVE].contains(&self.pose) {
            *facing
        } else {
            0
        };
        (control, grabbed)
    }
    /// sneak_thief.gd _move
    fn thief_move(&mut self, body: &mut Body, map: &Probe, control: i64) {
        if control != 0 {
            body.vx = (body.vx + control * ACCELERATION).clamp(-self.max_speed, self.max_speed);
        } else if body.vx > 0 {
            body.vx = (body.vx - DECELERATION).max(0);
        } else if body.vx < 0 {
            body.vx = (body.vx + DECELERATION).min(0);
        }
        let distance = body.vx;
        let mut started = false;
        if distance != 0 {
            // enemy_motion.gd move (horizontal)
            let actual = if body.prepare(map, BOX) {
                let support = body.floor(map, BOX);
                started = support != 0 && body.vy >= 0;
                body.horizontal(map, BOX, distance, support, HorizontalMove::Actor)
            } else {
                0
            };
            if actual != distance {
                body.vx = 0;
            }
        }
        let was_grounded = self.grounded == 1;
        let landed = body.gravity(map, BOX, started);
        if !landed && body.vy > 0 {
            if self.pose == JUMP {
                self.thief_pose(FALL);
            } else if self.pose == JUMP_MOVE {
                self.thief_pose(FALL_MOVE);
            }
        }
        if landed && !was_grounded {
            if self.pose == FALL {
                self.thief_pose(SIT);
            } else if self.pose == FALL_MOVE {
                self.thief_pose(SPRINT);
            }
        }
        self.grounded = i64::from(landed || body.floor(map, BOX) != 0);
    }
}

impl Run {
    fn thief_actor(&mut self, index: usize) -> &mut Actor {
        match &mut self.entities[index].kind {
            Kind::Walker(w) => w,
            _ => unreachable!("thief index"),
        }
    }
    /// sneak_thief.gd step.
    pub(crate) fn thief_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let token = self.entities[index].origin.token();
        let Run {
            entities,
            player,
            rng,
            frame,
            camera,
            ..
        } = self;
        let e = &mut entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        let fresh = w.started == 0;
        if fresh {
            // enemy_body.gd process: the first step's initialisation.
            w.started = 1;
            w.impact_cursor = player.impact;
            if w.mirror == 2 {
                e.facing = if player.body.x > e.body.x { 1 } else { -1 };
            }
        }
        let mut step = ActorStep {
            map,
            frame: *frame,
            camera: *camera,
            player,
            rng,
        };
        let action = w.process(
            token,
            &mut e.body,
            &mut e.facing,
            &mut e.status,
            &mut e.can_respawn,
            &step,
        );
        if [Hold::Held, Hold::Gone].contains(&action) {
            return Ok(());
        }
        if fresh {
            w.home_x = e.body.x;
        }
        if w.frozen != 0 {
            return Err(Error::Unsupported {
                requirements: vec!["frozen sneak thief (ice shots are not ported)".into()],
            });
        }
        if let Some(after) = w.spit_step(
            &mut e.body,
            &mut e.facing,
            &mut e.status,
            &mut e.can_respawn,
            &mut step,
        ) {
            if let After::HitOthers(b) = after {
                self.hit_others(index, b, HitKind::Spit, true)?;
            }
            return Ok(());
        }
        if map.lava_overlaps(world_box(e.body, BOX)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(());
        }
        let out = step.player.life.companion_mode == BUBBLE;
        w.thief_bubble_plans(&mut e.body, out);
        let (control, grabbed) = w.thief_decide(&mut e.body, &mut e.facing, &mut step);
        w.thief_move(&mut e.body, map, control);
        if w.carrying != 0 {
            if step.player.life.companion_mode == BUBBLE {
                // The stolen bubble rides on the thief.
                step.player.recovery_x = e.body.x;
                step.player.recovery_y = e.body.y + 30 * S;
            } else {
                w.carrying = 0;
            }
        }
        if grabbed {
            self.thief_grab_others(index);
        }
        Ok(())
    }
    /// sneak_thief.gd _grab: the other thieves give up the chase.
    fn thief_grab_others(&mut self, index: usize) {
        let token = self.entities[index].origin.token();
        for o in &mut self.entities {
            if let Kind::Walker(ow) = &mut o.kind {
                if ow.kind == ActorKind::Thief
                    && o.status == 1
                    && o.origin.token() != token
                    && ow.plan != EVADE
                {
                    ow.plan = IGNORE;
                    ow.max_speed = SLOW;
                    ow.thief_pose(IDLE);
                }
            }
        }
    }
    /// sneak_thief.gd contact.
    pub(crate) fn thief_contact(
        &mut self,
        index: usize,
        input: u8,
        map: &Probe,
    ) -> Result<(), Error> {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return Ok(());
        };
        // enemy_body.gd player_overlap
        let touching = !(w.hidden != 0 || w.held != 0 || w.spat != 0 || e.status != 1 || captured)
            && strict(world_box(e.body, BOX), world_box(p, pb));
        if touching && w.contact == 0 && p.vy > e.body.vy && e.body.y > p.y - 8 * S {
            // enemy_body.gd pounding: POUND_FALL or POUND_LAND.
            if [2, 3].contains(&self.player.action) {
                self.thief_defeat(index)?;
            } else {
                let vy = e.body.vy;
                self.player
                    .enemy_bounce(vy, input, self.message.modal_token != 0, &mut self.sound);
                let e = &mut self.entities[index];
                let Kind::Walker(w) = &mut e.kind else {
                    unreachable!()
                };
                w.jump_health -= 1;
                if w.jump_health > 0 {
                    w.thief_pose(SIT);
                    e.body.vx = 0;
                    self.player.body.vx = if p.x < e.body.x { -128 } else { 128 } * 60;
                } else {
                    self.thief_defeat(index)?;
                }
            }
        } else if touching
            && e.body.y <= p.y - 8 * S
            && self.player.life.separated == 0
            && self.player.life.invulnerable == 0
            && self.player.life.companion_mode == 0
        {
            // A touch from the side takes the companion straight into a bubble the thief
            // carries (damage.gd separate: an instant bubble).
            self.player.separate_in_world(0, true, map, self.camera);
            if self.player.life.companion_mode == BUBBLE {
                let e = &mut self.entities[index];
                if let Kind::Walker(w) = &mut e.kind {
                    w.thief_grab_self(&mut e.body);
                }
                self.thief_grab_others(index);
                self.thief_actor(index).saw_bubble = 1;
            }
        }
        self.thief_actor(index).contact = i64::from(touching);
        Ok(())
    }
    /// sneak_thief.gd _defeat: three coins, then removed.
    fn thief_defeat(&mut self, index: usize) -> Result<(), Error> {
        for _ in 0..3 {
            self.thief_coin(index, 30)?;
        }
        let e = &mut self.entities[index];
        if let Kind::Walker(w) = &mut e.kind {
            w.remove(&mut e.status, &mut e.can_respawn);
        }
        Ok(())
    }
    /// sneak_thief.gd _coin: registry.gd spawn_dynamic of a moving o1.
    fn thief_coin(&mut self, index: usize, delay: i64) -> Result<(), Error> {
        let (x, y) = (self.entities[index].body.x, self.entities[index].body.y);
        let vx = self.rng.ticks(-256 * 60, 256 * 60);
        let vy = -self.rng.ticks(256 * 60, 384 * 60);
        self.spawn_loot_coin(PickupKind::Coin, x, y, vx, vy, delay)
    }
    /// sneak_thief.gd _struck (hit with any kind but POUND and CLEAR, and
    /// projectile_contact): it sits, loses a hit and drops loot, or is removed.
    pub(crate) fn thief_struck(&mut self, index: usize, from_x: i64) -> Result<(), Error> {
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return Ok(());
        };
        w.thief_pose(SIT);
        w.hit_health -= 1;
        e.body.vx = if e.body.x > from_x { 256 } else { -256 } * 60;
        let (x, y, health) = (e.body.x, e.body.y, w.hit_health);
        if health >= 3 {
            self.thief_coin(index, 0)?;
        } else if health > 0 {
            let vy = -self.rng.ticks(256 * 60, 512 * 60);
            let facing = if self.rng.ticks(0, 1) == 1 { 1 } else { -1 };
            let max_speed = self.rng.ticks(64 * 60, 128 * 60);
            self.spawn_star(x, y, vy, facing, max_speed)?;
        } else {
            w.remove(&mut e.status, &mut e.can_respawn);
        }
        Ok(())
    }
}
