//! Literal v10 structural codec for differential inspection only.
//!
//! These indexed scalar arrays are serialization metadata, NOT gameplay state.
//! This module does not implement type/lifetime/movement valid_state hooks and
//! therefore cannot authorize a Session restore or gameplay admission.
use crate::{
    schema::{hash, Field, Schema},
    Error,
};
use std::collections::HashSet;
const MAX_BYTES: usize = 67_108_864;
const MAX_ENTITIES: usize = 100_000;
const MAX_TEXT: usize = 4096;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WireEntity {
    pub code: String,
    pub id: String,
    pub values: Vec<i64>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WireSnapshot {
    pub identity: [u8; 32],
    pub level: Vec<i64>,
    pub player: Vec<i64>,
    pub entities: Vec<WireEntity>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Difference {
    pub scope: String,
    pub field: String,
    pub token: Option<i64>,
    pub expected: String,
    pub actual: String,
}
impl WireSnapshot {
    pub fn decode(bytes: &[u8], identity: [u8; 32], schema: &Schema) -> Result<Self, Error> {
        let minimum = 76 + 8 * (schema.level().len() + schema.player().len()) + 4 + 32;
        if bytes.len() < minimum || bytes.len() > MAX_BYTES {
            return Err(refuse("size/truncation"));
        }
        let end = bytes.len() - 32;
        if hash(&bytes[..end]).as_slice() != &bytes[end..] {
            return Err(refuse("checksum"));
        }
        let mut cursor = Cursor {
            bytes: &bytes[..end],
            at: 0,
        };
        if cursor.take(8)? != b"EGGSTATE" || cursor.u32()? != 10 {
            return Err(refuse("format/version"));
        }
        if cursor.take(32)? != identity {
            return Err(refuse("level identity"));
        }
        if cursor.take(32)? != schema.digest() {
            return Err(refuse("schema digest"));
        }
        let level = cursor.values(schema.level().len())?;
        let player = cursor.values(schema.player().len())?;
        let count = cursor.u32()? as usize;
        // Every entity needs at least two lengths, field count and common values.
        if count > MAX_ENTITIES || count > (end - cursor.at) / (12 + schema.common().len() * 8) {
            return Err(refuse("entity count"));
        }
        let mut entities = Vec::with_capacity(count);
        for _ in 0..count {
            let code = cursor.text()?;
            let id = cursor.text()?;
            let fields = schema.entity_fields(&code);
            if cursor.u32()? as usize != fields.len() {
                return Err(refuse("entity field count"));
            }
            let values = cursor.values(fields.len())?;
            entities.push(WireEntity { code, id, values });
        }
        if cursor.at != end {
            return Err(refuse("trailing bytes/count"));
        }
        let state = Self {
            identity,
            level,
            player,
            entities,
        };
        state.validate_structure(schema)?;
        Ok(state)
    }
    pub fn encode(&self, schema: &Schema) -> Result<Vec<u8>, Error> {
        self.validate_structure(schema)?;
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"EGGSTATE");
        bytes.extend_from_slice(&10u32.to_le_bytes());
        bytes.extend_from_slice(&self.identity);
        bytes.extend_from_slice(&schema.digest());
        for value in self.level.iter().chain(&self.player) {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        bytes.extend_from_slice(&(self.entities.len() as u32).to_le_bytes());
        for entity in &self.entities {
            for text in [&entity.code, &entity.id] {
                bytes.extend_from_slice(&(text.len() as u32).to_le_bytes());
                bytes.extend_from_slice(text.as_bytes());
            }
            bytes.extend_from_slice(&(entity.values.len() as u32).to_le_bytes());
            for value in &entity.values {
                bytes.extend_from_slice(&value.to_le_bytes());
            }
            if bytes.len() > MAX_BYTES - 32 {
                return Err(refuse("oversized output"));
            }
        }
        bytes.extend_from_slice(&hash(&bytes));
        Ok(bytes)
    }
    fn validate_structure(&self, schema: &Schema) -> Result<(), Error> {
        if self.level.len() != schema.level().len()
            || self.player.len() != schema.player().len()
            || self.entities.len() > MAX_ENTITIES
        {
            return Err(refuse("schema/count"));
        }
        let map = required(&self.level, schema.level(), "map_index")?;
        let serial = required(&self.level, schema.level(), "dynamic_serial")?;
        if !(1..=i64::MAX - 1_000_000 + 1).contains(&serial) {
            return Err(refuse("dynamic serial"));
        }
        let mut ids = HashSet::new();
        let mut runtime = false;
        let mut enemies = 0;
        let mut pads = 0;
        for (index, entity) in self.entities.iter().enumerate() {
            let fields = schema.entity_fields(&entity.code);
            if entity.code.len() > MAX_TEXT
                || entity.id.len() > MAX_TEXT
                || !ids.insert(&entity.id)
                || fields.len() != entity.values.len()
            {
                return Err(refuse("entity identity/schema"));
            }
            let read = |name| required(&entity.values, fields, name);
            if read("map_index")? != map {
                return Err(refuse("entity map"));
            }
            for flag in [
                "collected",
                "checkpoint_collected",
                "offscreen",
                "spawn_mode",
                "can_despawn",
                "can_respawn",
            ] {
                if !(0..=1).contains(&read(flag)?) {
                    return Err(refuse("common entity flag"));
                }
            }
            for name in [
                "map_index",
                "family_index",
                "activation_x",
                "activation_y",
                "despawn_radius",
                "respawn_radius",
            ] {
                if read(name)? < 0 {
                    return Err(refuse("common nonnegative field"));
                }
            }
            if ![-1, 1].contains(&read("facing")?) || !(0..=3).contains(&read("status")?) {
                return Err(refuse("common facing/status"));
            }
            let source = read("source_index")?;
            let token = read("token")?;
            if source == -1 {
                runtime = true;
                let number = entity
                    .id
                    .strip_prefix('+')
                    .and_then(|s| s.parse::<i64>().ok())
                    .filter(|n| *n > 0 && n.to_string() == entity.id[1..]);
                let number = number.ok_or_else(|| refuse("dynamic id"))?;
                if number >= serial
                    || number > i64::MAX - 1_000_000
                    || token != 1_000_000 + number
                    || read("can_respawn")? != 0
                    || read("spawn_mode")? != 0
                    || !schema
                        .entity(&entity.code)
                        .is_some_and(|entry| entry.dynamic)
                {
                    return Err(refuse("dynamic row contract"));
                }
            } else if runtime
                || source < 0
                || source as usize != index
                || source >= 999_999
                || token != source + 1
            {
                return Err(refuse("placed prefix/token order"));
            }
            if schema.entity(&entity.code).is_some_and(|entry| entry.enemy) {
                if read("family_index")? != enemies {
                    return Err(refuse("enemy family order"));
                }
                enemies += 1;
            } else if entity.code == "o11" {
                if read("family_index")? != pads {
                    return Err(refuse("pad family order"));
                }
                pads += 1;
            }
        }
        if required(&self.player, schema.player(), "captured_by")? > enemies {
            return Err(refuse("captor family index"));
        }
        Ok(())
    }
    pub fn first_difference(&self, actual: &Self, schema: &Schema) -> Option<Difference> {
        let diff = |scope: &str, field: &str, token, expected: String, actual: String| Difference {
            scope: scope.into(),
            field: field.into(),
            token,
            expected,
            actual,
        };
        if self.identity != actual.identity {
            return Some(diff(
                "header",
                "identity",
                None,
                format!("{:x?}", self.identity),
                format!("{:x?}", actual.identity),
            ));
        }
        for (scope, fields, expected, actual) in [
            ("level", schema.level(), &self.level, &actual.level),
            ("player", schema.player(), &self.player, &actual.player),
        ] {
            for ((Field(name, _), a), b) in fields.iter().zip(expected).zip(actual) {
                if a != b {
                    return Some(diff(scope, name, None, a.to_string(), b.to_string()));
                }
            }
            if expected.len() != actual.len() {
                return Some(diff(
                    scope,
                    "field_count",
                    None,
                    expected.len().to_string(),
                    actual.len().to_string(),
                ));
            }
        }
        for (index, (expected, actual)) in self.entities.iter().zip(&actual.entities).enumerate() {
            let scope = format!("entity[{index}]:{}", expected.id);
            let fields = schema.entity_fields(&expected.code);
            let token = required(&expected.values, fields, "token").ok();
            for (field, a, b) in [
                ("code", &expected.code, &actual.code),
                ("id", &expected.id, &actual.id),
            ] {
                if a != b {
                    return Some(diff(&scope, field, token, a.clone(), b.clone()));
                }
            }
            for ((Field(name, _), a), b) in fields.iter().zip(&expected.values).zip(&actual.values)
            {
                if a != b {
                    return Some(diff(&scope, name, token, a.to_string(), b.to_string()));
                }
            }
            if expected.values.len() != actual.values.len() {
                return Some(diff(
                    &scope,
                    "field_count",
                    token,
                    expected.values.len().to_string(),
                    actual.values.len().to_string(),
                ));
            }
        }
        if self.entities.len() != actual.entities.len() {
            return Some(diff(
                "entities",
                "count",
                None,
                self.entities.len().to_string(),
                actual.entities.len().to_string(),
            ));
        }
        None
    }
}
pub fn required(values: &[i64], fields: &[Field], name: &str) -> Result<i64, Error> {
    fields
        .iter()
        .position(|field| field.0 == name)
        .and_then(|index| values.get(index))
        .copied()
        .ok_or_else(|| refuse(&format!("missing field {name}")))
}
struct Cursor<'a> {
    bytes: &'a [u8],
    at: usize,
}
impl<'a> Cursor<'a> {
    fn take(&mut self, count: usize) -> Result<&'a [u8], Error> {
        let end = self
            .at
            .checked_add(count)
            .filter(|end| *end <= self.bytes.len())
            .ok_or_else(|| refuse("truncation"))?;
        let result = &self.bytes[self.at..end];
        self.at = end;
        Ok(result)
    }
    fn u32(&mut self) -> Result<u32, Error> {
        Ok(u32::from_le_bytes(
            self.take(4)?.try_into().map_err(|_| refuse("u32"))?,
        ))
    }
    fn values(&mut self, count: usize) -> Result<Vec<i64>, Error> {
        let bytes = self.take(
            count
                .checked_mul(8)
                .ok_or_else(|| refuse("field count overflow"))?,
        )?;
        bytes
            .as_chunks::<8>()
            .0
            .iter()
            .map(|chunk| Ok(i64::from_le_bytes(*chunk)))
            .collect()
    }
    fn text(&mut self) -> Result<String, Error> {
        let len = self.u32()? as usize;
        if len > MAX_TEXT {
            return Err(refuse("string size"));
        }
        std::str::from_utf8(self.take(len)?)
            .map(str::to_owned)
            .map_err(|_| refuse("UTF-8"))
    }
}
fn refuse(reason: &str) -> Error {
    Error::Snapshot {
        reason: reason.into(),
    }
}
