//! Selected o23 post state; collision geometry is projected into the per-step solid frame.
use crate::{body::Body, Error, Placement, PropertyValue, SCALE as S};
#[derive(Clone, Debug)]
pub(crate) struct Post {
    pub height: i64,
    pub colour: i64,
    pub spiked: i64,
}
impl crate::state::Run {
    pub(crate) fn apply_post_updates(
        &mut self,
        updates: Vec<crate::solids::PostUpdate>,
    ) -> Result<(), Error> {
        for update in updates {
            let mut index = 0;
            while index < self.entities.len() {
                let e = &mut self.entities[index];
                index += 1;
                if e.origin.token() == update.token || e.status != 1 {
                    continue;
                }
                let crate::entity::Kind::Walker(actor) = &mut e.kind else {
                    continue;
                };
                let bounds = actor.bounds(e.body, e.facing);
                let foot = e.body.y + bounds[3];
                if e.body.x + bounds[2] < update.strike_box[0]
                    || e.body.x + bounds[0] > update.strike_box[2]
                    || foot > update.strike_box[1] + S
                    || foot < update.strike_box[1] - 2 * S
                    || actor.held != 0
                {
                    continue;
                }
                // shy_ghost.gd and blind_ghost.gd hit rules differ from removal.
                if [
                    crate::actors::ActorKind::Shy,
                    crate::actors::ActorKind::Blind,
                ]
                .contains(&actor.kind)
                {
                    return Err(Error::Unsupported {
                        requirements: vec!["post strike on an e26/e39 ghost".into()],
                    });
                }
                let spawn = if actor.kind == crate::actors::ActorKind::Stilt {
                    Some((
                        crate::Position {
                            x: e.body.x,
                            y: e.body.y - actor.height + 34 * S,
                        },
                        actor.variant,
                        e.facing,
                        e.layer,
                    ))
                } else {
                    None
                };
                if self.player.captured_by == e.family_index + 1 {
                    return Err(Error::Unsupported {
                        requirements: vec![
                            "post strike captured-plant release requires request closure".into(),
                        ],
                    });
                }
                e.status = 3;
                e.can_respawn = 0;
                actor.held = 0;
                actor.spat = 0;
                if let Some((p, variant, facing, layer)) = spawn {
                    self.spawn_walker(p, variant, facing, layer)?;
                }
            }
            let e = self
                .entities
                .iter_mut()
                .find(|e| e.origin.token() == update.token)
                .expect("post update retains placed token");
            let crate::entity::Kind::Post(post) = &mut e.kind else {
                unreachable!("solid update belongs to post")
            };
            post.height = update.height;
            e.status = update.status;
        }
        Ok(())
    }
}
impl Post {
    pub fn new(source: &Placement) -> Result<Self, Error> {
        let option = |key: &str| -> Result<i64, Error> {
            let raw = source
                .properties
                .iter()
                .find(|(name, _)| name == key)
                .map(|(_, v)| v);
            let n = match raw {
                None => Some(0.0),
                Some(PropertyValue::Number(n)) => Some(*n),
                Some(PropertyValue::String(s)) if s.is_empty() => Some(0.0),
                Some(PropertyValue::String(s)) => s.trim().parse::<f64>().ok(),
                _ => None,
            }
            .filter(|n| n.is_finite() && n.abs() <= (i64::MAX / S - 1) as f64)
            .ok_or_else(|| Error::Unsupported {
                requirements: vec![format!("invalid post option {key}")],
            })?;
            Ok(n as i64)
        };
        let height = option("E1")?
            .checked_mul(S)
            .filter(|v| (0..=i64::MAX / 16384).contains(v))
            .ok_or_else(|| Error::Unsupported {
                requirements: vec!["post height headroom".into()],
            })?;
        let post = Self {
            height,
            colour: option("E2")?,
            spiked: option("E3")?,
        };
        if !post.valid() {
            return Err(Error::Unsupported {
                requirements: vec!["post colour/pointed form".into()],
            });
        }
        Ok(post)
    }
    pub fn bounds(&self) -> [i64; 4] {
        [-16 * S, -self.height, 16 * S, 0]
    }
    pub fn solid(&self, body: Body, status: i64) -> Option<[i64; 4]> {
        (status == 1 && self.height > 0).then_some([
            body.x - 16 * S,
            body.y - self.height,
            body.x + 16 * S,
            body.y,
        ])
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "height" => self.height,
            "colour" => self.colour,
            "spiked" => self.spiked,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        let slot = match n {
            "height" => &mut self.height,
            "colour" => &mut self.colour,
            "spiked" => &mut self.spiked,
            _ => return false,
        };
        *slot = value;
        true
    }
    pub fn valid(&self) -> bool {
        (0..=i64::MAX / 16384).contains(&self.height)
            && (0..=16).contains(&self.colour)
            && [0, 1].contains(&self.spiked)
    }
}
