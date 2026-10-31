//! Runtime suffix reconstruction and stable token/family compaction.
use crate::{
    actors::{Actor, ActorKind},
    body::Body,
    entity::{Entity, Kind, Origin, TOKEN_BASE},
    items::{Pickup, PickupKind, Star},
    schema::{Field, Schema},
    state::Run,
    wire::WireEntity,
    Error, Position,
};
fn refuse(reason: &str) -> Error {
    Error::Unsupported {
        requirements: vec![format!("runtime entity: {reason}")],
    }
}
pub(crate) fn restore_head(
    row: &WireEntity,
    schema: &Schema,
    family_index: i64,
) -> Result<Entity, Error> {
    let serial = row
        .id
        .strip_prefix('+')
        .and_then(|v| v.parse::<i64>().ok())
        .filter(|v| *v >= 1 && *v <= i64::MAX - TOKEN_BASE && row.id == format!("+{v}"))
        .ok_or_else(|| refuse("invalid canonical runtime id"))?;
    let value = |name: &str| -> Result<i64, Error> {
        schema
            .entity_fields(&row.code)
            .iter()
            .zip(&row.values)
            .find(|(Field(n, _), _)| n == name)
            .map(|(_, v)| *v)
            .ok_or_else(|| refuse("missing declared header field"))
    };
    if value("source_index")? != -1
        || value("token")? != TOKEN_BASE + serial
        || value("map_index")? != 1
    {
        return Err(refuse("runtime identity differs"));
    }
    let position = Position {
        x: value("x")?,
        y: value("y")?,
    };
    let facing = value("facing")?;
    let kind = match row.code.as_str() {
        "e1" | "e2" | "e3" | "e5" => {
            let kind = match row.code.as_str() {
                "e1" => ActorKind::Walker,
                "e2" => ActorKind::Flyer,
                "e3" => ActorKind::Flower,
                _ => ActorKind::Plant,
            };
            Kind::Walker(Actor::new(
                kind,
                value("variant")?,
                i64::from(facing > 0),
                position,
            ))
        }
        // shell_walker.gd enemy_runner: saved fields are restored after the head.
        "enemy_runner" => Kind::Walker(Actor::new(ActorKind::Runner, 0, 0, position)),
        // masked_shooter.gd enemy_pellet: saved fields are restored after the head.
        "enemy_pellet" => Kind::Walker(Actor::new(ActorKind::Pellet, 0, 0, position)),
        // launcher_shot.gd: saved fields are restored after the head.
        "enemy_shot" => Kind::Walker(Actor::new(ActorKind::Shot, 0, 0, position)),
        // hop_sprout.gd grown from a drift_spore.gd: saved fields follow the head.
        "e12" => Kind::Walker(Actor::new(ActorKind::Sprout, 0, 0, position)),
        // spike_hopper.gd (a needle_juggler.gd hopper): saved fields follow the head.
        "e40" => Kind::Walker(Actor::new(
            ActorKind::Hopper,
            value("variant")?,
            0,
            position,
        )),
        "o1" | "o2" | "o3" => Kind::Pickup(Pickup::new(
            match row.code.as_str() {
                "o1" => PickupKind::Coin,
                "o2" => PickupKind::RedCoin,
                _ => PickupKind::Flower,
            },
            0,
            position.y,
        )),
        "o4" => Kind::Star(Star::default()),
        "o14" => Kind::Switch(crate::switch::Switch::released()),
        "o7" => Kind::Egg(crate::egg::Egg::new(0)),
        "seed_shot" => Kind::Seed(crate::melon::Seed { heading: 0 }),
        // enemy_overlap.gd: a and b are restored after the head.
        "enemy_overlap" => Kind::Overlap(crate::roller::Overlap::default()),
        _ => return Err(refuse("dynamic code outside implemented runtime closure")),
    };
    let mut entity = Entity::dynamic(
        serial,
        kind,
        Body {
            x: position.x,
            y: position.y,
            ..Body::default()
        },
        facing,
        value("layer")?,
    );
    entity.family_index = if entity.is_enemy() { family_index } else { 0 };
    Ok(entity)
}
impl Run {
    pub(crate) fn spawn_walker(
        &mut self,
        position: Position,
        variant: i64,
        facing: i64,
        layer: i64,
    ) -> Result<(), Error> {
        let serial = self.dynamic_serial;
        if !(1..=i64::MAX - TOKEN_BASE).contains(&serial)
            || !(0..=4).contains(&variant)
            || ![-1, 1].contains(&facing)
        {
            return Err(refuse("walker creation options/serial"));
        }
        let mut actor = Actor::new(ActorKind::Walker, variant, 0, position);
        actor.activate(facing, &mut self.rng);
        let family = self.entities.iter().filter(|e| e.is_enemy()).count() as i64;
        let mut row = Entity::dynamic(
            serial,
            Kind::Walker(actor),
            Body {
                x: position.x,
                y: position.y,
                ..Body::default()
            },
            facing,
            layer,
        );
        row.family_index = family;
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        Ok(())
    }
    pub(crate) fn compact(&mut self) {
        let captor = self
            .entities
            .iter()
            .find(|e| {
                matches!(e.kind, Kind::Walker(_)) && e.family_index + 1 == self.player.captured_by
            })
            .map(|e| e.origin.token());
        self.entities.retain(|e| {
            matches!(e.origin, Origin::Placed(_))
                || e.status != 3
                || Some(e.origin.token()) == captor
                || match &e.kind {
                    Kind::Walker(a) => a.held == 1,
                    Kind::Pickup(p) => p.held == 1,
                    Kind::Star(p) => p.held == 1,
                    _ => false,
                }
        });
        let mut family = 0;
        self.player.captured_by = 0;
        for e in &mut self.entities {
            if e.is_enemy() {
                e.family_index = family;
                family += 1;
                if Some(e.origin.token()) == captor {
                    self.player.captured_by = family;
                }
            }
        }
    }
}
