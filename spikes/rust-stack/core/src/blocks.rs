//! item_block.gd for o9 (egg block), o15 (linked on/off block) and o18 (message block).
//! o24 (the shrinking clear block) is refused until ported.
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
            _ => {
                return Err(Error::Unsupported {
                    requirements: vec![format!("item block {}", p.code)],
                })
            }
        };
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
            home_y: p.position.y,
            busy: 0,
            bump_direction: 1,
            enabled,
            solid_ready: enabled,
            charges: 3,
            height: 32 * S,
            height_from: 32 * S,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        [-16 * S, -16 * S, 16 * S, 16 * S]
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
        }
        Ok(())
    }
    /// item_block.gd bump, side 0 (from below) only.
    pub(crate) fn block_bump(&mut self, index: usize) -> Result<(), Error> {
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
            BlockKind::Linked => {}
        }
        Ok(())
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
    pub(crate) fn modal_step(&mut self, input: u8, world: &crate::World) -> bool {
        if self.message.modal_token == 0 {
            return false;
        }
        let Some(index) = self.find_token(self.message.modal_token) else {
            self.message.modal_token = 0;
            return false;
        };
        if !matches!(&self.entities[index].kind, Kind::Block(b) if b.kind == BlockKind::Message) {
            self.message.modal_token = 0;
            return false;
        }
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
    /// item_block.gd bump_above: BUMP hits on whatever stands just above the block.
    fn bump_above(&mut self, index: usize) -> Result<(), Error> {
        let e = &self.entities[index];
        let b = self.block(index).bounds();
        let probe = [
            e.body.x + b[0],
            e.body.y + b[1] - 8 * S,
            e.body.x + b[2],
            e.body.y + b[3] - 8 * S,
        ];
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
                _ => continue,
            };
            let ob = [
                o.body.x + ob[0],
                o.body.y + ob[1],
                o.body.x + ob[2],
                o.body.y + ob[3],
            ];
            if !overlap(ob, probe) {
                continue;
            }
            self.bump_hit(current, from_x)?;
        }
        Ok(())
    }
    /// Each type's `hit` with Hits.BUMP.
    fn bump_hit(&mut self, index: usize, from_x: i64) -> Result<(), Error> {
        let e = &mut self.entities[index];
        match &mut e.kind {
            Kind::Walker(w) if w.kind == crate::actors::ActorKind::Stilt => {
                w.stilt_knock(&mut e.body, &mut e.facing, from_x);
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
            // pickup.gd and release_cloud.gd ignore BUMP; item_block.gd hit is EGG only.
            _ => {}
        }
        Ok(())
    }
    /// item_egg.gd active_count: carried eggs plus loose on-screen eggs.
    fn active_eggs(&self, centre: crate::Position) -> i64 {
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
