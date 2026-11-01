//! shell_walker.gd: e6/e8 walkers, their winged forms, empty shells, and the bare
//! enemy_runner ejected from a shell. The bodies live in `Actor` (ActorKind::Shell and
//! ActorKind::Runner) so enemy bookkeeping (family index, capture) stays shared.
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, HorizontalMove, Probe},
    eating::{After, HitKind, Hold},
    entity::{Entity, Kind},
    state::Run,
    Error, Placement, SCALE as S,
};
pub(crate) const WALK: i64 = 0;
pub(crate) const TURN: i64 = 1;
pub(crate) const HOP: i64 = 2;
pub(crate) const HOP_LAND: i64 = 3;
pub(crate) const FLY: i64 = 4;
pub(crate) const IDLE: i64 = 5;
pub(crate) const SPIN: i64 = 6;
pub(crate) const BARE: i64 = 7;
pub(crate) const SLIDE: i64 = 8;
pub(crate) const BARE_TURN: i64 = 9;
pub(crate) const ENTER: i64 = 10;
pub(crate) const SHAKE: i64 = 11;
pub(crate) const RETURN_AIR: i64 = 12;
pub(crate) const RETURN_LAND: i64 = 13;
pub(crate) const UP_SPIT: i64 = 14;

/// shell_walker.gd bounds, by mode.
pub(crate) fn bounds(mode: i64) -> [i64; 4] {
    match mode {
        IDLE | SPIN | UP_SPIT | SHAKE => [-14 * S, -12 * S, 14 * S, 16 * S],
        SLIDE | ENTER => [-14 * S, -12 * S, 14 * S, 18 * S],
        RETURN_AIR => [-14 * S, -14 * S, 14 * S, 16 * S],
        _ => [-14 * S, -22 * S, 14 * S, 16 * S],
    }
}
/// Bare runner modes: no shell to spin or lose.
pub(crate) fn bare(mode: i64) -> bool {
    [BARE, SLIDE, BARE_TURN, ENTER].contains(&mode)
}
fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

impl Actor {
    /// shell_walker.gd prepare + create for a placed e6 or e8.
    pub fn shell(p: &Placement) -> Result<Self, Error> {
        if !(0..=4).contains(&p.variant) || !(0..=2).contains(&p.mirror) {
            return Err(Error::Unsupported {
                requirements: vec![format!("{} form F={} M={}", p.code, p.variant, p.mirror)],
            });
        }
        let mut a = Actor::new(ActorKind::Shell, p.variant, p.mirror, p.position);
        a.colour = i64::from(p.code == "e8");
        a.mode = [WALK, HOP, FLY, IDLE, SPIN][p.variant as usize];
        a.inside = i64::from(p.variant <= 2);
        Ok(a)
    }
    /// bare_runner.gd prepare + create: a placed shell-less walker (e7 green, e9 red).
    pub fn bare_runner(p: &Placement) -> Result<Self, Error> {
        if p.variant != 0 || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "{} form F={} M={} R={}",
                    p.code, p.variant, p.mirror, p.rotation
                )],
            });
        }
        let mut a = Actor::new(ActorKind::Runner, 0, p.mirror, p.position);
        a.colour = i64::from(p.code == "e9");
        a.mode = BARE;
        a.inside = 0;
        Ok(a)
    }
    pub fn shell_valid(&self) -> bool {
        (WALK..=UP_SPIT).contains(&self.mode)
            && (0..=120).contains(&self.timer)
            && [0, 1].contains(&self.colour)
            && [0, 1].contains(&self.inside)
            && [0, 1].contains(&self.grace)
            && (0..300).contains(&self.flight_phase)
            && [-1, 1].contains(&self.flight_direction)
            && [-1, 1].contains(&self.slide_direction)
            && self.origin_shell >= 0
            && self.runner_token >= 0
            && self.target_shell >= 0
    }
    /// shell_walker.gd spin
    pub(crate) fn spin(&mut self, body: &mut Body, facing: &mut i64, direction: i64) {
        self.mode = SPIN;
        self.timer = 0;
        *facing = direction;
        body.vx = direction * 432 * 60;
        self.spat = 0;
    }
    fn shell_turn(&mut self, body: &mut Body) {
        self.mode = if self.mode == BARE { BARE_TURN } else { TURN };
        self.timer = 26;
        body.vx = 0;
    }
    /// shell_walker.gd hit (no element reactions are admitted, so none apply).
    pub(crate) fn shell_hit(
        &mut self,
        body: &mut Body,
        facing: &mut i64,
        status: &mut i64,
        can_respawn: &mut i64,
        kind: HitKind,
        from_x: i64,
    ) {
        if kind == HitKind::Egg && !bare(self.mode) {
            if [HOP, FLY].contains(&self.mode) {
                self.mode = WALK;
            } else {
                self.spin(body, facing, if from_x < body.x { 1 } else { -1 });
            }
        } else if kind == HitKind::Spit && self.mode == SPIN {
        } else {
            self.remove(status, can_respawn);
        }
    }
    /// shell_walker.gd view_state animation.
    pub fn shell_animation(&self) -> String {
        let pose = match self.mode {
            IDLE | SPIN | UP_SPIT | SHAKE => "Shell",
            HOP | FLY => "Winged",
            HOP_LAND => "WingedLand",
            TURN | BARE_TURN => "Turn",
            RETURN_AIR | ENTER => "Jump",
            RETURN_LAND => "Land",
            _ => "Walk",
        };
        format!("{}{pose}", self.colour)
    }
}

/// enemy_motion.gd move with `horizontal` false: a vertical move from the floor support.
fn move_vertical(body: &mut Body, map: &Probe, b: [i64; 4], distance: i64) {
    if !body.prepare(map, b) {
        return;
    }
    let support = body.floor(map, b);
    body.vertical_support(map, b, distance, support);
}
/// enemy_motion.gd move (horizontal): (actual distance, started on a floor).
fn move_horizontal(body: &mut Body, map: &Probe, b: [i64; 4], distance: i64) -> (i64, bool) {
    if !body.prepare(map, b) {
        return (0, false);
    }
    let support = body.floor(map, b);
    let grounded = support != 0 && body.vy >= 0;
    (
        body.horizontal(map, b, distance, support, HorizontalMove::Actor),
        grounded,
    )
}

impl Run {
    fn shell_actor(&mut self, index: usize) -> &mut Actor {
        match &mut self.entities[index].kind {
            Kind::Walker(w) => w,
            _ => unreachable!("shell index"),
        }
    }
    /// shell_walker.gd step. A runner removed inside its own step (eaten through a
    /// CONSUME request, or lava) runs on_remove here; the other removal paths call
    /// shell_remove, and on_remove is idempotent within a step.
    pub(crate) fn shell_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let before = self.entities[index].status;
        let result = self.shell_step_inner(index, map);
        if before != 3 && self.entities[index].status == 3 {
            self.shell_on_remove(index);
        }
        result
    }
    fn shell_step_inner(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let runner_token = self.shell_actor(index).runner_token;
        if runner_token != 0 {
            let alive = self
                .find_token(runner_token)
                .is_some_and(|i| self.entities[i].status == 1);
            if !alive {
                self.entities[index].can_despawn = 1;
                self.shell_actor(index).runner_token = 0;
            }
        }
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
        let step = ActorStep {
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
        // element_reactions.gd frozen_step
        match w.frozen_step(&mut e.body, e.status, map, bounds(w.mode)) {
            crate::elements::Frozen::Free => {}
            crate::elements::Frozen::Done => return Ok(()),
            crate::elements::Frozen::Lava => return self.remove_enemy(index),
        }
        if fresh {
            w.flight_direction = e.facing;
        }
        if action == Hold::Released && !bare(w.mode) {
            if e.body.vx == 0 {
                w.mode = UP_SPIT;
            } else {
                let direction = e.body.vx.signum();
                w.spin(&mut e.body, &mut e.facing, direction);
                w.spat = 0;
            }
        }
        let mut step = ActorStep {
            map,
            frame: *frame,
            camera: *camera,
            player,
            rng,
        };
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
            let w = self.shell_actor(index);
            if w.spat == 0 && w.mode == UP_SPIT {
                w.mode = IDLE;
            }
            return Ok(());
        }
        let box_ = bounds(w.mode);
        if map.lava_overlaps(world_box(e.body, box_)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(());
        }
        if w.mode == ENTER {
            return self.shell_enter_step(index);
        }
        if w.mode == FLY {
            Self::shell_fly(w, &mut e.body, &mut e.facing, map);
            return Ok(());
        }
        let body = &mut e.body;
        let facing = &mut e.facing;
        let grounded = body.floor(map, box_) != 0;
        let wet = i64::from(map.water_overlaps(world_box(*body, box_)));
        match w.mode {
            TURN | BARE_TURN => {
                body.vx = 0;
                w.timer -= 1;
                if w.timer == 13 {
                    *facing = -*facing;
                }
                if w.timer == 0 {
                    w.mode = if w.mode == BARE_TURN { BARE } else { WALK };
                }
            }
            HOP_LAND => {
                body.vx = 0;
                w.timer -= 1;
                if w.timer == 0 {
                    w.mode = HOP;
                    body.vy = if w.colour != 0 { -448 } else { -280 } * 60;
                    // The hop moves sideways from its first step.
                    body.vx = *facing * 64 * 60 / ((wet + 1) * (wet + 1));
                }
            }
            SHAKE => {
                body.vx = 0;
                w.timer -= 1;
                if w.timer == 0 {
                    w.mode = RETURN_AIR;
                    body.vy = -256 * 60;
                }
            }
            RETURN_LAND => {
                body.vx = 0;
                w.timer -= 1;
                if w.timer == 0 {
                    w.mode = WALK;
                }
            }
            SLIDE => {
                body.vx = w.slide_direction * 432 * 60 * w.timer * w.timer / 3600;
                w.timer -= 1;
                if w.timer == 0 {
                    w.mode = BARE;
                }
            }
            IDLE | UP_SPIT | RETURN_AIR => body.vx = 0,
            _ => {
                let speed = match w.mode {
                    SPIN => 432,
                    HOP => 64,
                    _ => 48,
                };
                let mut divisor = wet + 1;
                if [WALK, HOP, SPIN].contains(&w.mode) {
                    divisor *= divisor;
                }
                body.vx = *facing * speed * 60 / divisor;
                if w.colour == 1 && [WALK, BARE].contains(&w.mode) && grounded {
                    // enemy_motion.gd edge
                    let left = if *facing > 0 { body.x } else { body.x - 12 * S };
                    let bottom = body.y + box_[3];
                    if !map.support_in_box([left, bottom, left + 12 * S, bottom + 28 * S]) {
                        w.shell_turn(body);
                    }
                }
            }
        }
        let distance = body.vx;
        let (actual, started) = move_horizontal(body, map, box_, distance);
        let mut struck = None;
        if actual != distance {
            if [SPIN, HOP].contains(&w.mode) {
                if w.mode == SPIN {
                    struck = Some(distance.signum());
                }
                *facing = -*facing;
            } else if [WALK, BARE].contains(&w.mode) {
                w.shell_turn(body);
            }
        }
        if struck.is_some() {
            // enemy_body.gd strike_wall with Hits.SHELL reaches SOLID 1 types with a
            // `hit`: hard, colour and thorn blocks react to EGG only and item blocks to
            // EGG only (o18), so a shell against them changes nothing.
        }
        let hopped = [HOP, HOP_LAND].contains(&w.mode);
        let falling = body.vy > 0;
        let landed = body.gravity_box(
            map,
            box_,
            started,
            if hopped { 512 } else { 2048 },
            if hopped { 176 } else { 704 } * 60,
        );
        if landed {
            match w.mode {
                HOP => {
                    w.mode = HOP_LAND;
                    // 0.25 s, plus two ticks after a fall: the landing is seen a tick late
                    // and the jump starts on the next tick. Placed on a floor: 0.25 s.
                    w.timer = if falling { 17 } else { 15 };
                }
                RETURN_AIR => {
                    w.mode = RETURN_LAND;
                    w.timer = 15;
                }
                BARE => {
                    self.shell_find(index);
                }
                _ => {}
            }
        }
        if self.shell_actor(index).mode == SPIN {
            self.hit_others(index, box_, HitKind::Shell, false)?;
        }
        Ok(())
    }
    /// shell_walker.gd _fly_step
    fn shell_fly(w: &mut Actor, body: &mut Body, facing: &mut i64, map: &Probe) {
        let tick = w.flight_phase;
        let time = if tick <= 150 { tick } else { 300 - tick };
        let numerator = if time < 75 {
            2 * time * time
        } else {
            22500 - 2 * (150 - time) * (150 - time)
        };
        let amplitude = if w.colour != 0 { 112 } else { 144 } * 60;
        let velocity = w.flight_direction * amplitude * (22500 - 2 * numerator) / 22500;
        body.vx = if w.colour != 0 { 0 } else { velocity };
        body.vy = if w.colour != 0 { velocity } else { 0 };
        if body.vx != 0 {
            *facing = body.vx.signum();
        }
        let b = bounds(w.mode);
        let vx = body.vx;
        move_horizontal(body, map, b, vx);
        let vy = body.vy;
        move_vertical(body, map, b, vy);
        w.flight_phase = (tick + 1) % 300;
    }
    /// shell_walker.gd _find_shell: a landed runner jumps for an empty idle shell 44 px
    /// ahead.
    fn shell_find(&mut self, index: usize) {
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return;
        };
        let mut ahead = world_box(e.body, bounds(w.mode));
        ahead[0] += e.facing * 44 * S;
        ahead[2] += e.facing * 44 * S;
        let found = self.entities.iter().enumerate().find_map(|(i, o)| {
            let Kind::Walker(ow) = &o.kind else {
                return None;
            };
            (i != index
                && ow.kind == ActorKind::Shell
                && o.status == 1
                && ow.held == 0
                && ow.mode == IDLE
                && ow.inside == 0
                && strict(ahead, world_box(o.body, bounds(ow.mode))))
            .then_some((o.origin.token(), o.body))
        });
        let Some((target, at)) = found else {
            return;
        };
        let e = &mut self.entities[index];
        let (x, y) = (e.body.x, e.body.y);
        e.body.vx = 0;
        e.body.vy = 0;
        let w = self.shell_actor(index);
        w.mode = ENTER;
        w.timer = 24;
        w.target_shell = target;
        w.enter_x = x;
        w.enter_y = y;
        w.target_x = at.x;
        w.target_y = at.y;
    }
    /// shell_walker.gd _enter_step: a 24-tick arc into the target shell.
    fn shell_enter_step(&mut self, index: usize) -> Result<(), Error> {
        let w = self.shell_actor(index);
        w.timer -= 1;
        let elapsed = 24 - w.timer;
        let (ex, ey, tx, ty, timer) = (w.enter_x, w.enter_y, w.target_x, w.target_y, w.timer);
        let target = w.target_shell;
        let e = &mut self.entities[index];
        e.body.x = ex + (tx - ex) * elapsed / 24;
        let apex = 2 * ey - ty - 32 * S;
        e.body.y = if elapsed <= 12 {
            ey + (apex - ey) * (144 - (12 - elapsed) * (12 - elapsed)) / 144
        } else {
            apex + (ty - apex) * (elapsed - 12) * (elapsed - 12) / 144
        };
        if timer != 0 {
            return Ok(());
        }
        let me = world_box(e.body, bounds(ENTER));
        let facing = e.facing;
        let shell = self.find_token(target).filter(|&i| {
            let o = &self.entities[i];
            matches!(&o.kind, Kind::Walker(ow)
                if o.status == 1 && ow.held == 0 && ow.mode == IDLE && ow.inside == 0
                    && strict(me, world_box(o.body, bounds(ow.mode))))
        });
        if let Some(shell) = shell {
            self.shell_remove(index);
            let o = &mut self.entities[shell];
            o.facing = facing;
            if let Kind::Walker(ow) = &mut o.kind {
                ow.inside = 1;
                ow.mode = SHAKE;
                ow.timer = 120;
            }
        } else {
            self.shell_actor(index).mode = BARE;
        }
        self.shell_actor(index).target_shell = 0;
        Ok(())
    }
    /// enemy_body.gd remove for a shell-family body, with shell_walker.gd on_remove: a
    /// runner's origin shell may despawn and never respawns.
    pub(crate) fn shell_remove(&mut self, index: usize) {
        if self.entities[index].status != 3 {
            self.plant_on_remove(index);
        }
        let e = &mut self.entities[index];
        let first = e.status != 3;
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        w.remove(&mut e.status, &mut e.can_respawn);
        if first {
            self.shell_on_remove(index);
        }
    }
    /// actor.gd on_remove: removing the e5 that holds the player separates the
    /// companion (Damage.separate without the world) and releases the player
    /// (enemy_plant.gd release).
    pub(crate) fn plant_on_remove(&mut self, index: usize) {
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        if w.kind != crate::actors::ActorKind::Plant
            || self.player.captured_by != e.family_index + 1
        {
            return;
        }
        if self.player.life.separated == 0 {
            self.player.separate(-e.facing * 400 * 60, true);
        }
        w.mode = 5;
        w.timer = 30;
        let p = &mut self.player;
        p.captured_by = 0;
        p.life.invulnerable = 121;
        p.life.hurt = 38;
        p.life.hurt_phase = 1;
        p.life.hurt_deceleration = 648;
        p.body.vx = e.facing * 400 * 60;
        p.body.vy = -384 * 60;
        p.on_floor = 0;
    }
    /// shell_walker.gd on_remove: a runner's origin shell may despawn and never
    /// respawns.
    fn shell_on_remove(&mut self, index: usize) {
        let Kind::Walker(w) = &self.entities[index].kind else {
            return;
        };
        let origin = w.origin_shell;
        if origin == 0 {
            return;
        }
        if let Some(i) = self.find_token(origin) {
            let o = &mut self.entities[i];
            o.can_despawn = 1;
            o.can_respawn = 0;
            if let Kind::Walker(ow) = &mut o.kind {
                ow.runner_token = 0;
            }
        }
    }
    /// shell_walker.gd eject: the walker leaves its shell as a sliding runner.
    fn shell_eject(&mut self, index: usize) -> Result<(), Error> {
        let player_x = self.player.body.x;
        let e = &mut self.entities[index];
        e.body.vx = 0;
        e.body.vy = -192 * 60;
        let (x, y, token) = (e.body.x, e.body.y, e.origin.token());
        let w = self.shell_actor(index);
        w.mode = IDLE;
        w.inside = 0;
        let colour = w.colour;
        let direction = if player_x < x { 1 } else { -1 };
        let Ok(serial) = self.next_serial() else {
            return Ok(());
        };
        let mut runner = Actor::new(ActorKind::Runner, 0, 0, crate::Position { x, y });
        runner.colour = colour;
        runner.origin_shell = token;
        runner.mode = SLIDE;
        runner.timer = 60;
        runner.slide_direction = direction;
        runner.grace = 1;
        runner.inside = 0;
        let family = self.entities.iter().filter(|e| e.is_enemy()).count() as i64;
        let mut row = Entity::dynamic(
            serial,
            Kind::Walker(runner),
            Body {
                x,
                y,
                ..Body::default()
            },
            -direction,
            8,
        );
        row.family_index = family;
        row.can_despawn = 1;
        self.dynamic_serial = serial + 1;
        let runner_token = row.origin.token();
        self.entities.push(row);
        self.entities[index].can_despawn = 0;
        self.shell_actor(index).runner_token = runner_token;
        Ok(())
    }
    /// shell_walker.gd contact.
    pub(crate) fn shell_contact(&mut self, index: usize, input: u8) -> Result<(), Error> {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return Ok(());
        };
        // enemy_body.gd player_overlap: open edges, nothing hidden, held or spat.
        let touching = !(w.hidden != 0 || w.held != 0 || w.spat != 0 || e.status != 1 || captured)
            && strict(world_box(e.body, bounds(w.mode)), world_box(p, pb));
        if !touching {
            w.contact = 0;
            w.grace = 0;
            return Ok(());
        }
        if w.grace != 0 {
            return Ok(());
        }
        let pounding = [2, 3].contains(&self.player.action);
        if e.body.y > p.y - 8 * S && w.contact == 0 {
            if pounding {
                self.shell_remove(index);
            } else {
                let vy = e.body.vy;
                self.player.stomp(vy, input, &mut self.sound);
                let e = &mut self.entities[index];
                let Kind::Walker(w) = &mut e.kind else {
                    unreachable!()
                };
                if [HOP, HOP_LAND, FLY].contains(&w.mode) {
                    w.mode = WALK;
                } else if (BARE..=ENTER).contains(&w.mode) {
                    self.shell_remove(index);
                } else if w.mode == SPIN {
                    w.mode = IDLE;
                    e.body.vx = 0;
                } else if w.inside != 0 && [WALK, TURN, IDLE, SHAKE].contains(&w.mode) {
                    self.shell_eject(index)?;
                } else {
                    let direction = if p.x < e.body.x { 1 } else { -1 };
                    w.spin(&mut e.body, &mut e.facing, direction);
                }
            }
        } else if e.body.y < p.y - 8 * S {
            if w.mode == IDLE {
                let direction = if p.x < e.body.x { 1 } else { -1 };
                w.spin(&mut e.body, &mut e.facing, direction);
                w.grace = 1;
            } else {
                let x = e.body.x;
                self.player.hurt(x, &mut self.sound);
            }
        }
        self.shell_actor(index).contact = 1;
        Ok(())
    }
}
