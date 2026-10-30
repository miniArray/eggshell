use crate::{
    schema::{Field, Schema},
    state::{Kind, Run},
    wire::WireSnapshot,
    Error, World,
};
impl Run {
    pub fn restored(wire: &WireSnapshot, world: &World, schema: &Schema) -> Result<Self, Error> {
        let mut run = Self::create(world, &mut crate::Stats::default())?;
        if wire.entities.len() != run.entities.len() {
            return Err(refuse("entity count/runtime suffix"));
        }
        for (Field(name, default), value) in schema.level().iter().zip(&wire.level) {
            match name.as_str() {
                "frame" => run.frame = *value,
                "camera_x" => run.camera.x = *value,
                "camera_y" => run.camera.y = *value,
                "rng" => run.rng = crate::math::Rng::from_saved(*value)?,
                "goal_reached" => run.goal_reached = *value,
                "deaths" => run.deaths = *value,
                "play_ticks" => run.play_ticks = *value,
                "total_play_ticks" => run.total_play_ticks = *value,
                "coins" => run.coins = *value,
                "redcoins" => run.redcoins = *value,
                "flowers" => run.flowers = *value,
                "sound_serial" => run.sound.serial = *value,
                "sound_kind" => run.sound.kind = *value,
                "sound_x" => run.sound.x = *value,
                "sound_y" => run.sound.y = *value,
                _ => {
                    let expected = run.wire(world, schema);
                    let index = schema
                        .level()
                        .iter()
                        .position(|f| f.0 == *name)
                        .ok_or_else(|| refuse("schema"))?;
                    if *value != expected.level[index] && *value != *default {
                        return Err(refuse(name));
                    }
                }
            }
        }
        for (Field(name, default), value) in schema.player().iter().zip(&wire.player) {
            if name == "attempt_ticks" {
                run.attempt_ticks = *value;
            } else if !run.player.set_field(name, *value) && value != default {
                return Err(refuse(name));
            }
        }
        for (e, encoded) in run.entities.iter_mut().zip(&wire.entities) {
            let source = &world.maps[0].placements[e.source];
            if encoded.id != source.id || encoded.code != source.code {
                return Err(refuse("ordered world table"));
            }
            let fields = schema.entity_fields(&source.code);
            for (Field(name, default), value) in fields.iter().zip(&encoded.values) {
                let specific = match &mut e.kind {
                    Kind::Pickup(p) => p.set_field(name, *value),
                    Kind::Star(p) => p.set_field(name, *value),
                    Kind::Walker(p) => p.set_field(name, *value),
                    _ => false,
                };
                let handled = if specific {
                    true
                } else {
                    match name.as_str() {
                        "x" => {
                            e.body.x = *value;
                            true
                        }
                        "y" => {
                            e.body.y = *value;
                            true
                        }
                        "vx" => {
                            e.body.vx = *value;
                            true
                        }
                        "vy" => {
                            e.body.vy = *value;
                            true
                        }
                        "facing" => {
                            e.facing = *value;
                            true
                        }
                        "status" => {
                            e.status = *value;
                            true
                        }
                        "offscreen" => {
                            e.offscreen = *value;
                            true
                        }
                        "collected" => {
                            e.collected = *value;
                            true
                        }
                        "checkpoint_collected" => {
                            e.checkpoint_collected = *value;
                            true
                        }
                        "squash" | "active" => {
                            if let Kind::Pad(pad) = &mut e.kind {
                                if name == "squash" {
                                    pad.squash = *value;
                                } else {
                                    match value {
                                        0 => pad.active = false,
                                        1 => pad.active = true,
                                        _ => return Err(refuse("pad active flag")),
                                    }
                                }
                                true
                            } else {
                                false
                            }
                        }
                        "phase" | "timer" | "cycles" | "mode" | "started" | "contact" => {
                            if let Kind::Walker(w) = &mut e.kind {
                                match name.as_str() {
                                    "phase" => w.phase = *value,
                                    "timer" => w.timer = *value,
                                    "cycles" => w.cycles = *value,
                                    "mode" => w.mode = *value,
                                    "started" => w.started = *value,
                                    _ => w.contact = *value,
                                };
                                true
                            } else {
                                false
                            }
                        }
                        "large" | "single_use" => {
                            let crate::PreparedPlacement::Pad { large, single_use } =
                                source.prepared
                            else {
                                return Err(refuse("pad source flags"));
                            };
                            if *value != i64::from(if name == "large" { large } else { single_use })
                            {
                                return Err(refuse("pad source flags differ"));
                            }
                            true
                        }
                        "source_index" => {
                            if *value != e.source as i64 {
                                return Err(refuse(name));
                            }
                            true
                        }
                        "token" => {
                            if *value != e.source as i64 + 1 {
                                return Err(refuse(name));
                            }
                            true
                        }
                        "family_index" => {
                            if *value != e.family_index {
                                return Err(refuse(name));
                            }
                            true
                        }
                        "map_index" => {
                            if *value != 1 {
                                return Err(refuse(name));
                            }
                            true
                        }
                        "layer" => {
                            if *value
                                != if matches!(e.kind, Kind::Walker(_)) {
                                    8
                                } else {
                                    7
                                }
                            {
                                return Err(refuse(name));
                            }
                            true
                        }
                        "spawn_mode" | "can_despawn" | "can_respawn" => {
                            if *value
                                != i64::from(matches!(e.kind, Kind::Walker(_) | Kind::Star(_)))
                            {
                                return Err(refuse(name));
                            }
                            true
                        }
                        "spawn_x" | "home_x" => {
                            if *value != source.position.x {
                                return Err(refuse(name));
                            }
                            true
                        }
                        "spawn_y" | "home_y" => {
                            if *value != source.position.y {
                                return Err(refuse(name));
                            }
                            true
                        }
                        _ => false,
                    }
                };
                if !handled && value != default {
                    return Err(refuse(name));
                }
            }
        }
        run.validate(world)?;
        // Compare the entire declared payload after typed reconstruction. This catches
        // constants, unsupported unused fields and cross-field assumptions in one seam.
        if let Some(diff) = wire.first_difference(&run.wire(world, schema), schema) {
            return Err(refuse(&format!("{}:{}", diff.scope, diff.field)));
        }
        Ok(run)
    }
}
fn refuse(field: &str) -> Error {
    Error::Unsupported {
        requirements: vec![format!("snapshot field outside Stride admission: {field}")],
    }
}
