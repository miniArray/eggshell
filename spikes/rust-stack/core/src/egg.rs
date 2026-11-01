//! o7: inventory eggs and their thrown, skipping and falling forms (item_egg.gd).
use crate::{
    actors::ActorKind,
    body::{Body, HorizontalMove, Probe},
    entity::{Entity, Kind, Origin, TOKEN_BASE},
    items::{Pickup, PickupKind, Star},
    math::{angle_delta, angle_to, root, turn_cosine, turn_sine},
    state::Run,
    Error, SCALE as S,
};

pub(crate) const STATIONARY: i64 = 0;
pub(crate) const THROWN: i64 = 1;
pub(crate) const FALLING: i64 = 2;
pub(crate) const SKIP: i64 = 3;
const SPEED: i64 = 1024 * 60;
const UNIT: i64 = 1_000_000;

macro_rules! egg_fields {($($field:ident),*$(,)?)=>{impl Egg{pub fn field(&self,n:&str)->Option<i64>{Some(match n{$(stringify!($field)=>self.$field,)*_=>return None})}pub fn set_field(&mut self,n:&str,value:i64)->bool{match n{$(stringify!($field)=>{self.$field=value;true},)*_=>false}}}};}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Egg {
    pub variant: i64,
    pub colour: i64,
    pub mode: i64,
    pub floating: i64,
    pub pickup_delay: i64,
    pub despawn_ticks: i64,
    pub bounces: i64,
    pub fall_on_terrain: i64,
    pub camera: i64,
    pub last_target: i64,
    pub origin_token: i64,
    pub loot_created: i64,
    pub ignore_terrain: i64,
    pub skip_ticks: i64,
    pub skip_total: i64,
    pub skip_vx: i64,
    pub skip_ghost: i64,
}
egg_fields!(
    variant,
    colour,
    mode,
    floating,
    pickup_delay,
    despawn_ticks,
    bounces,
    fall_on_terrain,
    camera,
    last_target,
    origin_token,
    loot_created,
    ignore_terrain,
    skip_ticks,
    skip_total,
    skip_vx,
    skip_ghost
);

impl Egg {
    pub fn new(variant: i64) -> Self {
        Self {
            variant,
            colour: variant,
            mode: STATIONARY,
            floating: 0,
            pickup_delay: 0,
            despawn_ticks: 0,
            bounces: 4,
            fall_on_terrain: 0,
            camera: 0,
            last_target: 0,
            origin_token: 0,
            loot_created: 0,
            ignore_terrain: 0,
            skip_ticks: 0,
            skip_total: 0,
            skip_vx: 0,
            skip_ghost: 0,
        }
    }
    pub fn bounds(&self) -> [i64; 4] {
        let bottom = if [THROWN, SKIP].contains(&self.mode) {
            12
        } else {
            16
        };
        [-12 * S, -12 * S, 12 * S, bottom * S]
    }
    /// item_egg.gd valid (with the common vx/vy limits).
    pub fn valid(&self, body: Body) -> bool {
        (0..=3).contains(&self.variant)
            && (0..=3).contains(&self.colour)
            && (0..=3).contains(&self.mode)
            && self.skip_ticks >= 0
            && self.skip_total >= 0
            && self.skip_ticks <= self.skip_total
            && self.skip_total <= 400
            && self.skip_vx.abs() <= 512 * 60
            && [
                self.skip_ghost,
                self.floating,
                self.ignore_terrain,
                self.fall_on_terrain,
                self.camera,
                self.loot_created,
            ]
            .iter()
            .all(|v| [0, 1].contains(v))
            && self.pickup_delay >= 0
            && self.despawn_ticks >= 0
            && self.bounces <= 4
            && self.last_target >= 0
            && self.origin_token >= 0
            && (-1024 * 60..=1024 * 60).contains(&body.vx)
            && (-1024 * 60..=1024 * 60).contains(&body.vy)
    }
}

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// registry.gd overlaps_box: strict.
fn reaches(body: Body, b: [i64; 4], probe: [i64; 4]) -> bool {
    body.x + b[2] > probe[0]
        && body.x + b[0] < probe[2]
        && body.y + b[3] > probe[1]
        && body.y + b[1] < probe[3]
}
/// item_egg.gd rect_overlap: edges count.
fn rect_overlap(x: i64, y: i64, body: [i64; 4], b: [i64; 4]) -> bool {
    x + body[2] >= b[0] && x + body[0] <= b[2] && y + body[3] >= b[1] && y + body[1] <= b[3]
}

/// A full (mode 1) or one-way (mode 2) solid box remembered from a bounce target.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Shape {
    pub b: [i64; 4],
    pub mode: i64,
}

struct Contact {
    alive: bool,
    redirected: bool,
    solids: Vec<Shape>,
}

/// One spawned item from an egg's loot or the thrower's request.
pub(crate) enum Spawn {
    Egg {
        x: i64,
        y: i64,
        colour: i64,
        origin: i64,
        ghost: i64,
        vx: i64,
        vy: i64,
    },
}

impl Run {
    fn egg(&self, index: usize) -> &Egg {
        match &self.entities[index].kind {
            Kind::Egg(e) => e,
            _ => unreachable!("egg index"),
        }
    }
    fn egg_mut(&mut self, index: usize) -> &mut Egg {
        match &mut self.entities[index].kind {
            Kind::Egg(e) => e,
            _ => unreachable!("egg index"),
        }
    }
    pub(crate) fn find_token(&self, token: i64) -> Option<usize> {
        if token == 0 {
            return None;
        }
        self.entities.iter().position(|e| e.origin.token() == token)
    }
    /// item_egg.gd mark_origin: only the special persistent form (variant 3) is marked.
    pub(crate) fn mark_origin(&mut self, token: i64) {
        if let Some(i) = self.find_token(token) {
            if matches!(&self.entities[i].kind, Kind::Egg(e) if e.variant == 3) {
                self.entities[i].collected = 1;
            }
        }
    }
    /// item_egg.gd liquid_at: 2 lava, 1 water, 0 none.
    fn liquid_at(&self, index: usize, map: &Probe) -> i64 {
        let e = &self.entities[index];
        let area = world_box(e.body, self.egg(index).bounds());
        if map.lava_overlaps(area) {
            2
        } else {
            i64::from(map.water_overlaps(area))
        }
    }
    /// item_egg.gd step
    pub(crate) fn egg_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        {
            let egg = self.egg_mut(index);
            egg.pickup_delay = (egg.pickup_delay - 1).max(0);
        }
        if self.egg(index).despawn_ticks != 0 {
            self.egg_mut(index).despawn_ticks -= 1;
            if self.egg(index).despawn_ticks == 0 {
                return self.remove_egg(index, false);
            }
        }
        if self.entities[index].collected != 0 {
            return Ok(());
        }
        match self.egg(index).mode {
            THROWN => {
                self.travel(index, map)?;
                if self.egg(index).mode == THROWN && self.entities[index].status == 1 {
                    self.enter_liquid(index, map)?;
                }
            }
            SKIP => self.skip(index, map)?,
            FALLING => {
                let body = &mut self.entities[index].body;
                body.vy = (body.vy + 1600).min(576 * 60);
                body.y += body.vy;
            }
            _ => {
                let (floating, ghost, b) = {
                    let egg = self.egg(index);
                    (egg.floating, egg.ignore_terrain, egg.bounds())
                };
                if floating == 0
                    && self.entities[index]
                        .body
                        .fall_item(map, b, 1600, 576 * 60, ghost != 0)
                {
                    self.entities[index].body.vx = 0;
                }
            }
        }
        let mode = self.egg(index).mode;
        if self.entities[index].status == 1
            && ![THROWN, SKIP].contains(&mode)
            && self.liquid_at(index, map) == 2
        {
            return self.remove_egg(index, false);
        }
        Ok(())
    }
    /// item_egg.gd remove
    fn remove_egg(&mut self, index: usize, with_loot: bool) -> Result<(), Error> {
        self.entities[index].status = 3;
        let origin = self.egg(index).origin_token;
        self.mark_origin(origin);
        let egg = self.egg(index);
        if with_loot && [THROWN, SKIP].contains(&egg.mode) && egg.loot_created == 0 {
            self.egg_mut(index).loot_created = 1;
            self.loot(index)?;
        }
        Ok(())
    }
    /// item_egg.gd loot: coins, a red coin or health drops from a coloured egg.
    fn loot(&mut self, index: usize) -> Result<(), Error> {
        let (x, colour) = (self.entities[index].body.x, self.egg(index).colour);
        let y = self.entities[index].body.y;
        if [1, 3].contains(&colour) {
            let vx = if x >= self.player.body.x { -176 } else { 176 } * 60;
            let vy = -self.rng.ticks(256 * 60, 512 * 60);
            let kind = if colour == 3 {
                PickupKind::RedCoin
            } else {
                PickupKind::Coin
            };
            self.spawn_pickup(kind, x, y, vx, vy)?;
        } else if colour == 2 {
            for n in 0..2 {
                if self.player.life.health + n < 30 {
                    let vy = -self.rng.ticks(256 * 60, 384 * 60);
                    let facing = if self.rng.ticks(0, 1) == 0 { -1 } else { 1 };
                    let max_speed = self.rng.ticks(64 * 60, 128 * 60);
                    self.spawn_star(x, y, vy, facing, max_speed)?;
                } else {
                    let vx = self.rng.ticks(-192 * 60, 192 * 60);
                    let vy = -self.rng.ticks(256 * 60, 384 * 60);
                    self.spawn_pickup(PickupKind::Coin, x, y, vx, vy)?;
                }
            }
        }
        Ok(())
    }
    pub(crate) fn next_serial(&self) -> Result<i64, Error> {
        let serial = self.dynamic_serial;
        if !(1..=i64::MAX - TOKEN_BASE).contains(&serial) {
            return Err(Error::Unsupported {
                requirements: vec!["runtime creation serial".into()],
            });
        }
        Ok(serial)
    }
    /// registry.gd spawn_dynamic for a loot coin: moving, 480-tick life, 30-tick delay.
    pub(crate) fn spawn_pickup(
        &mut self,
        kind: PickupKind,
        x: i64,
        y: i64,
        vx: i64,
        vy: i64,
    ) -> Result<(), Error> {
        self.spawn_loot_coin(kind, x, y, vx, vy, 30)
    }
    /// registry.gd spawn_dynamic for a moving loot pickup with a 480-tick life.
    pub(crate) fn spawn_loot_coin(
        &mut self,
        kind: PickupKind,
        x: i64,
        y: i64,
        vx: i64,
        vy: i64,
        pickup_delay: i64,
    ) -> Result<(), Error> {
        let serial = self.next_serial()?;
        let mut pickup = Pickup::new(kind, 0, y);
        pickup.moving = 1;
        pickup.despawn_ticks = 480;
        pickup.pickup_delay = pickup_delay;
        let mut row = Entity::dynamic(serial, Kind::Pickup(pickup), Body { x, y, vx, vy }, -1, 7);
        row.can_despawn = 0;
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        Ok(())
    }
    /// registry.gd spawn_dynamic for a loot health drop (item_star.gd create: phase 10).
    pub(crate) fn spawn_star(
        &mut self,
        x: i64,
        y: i64,
        vy: i64,
        facing: i64,
        max_speed: i64,
    ) -> Result<(), Error> {
        let serial = self.next_serial()?;
        let star = Star {
            phase: 10,
            despawn_ticks: 480,
            max_speed,
            ..Star::default()
        };
        let mut row = Entity::dynamic(
            serial,
            Kind::Star(star),
            Body { x, y, vx: 0, vy },
            facing,
            7,
        );
        row.can_despawn = 0;
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        Ok(())
    }
    /// item_egg.gd hit with Hits.BUMP: a resting egg hops.
    pub(crate) fn egg_bump(&mut self, index: usize) {
        let collected = self.entities[index].collected;
        let e = &mut self.entities[index];
        if let Kind::Egg(egg) = &mut e.kind {
            if egg.mode == STATIONARY && collected == 0 {
                egg.floating = 0;
                e.body.vy = -384 * 60;
            }
        }
    }
    /// screen.gd overlaps (open edges) for an egg's box, around the camera's screen centre.
    pub(crate) fn egg_on_screen(&self, e: &Entity, centre: crate::Position) -> bool {
        let Kind::Egg(egg) = &e.kind else {
            return false;
        };
        let b = egg.bounds();
        e.body.x + b[2] > centre.x - 416 * S
            && e.body.x + b[0] < centre.x + 416 * S
            && e.body.y + b[3] > centre.y - 224 * S
            && e.body.y + b[1] < centre.y + 224 * S
    }
    /// item_block.gd o9: registry.gd spawn_dynamic("o7", x, y, {vx, vy}).
    pub(crate) fn spawn_block_egg(
        &mut self,
        x: i64,
        y: i64,
        vx: i64,
        vy: i64,
    ) -> Result<(), Error> {
        let serial = self.next_serial()?;
        let mut row = Entity::dynamic(serial, Kind::Egg(Egg::new(0)), Body { x, y, vx, vy }, -1, 7);
        row.can_despawn = 1;
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        Ok(())
    }
    /// The thrower's EGG request (item_egg.gd consume_level_requests): a thrown o7.
    pub(crate) fn spawn_thrown_egg(&mut self, spawn: Spawn) -> Result<(), Error> {
        let Spawn::Egg {
            x,
            y,
            colour,
            origin,
            ghost,
            vx,
            vy,
        } = spawn;
        let serial = self.next_serial()?;
        let mut egg = Egg::new(0);
        egg.mode = THROWN;
        egg.colour = colour;
        egg.variant = colour;
        egg.origin_token = origin;
        egg.ignore_terrain = ghost;
        let mut row = Entity::dynamic(serial, Kind::Egg(egg), Body { x, y, vx, vy }, -1, 7);
        row.can_despawn = 1;
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        Ok(())
    }
    /// item_egg.gd travel: whole-pixel substeps with object hits and ricochets.
    fn travel(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let (vx0, vy0) = (self.entities[index].body.vx, self.entities[index].body.vy);
        let steps = ((vx0.abs().max(vy0.abs()) + S - 1) / S).max(1);
        let mut last = (self.entities[index].body.x, self.entities[index].body.y);
        for step in 0..steps {
            let (vx, vy) = (self.entities[index].body.vx, self.entities[index].body.vy);
            let dx = vx * (step + 1) / steps - vx * step / steps;
            let dy = vy * (step + 1) / steps - vy * step / steps;
            let contact = self.object_collisions(index, dx, dy, map)?;
            if !contact.alive || contact.redirected {
                return Ok(());
            }
            let b = self.egg(index).bounds();
            let body = &mut self.entities[index].body;
            let (x, y) = (body.x, body.y);
            body.horizontal(map, b, dx, 0, HorizontalMove::Item);
            let mut horizontal = body.x - x != dx;
            body.vertical(map, b, dy);
            let mut vertical = body.y - y != dy;
            let preserved = preserve_solid_bounce(body, b, x, y, dx, dy, &contact.solids);
            horizontal |= preserved.0;
            vertical |= preserved.1;
            if horizontal || vertical {
                let turned = ricochet(map, b, last, (x + dx, y + dy), vx, vy, &contact.solids);
                body.vx = turned.0;
                body.vy = turned.1;
                last = (body.x, body.y);
            } else {
                body.vx = vx;
                body.vy = vy;
            }
            if horizontal || vertical {
                let egg = self.egg_mut(index);
                egg.bounces = (egg.bounces - 1).max(-9_223_372_036_854_775_806);
                if egg.colour < 2 {
                    egg.colour += 1;
                }
                if egg.bounces == 0 && egg.fall_on_terrain != 0 {
                    egg.mode = FALLING;
                    self.entities[index].body.vx = 0;
                    self.entities[index].body.vy = 0;
                    return Ok(());
                }
            }
            if self.egg(index).mode != THROWN || self.entities[index].status != 1 {
                return Ok(());
            }
        }
        Ok(())
    }
    /// item_egg.gd object_collisions
    fn object_collisions(
        &mut self,
        index: usize,
        dx: i64,
        dy: i64,
        map: &Probe,
    ) -> Result<Contact, Error> {
        let mut result = Contact {
            alive: true,
            redirected: false,
            solids: Vec::new(),
        };
        let body = self.entities[index].body;
        let b = self.egg(index).bounds();
        let probe = [
            body.x + b[0] + dx,
            body.y + b[1] + dy,
            body.x + b[2] + dx,
            body.y + b[3] + dy,
        ];
        let token = self.entities[index].origin.token();
        let last_target = self.egg(index).last_target;
        let keep = self.find_token(last_target).is_some_and(|i| {
            let o = &self.entities[i];
            reaches(o.body, entity_bounds(o), probe)
        });
        if !keep {
            self.egg_mut(index).last_target = 0;
        }
        let last_target = self.egg(index).last_target;
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
            if o.origin.token() == token
                || o.origin.token() == last_target
                || o.status != 1
                || o.collected != 0
                || held
                || hidden
            {
                continue;
            }
            let old_shapes: Vec<Shape> = match &o.kind {
                Kind::Post(p) => p
                    .solid(o.body, o.status)
                    .map(|b| vec![Shape { b, mode: 1 }])
                    .unwrap_or_default(),
                Kind::Block(bl) => bl
                    .solid(o)
                    .map(|b| vec![Shape { b, mode: 1 }])
                    .unwrap_or_default(),
                Kind::Hard(h) => h
                    .solid(o)
                    .map(|b| vec![Shape { b, mode: 1 }])
                    .unwrap_or_default(),
                Kind::SpinBlock(b) => b
                    .solid(o.status, o.body)
                    .map(|b| vec![Shape { b, mode: 1 }])
                    .unwrap_or_default(),
                Kind::Dice(d) => d
                    .solid(o.status, o.body)
                    .map(|b| vec![Shape { b, mode: 1 }])
                    .unwrap_or_default(),
                _ => Vec::new(),
            };
            let full = old_shapes.iter().any(|s| {
                s.mode == 1
                    && probe[2] >= s.b[0]
                    && probe[0] <= s.b[2]
                    && probe[3] >= s.b[1]
                    && probe[1] <= s.b[3]
            });
            if !reaches(o.body, entity_bounds(o), probe) && !full {
                continue;
            }
            // redirect_cloud.gd touches: the turned rectangle.
            if let Kind::Redirect(r) = &o.kind {
                if !r.touches(o.body.x, o.body.y, probe) {
                    continue;
                }
            }
            // one_way_gate.gd touches: the turned area.
            if let Kind::Gate(g) = &o.kind {
                if !g.touches(o.body.x, o.body.y, probe) {
                    continue;
                }
            }
            // pickup.gd touches
            if let Kind::Pickup(p) = &o.kind {
                let r = p.bounds();
                if o.collected != 0
                    || p.enabled == 0
                    || p.held != 0
                    || p.pickup_delay != 0
                    || o.body.x + r[2] <= probe[0]
                    || o.body.x + r[0] >= probe[2]
                    || o.body.y + r[3] <= probe[1]
                    || o.body.y + r[1] >= probe[3]
                {
                    continue;
                }
            }
            let enemy = matches!(o.kind, Kind::Walker(_));
            let response = self.egg_contact(index, current, map)?;
            // item_egg.gd object_collisions: Collision.refresh(world, other).
            self.refresh_block_solid(current, map);
            if response == 1 {
                self.remove_egg(index, true)?;
                result.alive = false;
                return Ok(result);
            }
            if response == 2 {
                let other_token = self.entities[current].origin.token();
                self.egg_mut(index).last_target = other_token;
                result.redirected = true;
                return Ok(result);
            }
            if response == 3 && !enemy {
                result.solids.extend(old_shapes);
            }
            if [2, 3].contains(&response) {
                let other_token = self.entities[current].origin.token();
                self.egg_mut(index).last_target = other_token;
            }
        }
        Ok(result)
    }
    /// The struck entity's projectile_contact for an egg (Hits.EGG), or its hit.
    fn egg_contact(
        &mut self,
        egg: usize,
        other: usize,
        map: &crate::body::Probe,
    ) -> Result<i64, Error> {
        enum Target {
            StiltRider,
            StiltBody,
            PlantHead,
            PlantMiss,
            Roller,
            ShellBare,
            ShellCovered,
            Armored,
            Spear,
            Thief,
            Hanging,
            Wing,
            Spine,
            Bulk,
            Spitter,
            Flower,
            Actor,
            Pickup { flower: bool },
            PickupSpent,
            Cache,
            Redirect,
            Block,
            Hard,
            Gate,
            StarFlower,
            Hound,
            Dice,
            SpinBlock,
            Bubble,
            Thorn,
            Nothing,
        }
        let projectile = self.entities[egg].body;
        let projectile_box = world_box(projectile, self.egg(egg).bounds());
        let target = {
            let o = &self.entities[other];
            match &o.kind {
                Kind::Walker(w) if w.kind == ActorKind::Stilt => {
                    if projectile.y < o.body.y - w.height + 50 * S {
                        Target::StiltRider
                    } else {
                        Target::StiltBody
                    }
                }
                Kind::Walker(w) if w.kind == ActorKind::Plant => {
                    let h = w.head_box(o.body, o.facing);
                    if w.head_size != 0
                        && h[0] < projectile_box[2]
                        && h[2] > projectile_box[0]
                        && h[1] < projectile_box[3]
                        && h[3] > projectile_box[1]
                    {
                        Target::PlantHead
                    } else {
                        Target::PlantMiss
                    }
                }
                // spear_guard.gd projectile_contact for an egg.
                Kind::Walker(w) if w.kind == ActorKind::Spear => Target::Spear,
                // sneak_thief.gd projectile_contact: struck; the egg is used up.
                Kind::Walker(w) if w.kind == ActorKind::Thief => Target::Thief,
                // hanging_roller.gd projectile_contact for an egg: 0 while rolling.
                Kind::Walker(w) if w.kind == ActorKind::Roller => Target::Hanging,
                // spitting_stem.gd projectile_contact for an egg.
                Kind::Walker(w) if w.kind == ActorKind::Spitter => Target::Spitter,
                // enemy_spike.gd projectile_contact for an egg: the egg then falls.
                Kind::Walker(w) if w.kind == ActorKind::Spike => Target::Flower,
                // enemy_pellet.gd projectile_contact returns 0.
                Kind::Walker(w) if w.kind == ActorKind::Pellet => Target::Nothing,
                // petal_stem.gd projectile_contact returns 0, as does a dropped petal's;
                // any other petal is removed (reaction 3).
                Kind::Walker(w)
                    if w.kind == ActorKind::PetalStem
                        || (w.kind == ActorKind::Petal && w.mode == crate::petal::FALL) =>
                {
                    Target::Nothing
                }
                // masked_shooter.gd projectile_contact for an egg: like the flower, the egg
                // then falls.
                Kind::Walker(w) if w.kind == ActorKind::Shooter => Target::Flower,
                // wing_drifter.gd projectile_contact.
                Kind::Walker(w) if w.kind == ActorKind::Wing => Target::Wing,
                // spine_walker.gd projectile_contact for an egg.
                Kind::Walker(w) if w.kind == ActorKind::Spine => Target::Spine,
                // slime_drop.gd projectile_contact: hanging and squashing blobs return 0.
                Kind::Walker(w) if w.kind == ActorKind::Slime && !w.slime_struck() => {
                    Target::Nothing
                }
                // leap_bulk.gd projectile_contact: an egg breaks on it (1).
                Kind::Walker(w) if w.kind == ActorKind::Bulk => Target::Bulk,
                // needle_juggler.gd and an intangible spike_hopper.gd return 0.
                Kind::Walker(w)
                    if w.kind == ActorKind::Juggler
                        || (w.kind == ActorKind::Hopper && w.intangible != 0) =>
                {
                    Target::Nothing
                }
                // armored_walker.gd projectile_contact for an egg: it rolls away.
                Kind::Walker(w) if w.kind == ActorKind::Armored => Target::Armored,
                // shell_walker.gd projectile_contact for an egg.
                Kind::Walker(w) if [ActorKind::Shell, ActorKind::Runner].contains(&w.kind) => {
                    if crate::shell::bare(w.mode) {
                        Target::ShellBare
                    } else {
                        Target::ShellCovered
                    }
                }
                Kind::Walker(w) if [ActorKind::Walker, ActorKind::Flyer].contains(&w.kind) => {
                    Target::Roller
                }
                // flat_walker.gd and hop_sprout.gd projectile_contact: like the flower,
                // the egg then falls.
                Kind::Walker(w)
                    if [
                        ActorKind::Flower,
                        ActorKind::Flat,
                        ActorKind::Sprout,
                        ActorKind::Bee,
                        ActorKind::Hopper,
                        ActorKind::Gust,
                    ]
                    .contains(&w.kind) =>
                {
                    Target::Flower
                }
                // lava_bubble.gd projectile_contact: an egg defeats it and breaks.
                Kind::Walker(w) if w.kind == ActorKind::Bubble => Target::Bubble,
                // thorn_bush.gd projectile_contact: destroyed; the egg is spent on spikes.
                Kind::Walker(w) if w.kind == ActorKind::Thorn => Target::Thorn,
                Kind::Walker(_) => Target::Actor,
                Kind::Pickup(p) => {
                    if o.collected != 0 || p.enabled == 0 || p.pickup_delay != 0 {
                        Target::PickupSpent
                    } else {
                        Target::Pickup {
                            flower: p.kind == PickupKind::Flower,
                        }
                    }
                }
                // release_cloud.gd / redirect_cloud.gd act on thrown eggs only.
                Kind::Cache(c)
                    if self.egg(egg).mode == THROWN
                        && o.collected == 0
                        && c.phase != crate::clouds::OPENING =>
                {
                    Target::Cache
                }
                Kind::Redirect(_) if self.egg(egg).mode == THROWN => Target::Redirect,
                // item_block.gd projectile_contact.
                Kind::Block(_) => Target::Block,
                // hard_block.gd projectile_contact.
                Kind::Hard(_) if o.status == 1 => Target::Hard,
                // one_way_gate.gd projectile_contact.
                Kind::Gate(_) => Target::Gate,
                // ride_hound.gd projectile_contact.
                Kind::Hound(_) => Target::Hound,
                // star_flower.gd projectile_contact.
                Kind::StarFlower(_) => Target::StarFlower,
                // dice_block.gd projectile_contact.
                Kind::Dice(_) => Target::Dice,
                // spin_block.gd projectile_contact.
                Kind::SpinBlock(_) => Target::SpinBlock,
                // item_star.gd and item_egg.gd projectile_contact return 0.
                _ => Target::Nothing,
            }
        };
        Ok(match target {
            Target::StiltRider => {
                self.unseat_stilt(other)?;
                1
            }
            Target::StiltBody => {
                let o = &mut self.entities[other];
                if let Kind::Walker(w) = &mut o.kind {
                    w.stilt_knock(&mut o.body, &mut o.facing, projectile.x);
                }
                1
            }
            Target::PlantHead => {
                self.remove_struck_actor(other)?;
                1
            }
            Target::Spear => {
                let e = &self.entities[egg];
                let o = &self.entities[other];
                let heading = if e.body.vx != 0 {
                    e.body.vx.signum()
                } else if e.body.x < o.body.x {
                    1
                } else {
                    -1
                };
                let o = &mut self.entities[other];
                if let Kind::Walker(w) = &mut o.kind {
                    w.spear_egg(o.facing, &mut o.status, &mut o.can_respawn, heading);
                }
                1
            }
            Target::Thief => {
                self.thief_struck(other, projectile.x)?;
                1
            }
            Target::Spitter => {
                self.spitter_projectile(other, projectile_box, projectile.x, false, false)
            }
            Target::Hanging => {
                let o = &mut self.entities[other];
                match &mut o.kind {
                    Kind::Walker(w) if w.mode != crate::roller::ROLL => {
                        w.roller_hit();
                        1
                    }
                    _ => 0,
                }
            }
            Target::Bulk => {
                self.bulk_defeat(other)?;
                1
            }
            Target::Wing => {
                let o = &mut self.entities[other];
                let Kind::Walker(w) = &mut o.kind else {
                    unreachable!()
                };
                w.wing_struck(o.body, projectile)
            }
            Target::Armored => {
                let direction = if self.entities[egg].body.vx > 0 {
                    1
                } else {
                    -1
                };
                let o = &mut self.entities[other];
                if let Kind::Walker(w) = &mut o.kind {
                    w.armored_roll(&mut o.body, direction);
                }
                1
            }
            Target::ShellBare => {
                // The egg then falls; the runner is removed.
                self.egg_mut(egg).fall_on_terrain = 1;
                if self.entities[other].status == 1 {
                    self.shell_remove(other);
                }
                3
            }
            Target::ShellCovered => {
                let o = &mut self.entities[other];
                if let Kind::Walker(w) = &mut o.kind {
                    w.shell_hit(
                        &mut o.body,
                        &mut o.facing,
                        &mut o.status,
                        &mut o.can_respawn,
                        crate::eating::HitKind::Egg,
                        projectile.x,
                    );
                }
                1
            }
            Target::Roller => {
                let o = &mut self.entities[other];
                if let Kind::Walker(w) = &mut o.kind {
                    if w.held == 0 && o.status == 1 {
                        let direction = if o.body.x > projectile.x { 1 } else { -1 };
                        w.start_roll(&mut o.body, &mut o.facing, direction, 0, false);
                    }
                }
                1
            }
            Target::Flower => {
                self.remove_struck_actor(other)?;
                self.egg_mut(egg).fall_on_terrain = 1;
                3
            }
            Target::Actor => {
                self.remove_struck_actor(other)?;
                3
            }
            Target::Thorn => self.thorn_projectile(other)?,
            Target::Bubble => {
                self.remove_enemy(other)?;
                1
            }
            Target::Pickup { flower } => {
                self.collect_item(other);
                if flower {
                    1
                } else {
                    3
                }
            }
            Target::Cache => {
                let o = &mut self.entities[other];
                if let Kind::Cache(c) = &mut o.kind {
                    c.hit(o.status, o.collected);
                }
                1
            }
            Target::Redirect => {
                // redirect_cloud.gd projectile_contact: snap to the cloud, turn, maybe pop.
                let (cloud, angle, infinite, last_egg) = {
                    let o = &self.entities[other];
                    let Kind::Redirect(r) = &o.kind else {
                        unreachable!()
                    };
                    (o.body, r.angle, r.infinite, r.last_egg)
                };
                let token = self.entities[egg].origin.token();
                let body = &mut self.entities[egg].body;
                let speed = root(body.vx * body.vx + body.vy * body.vy);
                let (vx, vy) = crate::turn::vector(angle - 90_000, speed);
                body.x = cloud.x;
                body.y = cloud.y;
                body.vx = vx;
                body.vy = vy;
                self.egg_mut(egg).camera = 1;
                if last_egg != token {
                    self.egg_mut(egg).despawn_ticks = 600;
                }
                let o = &mut self.entities[other];
                if let Kind::Redirect(r) = &mut o.kind {
                    r.last_egg = token;
                }
                if infinite == 0 {
                    o.status = 3;
                }
                2
            }
            Target::Block => self.block_projectile_contact(other)?,
            Target::Dice => self.dice_projectile_contact(other, map)?,
            Target::SpinBlock => self.spin_block_projectile_contact(other)?,
            Target::Hard => {
                // o28/o29: the following physical bounce spends this extra charge.
                if matches!(&self.entities[other].kind, Kind::Hard(h) if h.refunds_bounce()) {
                    let egg = self.egg_mut(egg);
                    egg.bounces = egg.bounces.saturating_add(1);
                }
                let o = &mut self.entities[other];
                if let Kind::Hard(h) = &mut o.kind {
                    h.egg_hit(&mut o.status);
                }
                3
            }
            Target::Hound => {
                // A thrown egg drops beside a free runner, which plays with it.
                let o = &self.entities[other];
                let Kind::Hound(h) = &o.kind else {
                    unreachable!()
                };
                if h.ridden != 0 || h.playing != 0 || h.swimming != 0 {
                    return Ok(0);
                }
                let at = o.body.x;
                let token = self.entities[egg].origin.token();
                let e = &mut self.entities[egg];
                e.body.vy = -384 * 60;
                e.body.vx = if e.body.x < at { -384 } else { 384 } * 60;
                if let Kind::Egg(g) = &mut e.kind {
                    g.mode = STATIONARY;
                    g.floating = 0;
                    g.camera = 0;
                }
                if let Kind::Hound(h) = &mut self.entities[other].kind {
                    h.playing = 1;
                    h.egg_token = token;
                }
                2
            }
            Target::StarFlower => {
                // An open cup drops the egg beside it as a resting egg.
                let o = &self.entities[other];
                let Kind::StarFlower(f) = &o.kind else {
                    unreachable!()
                };
                let Some((vx, vy)) = f.egg_contact(o.body, projectile) else {
                    return Ok(0);
                };
                let e = &mut self.entities[egg];
                e.body.vx = vx;
                e.body.vy = vy;
                if let Kind::Egg(g) = &mut e.kind {
                    g.mode = STATIONARY;
                    g.floating = 0;
                    g.camera = 0;
                }
                2
            }
            Target::Gate => {
                let thrown = self.egg(egg).mode == THROWN;
                let o = &mut self.entities[other];
                if let Kind::Gate(g) = &mut o.kind {
                    g.egg_contact(
                        (o.status, o.body.x, o.body.y),
                        crate::Position {
                            x: projectile.x,
                            y: projectile.y,
                        },
                        thrown,
                    );
                }
                0
            }
            // spine_walker.gd: a walking one is removed and the egg falls (3); folding
            // spines absorb nothing (0); raised spines break the egg (1) and fold.
            Target::Spine => {
                let Kind::Walker(w) = &mut self.entities[other].kind else {
                    unreachable!()
                };
                match w.mode {
                    crate::spine::WALK => {
                        self.egg_mut(egg).fall_on_terrain = 1;
                        self.remove_struck_actor(other)?;
                        3
                    }
                    crate::spine::SHRINK => 0,
                    _ => {
                        w.spine_shrink();
                        1
                    }
                }
            }
            Target::PlantMiss | Target::PickupSpent | Target::Nothing => 0,
        })
    }
    fn remove_struck_actor(&mut self, index: usize) -> Result<(), Error> {
        let e = &self.entities[index];
        if let Kind::Walker(w) = &e.kind {
            if w.held != 0 || e.status != 1 {
                return Ok(());
            }
            // Body.remove runs actor.gd on_remove first (the capturing e5 lets go).
            self.plant_on_remove(index);
            let e = &mut self.entities[index];
            if let Kind::Walker(w) = &mut e.kind {
                w.remove(&mut e.status, &mut e.can_respawn);
            }
        }
        Ok(())
    }
    /// item_egg.gd enter_liquid
    fn enter_liquid(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let kind = self.liquid_at(index, map);
        let body = self.entities[index].body;
        if kind == 0 || (body.vx == 0 && body.vy == 0) {
            return Ok(());
        }
        let angle = angle_to(body.vx, body.vy);
        let speed = root(body.vx * body.vx + body.vy * body.vy).min(SPEED);
        if angle > 0 && angle < 30_000 {
            self.start_skip(index, speed / 2, angle / 400 + 120);
        } else if angle > 150_000 && angle < 180_000 {
            self.start_skip(index, -speed / 2, angle / 3000 + 120);
        } else if angle > 30_000 && angle < 150_000 {
            if kind == 2 {
                return self.remove_egg(index, false);
            }
            self.settle(index, -256 * 60, true);
        }
        Ok(())
    }
    fn start_skip(&mut self, index: usize, vx: i64, ticks: i64) {
        let egg = self.egg_mut(index);
        egg.mode = SKIP;
        egg.skip_vx = vx;
        egg.skip_total = ticks;
        egg.skip_ticks = 0;
        egg.skip_ghost = 0;
        self.entities[index].body.vx = vx;
    }
    fn settle(&mut self, index: usize, vy: i64, in_liquid: bool) {
        let egg = self.egg_mut(index);
        egg.mode = STATIONARY;
        egg.floating = 0;
        egg.camera = 0;
        egg.skip_ghost = 0;
        if in_liquid {
            egg.despawn_ticks = 480;
        }
        self.entities[index].body.vx = 0;
        self.entities[index].body.vy = vy;
    }
    /// item_egg.gd skip: a shallow liquid entry glides while its speed eases to zero.
    fn skip(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        {
            let egg = self.egg_mut(index);
            egg.skip_ticks += 1;
            let vx = egg.skip_vx * (egg.skip_total - egg.skip_ticks) / egg.skip_total;
            self.entities[index].body.vx = vx;
        }
        let b = self.egg(index).bounds();
        if self.liquid_at(index, map) != 0 {
            self.entities[index].body.vy = -256 * 60;
        } else {
            let body = &mut self.entities[index].body;
            body.vy = (body.vy + 1536).min(704 * 60);
        }
        if self.egg(index).skip_ghost == 0 {
            let (vx, vy) = (self.entities[index].body.vx, self.entities[index].body.vy);
            if !self.object_collisions(index, vx, vy, map)?.alive {
                return Ok(());
            }
        }
        let body = &mut self.entities[index].body;
        let x = body.x;
        let vx = body.vx;
        let moved = body.horizontal(map, b, vx, 0, HorizontalMove::Item);
        if moved != body.vx {
            self.egg_mut(index).skip_ghost = 1;
        }
        let body = &mut self.entities[index].body;
        let desired = body.vy;
        let actual = body.vertical(map, b, desired);
        if desired > 0 && actual != desired {
            self.settle(index, -256 * 60, false);
            return Ok(());
        }
        if self.egg(index).skip_ticks >= self.egg(index).skip_total {
            let kind = self.liquid_at(index, map);
            if kind == 2 {
                return self.remove_egg(index, false);
            }
            self.settle(index, 0, kind == 1);
        }
        let body = self.entities[index].body;
        if body.x == x && body.vx != 0 {
            self.egg_mut(index).skip_ghost = 1;
        }
        Ok(())
    }
    /// item_egg.gd contact + grant: a resting egg joins the inventory.
    pub(crate) fn egg_contact_player(&mut self, index: usize) -> Result<(), Error> {
        let egg = self.egg(index);
        if egg.mode != STATIONARY
            || self.entities[index].collected != 0
            || egg.pickup_delay != 0
            || self.player.blocks_step()
        {
            return Ok(());
        }
        let p = self.player.bounds();
        let player = world_box(self.player.body, p);
        if !reaches(self.entities[index].body, egg.bounds(), player) {
            return Ok(());
        }
        // grant: the level consumers run first (item_egg.gd consume_level_requests).
        for action in self
            .consumers
            .run_eggs(&self.player.food.requests, self.player.food.eggs)?
        {
            self.apply_consumer(action)?;
        }
        let e = &self.entities[index];
        let egg = self.egg(index);
        let origin = if matches!(e.origin, Origin::Placed(_)) {
            e.origin.token()
        } else {
            egg.origin_token
        };
        let (colour, ghost, origin_token) = (egg.colour, egg.ignore_terrain, egg.origin_token);
        if let Some(popped) = self.consumers.push_egg(colour, origin, ghost) {
            self.mark_origin(popped);
        }
        self.player.give_eggs(1);
        if origin_token != 0 {
            if let Some(i) = self.find_token(origin_token) {
                if !matches!(&self.entities[i].kind, Kind::Egg(o) if o.variant == 3) {
                    self.entities[i].collected = 1;
                }
            }
        }
        self.entities[index].status = 3;
        self.entities[index].can_respawn = 0;
        Ok(())
    }
    pub(crate) fn apply_consumer(&mut self, action: crate::consumers::Action) -> Result<(), Error> {
        match action {
            crate::consumers::Action::Spawn(spawn) => self.spawn_thrown_egg(spawn),
            crate::consumers::Action::MarkOrigin(token) => {
                self.mark_origin(token);
                Ok(())
            }
            crate::consumers::Action::Seed(x, y, angle) => self.spawn_seed(x, y, angle),
            crate::consumers::Action::Shot {
                element,
                x,
                y,
                angle,
            } => self.spawn_shot(element, x, y, angle),
        }
    }
    /// item_egg.gd tongue: a resting egg is nudged away and blocks the tongue.
    pub(crate) fn egg_tongue(&mut self, index: usize) -> i64 {
        let player_x = self.player.body.x;
        let collected = self.entities[index].collected;
        let e = &mut self.entities[index];
        let Kind::Egg(egg) = &mut e.kind else {
            return 0;
        };
        if collected != 0 || egg.mode == FALLING {
            return 0;
        }
        egg.mode = STATIONARY;
        egg.floating = 0;
        egg.camera = 0;
        e.body.vy = -384 * 60;
        e.body.vx = if e.body.x >= player_x { -256 } else { 256 } * 60;
        2
    }
}

/// registry.gd overlaps_box bounds for each kind (type.bounds or a point).
pub(crate) fn entity_bounds(e: &Entity) -> [i64; 4] {
    match &e.kind {
        Kind::Walker(w) => w.bounds(e.body, e.facing),
        Kind::Pickup(p) => p.bounds(),
        Kind::Star(p) => p.bounds(),
        Kind::Post(p) => p.bounds(),
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
        _ => [0; 4],
    }
}

/// item_egg.gd preserve_solid_bounce
fn preserve_solid_bounce(
    body: &mut Body,
    b: [i64; 4],
    x: i64,
    y: i64,
    dx: i64,
    dy: i64,
    shapes: &[Shape],
) -> (bool, bool) {
    let (mut horizontal, mut vertical) = (false, false);
    for s in shapes {
        if s.mode == 1 && dx != 0 && rect_overlap(x + dx, y, b, s.b) {
            body.x = if dx > 0 {
                s.b[0] - b[2] - 1
            } else {
                s.b[2] - b[0] + 1
            };
            horizontal = true;
        }
        if dy != 0
            && rect_overlap(body.x, y + dy, b, s.b)
            && (s.mode == 1 || dy > 0 && y + b[3] <= s.b[1])
        {
            body.y = if dy > 0 {
                s.b[1] - b[3] - 1
            } else {
                s.b[3] - b[1] + 1
            };
            vertical = true;
        }
    }
    (horizontal, vertical)
}

fn blocked_at(map: &Probe, b: [i64; 4], x: i64, y: i64, shapes: &[Shape]) -> bool {
    let probe = Body { x, y, vx: 0, vy: 0 };
    probe.overlaps(map, b, 0, 0)
        || shapes
            .iter()
            .any(|s| s.mode == 1 && rect_overlap(x, y, b, s.b))
}

/// item_egg.gd ricochet: probe a circle around the last position in 5-degree steps.
fn ricochet(
    map: &Probe,
    b: [i64; 4],
    last: (i64, i64),
    hit: (i64, i64),
    vx: i64,
    vy: i64,
    shapes: &[Shape],
) -> (i64, i64) {
    let speed = SPEED.min(root(vx * vx + vy * vy));
    let (mut dx, mut dy) = (hit.0 - last.0, hit.1 - last.1);
    if dx == 0 && dy == 0 {
        dx = vx;
        dy = vy;
    }
    let travel_angle = angle_to(dx, dy);
    let radius = (10 * S).max(root(dx * dx + dy * dy));
    let mut sides = [0i64; 2];
    for (n, sign) in [-1i64, 1].into_iter().enumerate() {
        let mut found = (travel_angle + 180_000).rem_euclid(360_000);
        for step in 1..36 {
            let angle = (travel_angle + sign * step * 5000).rem_euclid(360_000);
            let x = last.0 + turn_cosine(angle, radius);
            let y = last.1 + turn_sine(angle, radius);
            if !blocked_at(map, b, x, y, shapes) {
                found = angle;
                break;
            }
        }
        sides[n] = found;
    }
    let result = if sides[0] == sides[1] {
        sides[0]
    } else {
        let spread = (sides[1] - sides[0]).rem_euclid(360_000);
        let normal = (sides[0] + spread / 2 + 180_000).rem_euclid(360_000);
        let lx = turn_cosine(travel_angle, UNIT);
        let ly = turn_sine(travel_angle, UNIT);
        let nx = turn_cosine(normal, UNIT);
        let ny = turn_sine(normal, UNIT);
        let dot = (lx * nx + ly * ny) / UNIT;
        angle_to(lx - 2 * dot * nx / UNIT, ly - 2 * dot * ny / UNIT)
    };
    exact_turn(result, speed, vx, vy)
}

/// item_egg.gd exact_turn: a pure axis flip keeps exact integer speed.
fn exact_turn(angle: i64, speed: i64, vx: i64, vy: i64) -> (i64, i64) {
    if vy != 0 || vx != 0 {
        if angle_delta(angle, angle_to(-vx, vy)).abs() <= 500 {
            return (-vx, vy);
        }
        if angle_delta(angle, angle_to(vx, -vy)).abs() <= 500 {
            return (vx, -vy);
        }
    }
    (turn_cosine(angle, speed), turn_sine(angle, speed))
}
