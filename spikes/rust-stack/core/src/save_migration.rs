//! Deterministic v10 -> v11 migration. Missing creation history cannot be recovered.
use crate::{
    schema::{Field, Schema},
    wire::{WireCollection, WireEntity, WireSnapshot},
    Error, PreparedPlacement, World,
};
use std::collections::HashMap;

#[derive(Default)]
pub(crate) struct Report {
    birth_rows: usize,
    flyer_phases: usize,
    soft_knockbacks: usize,
    squash_registrations: usize,
    remapped_placed_rows: usize,
}
impl Report {
    pub fn print(&self) {
        println!(
            "SAVE_MIGRATED from=10 to=11 inferred_birth_rows={} inferred_flyer_phases={} inferred_soft_knockbacks={} inferred_squash_registrations={} remapped_placed_rows={}",
            self.birth_rows, self.flyer_phases, self.soft_knockbacks,
            self.squash_registrations, self.remapped_placed_rows
        );
    }
}
fn refuse(reason: &str) -> Error {
    Error::Unsupported {
        requirements: vec![format!("v10 save migration: {reason}")],
    }
}
fn get(values: &[i64], fields: &[Field], name: &str) -> Option<i64> {
    fields.iter().position(|f| f.0 == name).map(|i| values[i])
}
fn set(values: &mut [i64], fields: &[Field], name: &str, value: i64) -> Result<(), Error> {
    let index = fields
        .iter()
        .position(|f| f.0 == name)
        .ok_or_else(|| refuse(&format!("missing field {name}")))?;
    values[index] = value;
    Ok(())
}
fn translate(values: &[i64], old: &[Field], new: &[Field]) -> Result<Vec<i64>, Error> {
    for field in old {
        if !new.iter().any(|f| f.0 == field.0) {
            return Err(refuse(&format!("no v11 equivalent for {}", field.0)));
        }
    }
    Ok(new
        .iter()
        .map(|Field(name, default)| get(values, old, name).unwrap_or(*default))
        .collect())
}
fn remap(values: &mut [i64], fields: &[Field], name: &str, tokens: &HashMap<i64, i64>) {
    if let Some(index) = fields.iter().position(|f| f.0 == name) {
        if let Some(value) = tokens.get(&values[index]) {
            values[index] = *value;
        }
    }
}

pub(crate) fn migrate(
    mut wire: WireSnapshot,
    world: &World,
    old: &Schema,
    new: &Schema,
) -> Result<(WireSnapshot, Report), Error> {
    let mut report = Report::default();
    let placed = world.maps[0].placements.len();
    if wire.entities.len() < placed {
        return Err(refuse("placed row count"));
    }
    let mut births = HashMap::new();
    let mut squashes = HashMap::new();
    for row in &wire.entities {
        if new
            .entity_fields(&row.code)
            .iter()
            .any(|f| f.0 == "birth_serial")
        {
            report.birth_rows += 1;
            births.insert(row.id.clone(), report.birth_rows as i64);
        }
        if row.code == "e24" && get(&row.values, old.entity_fields(&row.code), "mode") == Some(3) {
            report.squash_registrations += 1;
            squashes.insert(row.id.clone(), report.squash_registrations as i64);
        }
    }
    let mut tokens = HashMap::new();
    let mut bridges = HashMap::new();
    let mut old_bridge = 0;
    let mut ordered: Vec<Option<WireEntity>> = vec![None; placed];
    let sources: HashMap<_, _> = world.maps[0]
        .placements
        .iter()
        .enumerate()
        .map(|(i, p)| (p.id.as_str(), i))
        .collect();
    for (old_index, row) in wire.entities.drain(..placed).enumerate() {
        let index = *sources
            .get(row.id.as_str())
            .ok_or_else(|| refuse("placed identity"))?;
        if world.maps[0].placements[index].code != row.code || ordered[index].is_some() {
            return Err(refuse("placed code/identity"));
        }
        tokens.insert(old_index as i64 + 1, index as i64 + 1);
        report.remapped_placed_rows += usize::from(old_index != index);
        if let PreparedPlacement::Bridge { geometry_index } =
            world.maps[0].placements[index].prepared
        {
            old_bridge += 1;
            bridges.insert(old_bridge, geometry_index as i64 + 1);
        }
        ordered[index] = Some(row);
    }
    let mut entities = ordered
        .into_iter()
        .map(|row| row.ok_or_else(|| refuse("placed identity gap")))
        .collect::<Result<Vec<_>, _>>()?;
    entities.append(&mut wire.entities);
    wire.entities = entities;
    let mut families = HashMap::new();
    let mut enemy = 0;
    let mut pad = 0;
    for (index, row) in wire.entities.iter_mut().enumerate() {
        let fields = old.entity_fields(&row.code);
        if index < placed {
            set(&mut row.values, fields, "source_index", index as i64)?;
            set(&mut row.values, fields, "token", index as i64 + 1)?;
        }
        if old.entity(&row.code).is_some_and(|e| e.enemy) {
            let previous =
                get(&row.values, fields, "family_index").ok_or_else(|| refuse("enemy family"))?;
            families.insert(previous + 1, enemy + 1);
            set(&mut row.values, fields, "family_index", enemy)?;
            enemy += 1;
        } else if row.code == "o11" {
            set(&mut row.values, fields, "family_index", pad)?;
            pad += 1;
        }
        // These saved fields are entity tokens, not coordinates, serials or family indices.
        for name in [
            "runner_token",
            "origin_shell",
            "target_shell",
            "stem_token",
            "ball_token",
            "owner_token",
            "carrier",
            "needle_token",
            "origin_token",
            "egg_token",
            "shot_token",
        ] {
            remap(&mut row.values, fields, name, &tokens);
        }
        if row.code == "enemy_overlap" {
            for name in ["a", "b"] {
                remap(&mut row.values, fields, name, &tokens);
            }
        }
        if row.code == "enemy_disc" {
            remap(&mut row.values, fields, "owner", &tokens);
        }
    }
    for name in [
        "checkpoint_id",
        "modal_token",
        "egg_origin_0",
        "egg_origin_1",
        "egg_origin_2",
        "egg_origin_3",
        "egg_origin_4",
        "egg_origin_5",
    ] {
        remap(&mut wire.level, old.level(), name, &tokens);
    }
    remap(&mut wire.player, old.player(), "move_held_id", &tokens);
    remap(&mut wire.player, old.player(), "captured_by", &families);
    remap(&mut wire.player, old.player(), "support_bridge", &bridges);
    for slot in 0..4 {
        let prefix = if slot == 0 {
            "move_emit_".into()
        } else {
            format!("move_emit_{slot}_")
        };
        if matches!(
            get(&wire.player, old.player(), &format!("{prefix}kind")),
            Some(2 | 6)
        ) {
            remap(
                &mut wire.player,
                old.player(),
                &format!("{prefix}item"),
                &tokens,
            );
        }
    }
    wire.validate_structure(old)?;
    let frame = get(&wire.level, old.level(), "frame").ok_or_else(|| refuse("frame"))?;
    let bound = get(&wire.player, old.player(), "bubble_bound_ticks").unwrap_or(0);
    wire.level = translate(&wire.level, old.level(), new.level())?;
    wire.player = translate(&wire.player, old.player(), new.player())?;
    set(
        &mut wire.level,
        new.level(),
        "birth_serial",
        report.birth_rows as i64,
    )?;
    set(
        &mut wire.level,
        new.level(),
        "soft_squash_batch",
        i64::from(!squashes.is_empty()),
    )?;
    set(&mut wire.level, new.level(), "soft_squash_ordinal", 0)?;
    set(
        &mut wire.player,
        new.player(),
        "bubble_collision_disabled",
        i64::from(bound != 0),
    )?;
    for row in &mut wire.entities {
        let old_fields = old.entity_fields(&row.code);
        let fields = new.entity_fields(&row.code);
        row.values = translate(&row.values, old_fields, fields)?;
        row.collections = new
            .entity_collections(&row.code)
            .iter()
            .map(|_| WireCollection { rows: Vec::new() })
            .collect();
        if let Some(serial) = births.get(&row.id) {
            let runtime = get(&row.values, fields, "source_index") == Some(-1);
            set(&mut row.values, fields, "birth_frame", 0)?;
            set(&mut row.values, fields, "birth_serial", *serial)?;
            set(
                &mut row.values,
                fields,
                "birth_phase",
                if runtime { 2 } else { 0 },
            )?;
        }
        if row.code == "e2" && get(&row.values, fields, "ground_form") == Some(0) {
            // v10 used the level clock, including the two hidden intro steps.
            set(
                &mut row.values,
                fields,
                "timer",
                (frame.rem_euclid(180) + 152) % 180,
            )?;
            report.flyer_phases += 1;
        }
        if row.code == "e23" && get(&row.values, fields, "mode") == Some(3) {
            let total = get(&row.values, fields, "slide_total").unwrap_or(0);
            if total > 0 {
                let remaining = get(&row.values, fields, "slide_ticks").unwrap_or(0);
                let from = get(&row.values, fields, "slide_from").unwrap_or(0);
                row.collections[0].rows.push(vec![
                    from,
                    remaining,
                    total,
                    if remaining > 0 { 1 } else { 3 },
                ]);
                set(
                    &mut row.values,
                    fields,
                    "knock_active",
                    i64::from(remaining > 0),
                )?;
                for name in ["slide_from", "slide_ticks", "slide_total"] {
                    set(&mut row.values, fields, name, 0)?;
                }
                report.soft_knockbacks += 1;
            }
        }
        if let Some(ordinal) = squashes.get(&row.id) {
            set(&mut row.values, fields, "squash_batch", 1)?;
            set(&mut row.values, fields, "squash_ordinal", *ordinal)?;
        }
    }
    wire.validate_structure(new)?;
    Ok((wire, report))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{BridgeGeometry, SCALE as S};

    #[test]
    fn v10_infers_birth_order_wave_phase_and_legacy_soft_tween() {
        let level = r#"{"version":"s3.8","name":"migration","desc":"","author":"test","startpoint":{"map":1,"X":128,"Y":128},"maps":{"map1":{"width":2048,"height":1024,"objects":{"small":{"A":"e23","X":300,"Y":200},"fly":{"A":"e2","X":400,"Y":200},"big":{"A":"e24","X":600,"Y":200}}}}}"#;
        let world =
            World::compile(level, include_str!("../../../../data/collision_table.json")).unwrap();
        let old = Schema::legacy().unwrap();
        let new = Schema::current().unwrap();
        let mut wire = WireSnapshot {
            identity: world.identity,
            level: old.level().iter().map(|f| f.1).collect(),
            player: old.player().iter().map(|f| f.1).collect(),
            entities: Vec::new(),
        };
        set(&mut wire.level, old.level(), "map_index", 1).unwrap();
        set(&mut wire.level, old.level(), "frame", 200).unwrap();
        set(&mut wire.level, old.level(), "dynamic_serial", 1).unwrap();
        for (index, (id, code)) in [("small", "e23"), ("fly", "e2"), ("big", "e24")]
            .into_iter()
            .enumerate()
        {
            let fields = old.entity_fields(code);
            let mut values = fields.iter().map(|f| f.1).collect::<Vec<_>>();
            for (name, value) in [
                ("source_index", index as i64),
                ("token", index as i64 + 1),
                ("map_index", 1),
                ("facing", -1),
                ("status", 1),
                ("family_index", index as i64),
            ] {
                set(&mut values, fields, name, value).unwrap();
            }
            wire.entities.push(WireEntity {
                code: code.into(),
                id: id.into(),
                values,
                collections: Vec::new(),
            });
        }
        let fields = old.entity_fields("e23");
        for (name, value) in [
            ("mode", 3),
            ("slide_from", 448 * 60),
            ("slide_ticks", 17),
            ("slide_total", 60),
            ("vx", 8064),
        ] {
            set(&mut wire.entities[0].values, fields, name, value).unwrap();
        }
        set(
            &mut wire.entities[2].values,
            old.entity_fields("e24"),
            "mode",
            3,
        )
        .unwrap();
        set(
            &mut wire.entities[2].values,
            old.entity_fields("e24"),
            "timer",
            7,
        )
        .unwrap();
        wire.validate_structure(&old).unwrap();
        let (wire, report) = migrate(wire, &world, &old, &new).unwrap();
        assert_eq!(report.birth_rows, 2);
        assert_eq!(report.flyer_phases, 1);
        assert_eq!(report.soft_knockbacks, 1);
        assert_eq!(report.squash_registrations, 1);
        let small = &wire.entities[0];
        let fly = &wire.entities[1];
        assert_eq!(
            get(&small.values, new.entity_fields("e23"), "birth_serial"),
            Some(1)
        );
        assert_eq!(
            get(&fly.values, new.entity_fields("e2"), "birth_serial"),
            Some(2)
        );
        assert_eq!(
            get(&fly.values, new.entity_fields("e2"), "timer"),
            Some(172)
        );
        assert_eq!(
            get(&small.values, new.entity_fields("e23"), "vx"),
            Some(8064)
        );
        assert_eq!(
            get(&small.values, new.entity_fields("e23"), "knock_active"),
            Some(1)
        );
        assert_eq!(small.collections[0].rows, [vec![448 * 60, 17, 60, 1]]);
        for name in ["slide_from", "slide_ticks", "slide_total"] {
            assert_eq!(get(&small.values, new.entity_fields("e23"), name), Some(0));
        }
        assert_eq!(
            get(
                &wire.entities[2].values,
                new.entity_fields("e24"),
                "squash_batch"
            ),
            Some(1)
        );
        assert_eq!(
            get(
                &wire.entities[2].values,
                new.entity_fields("e24"),
                "squash_ordinal"
            ),
            Some(1)
        );
    }

    #[test]
    fn v10_editor_key_order_migrates_tokens_families_bridges_and_request_items() {
        // Wire-boundary coverage, not a claim that these contacts occurred in gameplay.
        let level = r#"{"version":"s3.8","name":"migration","desc":"","author":"test","startpoint":{"map":1,"X":128,"Y":128},"maps":{"map1":{"width":2048,"height":1024,"objects":{"named":{"A":"e6","X":300,"Y":200},"2":{"A":"e1","X":400,"Y":200},"3":{"A":"p1","X":700,"Y":300,"E1":"128"},"1":{"A":"o7","X":200,"Y":200},"0":{"A":"p1","X":500,"Y":300,"E1":"128"}}}}}"#;
        let mut world =
            World::compile(level, include_str!("../../../../data/collision_table.json")).unwrap();
        let order = ["0", "1", "2", "3", "named"];
        world.maps[0]
            .placements
            .sort_by_key(|p| order.iter().position(|id| *id == p.id).unwrap());
        let map = &mut world.maps[0];
        map.bridges.clear();
        for placement in &mut map.placements {
            if placement.code == "p1" {
                placement.prepared = PreparedPlacement::Bridge {
                    geometry_index: map.bridges.len(),
                };
                map.bridges.push(BridgeGeometry {
                    left: placement.position.x - 64 * S,
                    right: placement.position.x + 64 * S,
                    top: placement.position.y - 16 * S,
                });
            }
        }
        let old = Schema::legacy().unwrap();
        let new = Schema::current().unwrap();
        let mut wire = WireSnapshot {
            identity: world.identity,
            level: old.level().iter().map(|f| f.1).collect(),
            player: old.player().iter().map(|f| f.1).collect(),
            entities: Vec::new(),
        };
        set(&mut wire.level, old.level(), "map_index", 1).unwrap();
        set(&mut wire.level, old.level(), "dynamic_serial", 1).unwrap();
        for (index, (id, code)) in [
            ("named", "e6"),
            ("2", "e1"),
            ("3", "p1"),
            ("1", "o7"),
            ("0", "p1"),
        ]
        .into_iter()
        .enumerate()
        {
            let fields = old.entity_fields(code);
            let mut values = fields.iter().map(|f| f.1).collect::<Vec<_>>();
            for (name, value) in [
                ("source_index", index as i64),
                ("token", index as i64 + 1),
                ("map_index", 1),
                ("facing", -1),
                ("status", 1),
                ("family_index", i64::from(code == "e1")),
            ] {
                set(&mut values, fields, name, value).unwrap();
            }
            wire.entities.push(WireEntity {
                code: code.into(),
                id: id.into(),
                values,
                collections: Vec::new(),
            });
        }
        set(
            &mut wire.entities[0].values,
            old.entity_fields("e6"),
            "runner_token",
            2,
        )
        .unwrap();
        set(
            &mut wire.entities[3].values,
            old.entity_fields("o7"),
            "origin_token",
            1,
        )
        .unwrap();
        set(&mut wire.level, old.level(), "egg_origin_0", 1).unwrap();
        set(&mut wire.player, old.player(), "move_held_id", 1).unwrap();
        set(&mut wire.player, old.player(), "captured_by", 2).unwrap();
        set(&mut wire.player, old.player(), "support_bridge", 1).unwrap();
        set(&mut wire.player, old.player(), "move_emit_kind", 2).unwrap();
        set(&mut wire.player, old.player(), "move_emit_item", 1).unwrap();
        set(&mut wire.player, old.player(), "move_emit_1_kind", 1).unwrap();
        set(&mut wire.player, old.player(), "move_emit_1_item", 1).unwrap();
        wire.validate_structure(&old).unwrap();
        let (migrated, report) = migrate(wire, &world, &old, &new).unwrap();
        assert_eq!(
            migrated
                .entities
                .iter()
                .map(|e| e.id.as_str())
                .collect::<Vec<_>>(),
            order
        );
        assert_eq!(report.remapped_placed_rows, 5);
        assert_eq!(get(&migrated.player, new.player(), "move_held_id"), Some(5));
        assert_eq!(get(&migrated.player, new.player(), "captured_by"), Some(1));
        assert_eq!(
            get(&migrated.player, new.player(), "support_bridge"),
            Some(2)
        );
        assert_eq!(
            get(&migrated.player, new.player(), "move_emit_item"),
            Some(5)
        );
        assert_eq!(
            get(&migrated.player, new.player(), "move_emit_1_item"),
            Some(1)
        );
        assert_eq!(get(&migrated.level, new.level(), "egg_origin_0"), Some(5));
        assert_eq!(
            get(
                &migrated.entities[4].values,
                new.entity_fields("e6"),
                "runner_token"
            ),
            Some(3)
        );
        assert_eq!(
            get(
                &migrated.entities[1].values,
                new.entity_fields("o7"),
                "origin_token"
            ),
            Some(5)
        );
        assert_eq!(
            get(
                &migrated.entities[4].values,
                new.entity_fields("e6"),
                "family_index"
            ),
            Some(1)
        );
    }
}
