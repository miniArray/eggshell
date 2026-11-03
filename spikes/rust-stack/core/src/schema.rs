//! Complete reference metadata is a serialization boundary, never a step interpreter.
use crate::Error;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::HashSet;

pub const REFERENCE_SOURCE: &str = "297ada9a022d0ddc297dd2d4091c5dccfab4531e";
/// Complete baseline registry, including every unused declaration.
pub const V10_SCHEMA_DIGEST: &str =
    "12034df2601b61728f41efa24c05b3679830af0ba217a41e5c1446441b6052ee";

#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
pub struct Field(pub String, pub i64);
#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
pub struct EntitySchema {
    pub code: String,
    pub fields: Vec<Field>,
    pub dynamic: bool,
    pub enemy: bool,
}
#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Metadata {
    source_sha: String,
    version: u32,
    digest: String,
    digest_input: String,
    level: Vec<Field>,
    player: Vec<Field>,
    common: Vec<Field>,
    entities: Vec<EntitySchema>,
}
#[derive(Clone, Debug)]
pub struct Schema {
    digest: [u8; 32],
    level: Vec<Field>,
    player: Vec<Field>,
    common: Vec<Field>,
    entities: Vec<EntitySchema>,
}
impl Schema {
    pub fn parse(json: &str) -> Result<Self, Error> {
        if json.len() > 4 * 1024 * 1024 {
            return Err(invalid("schema metadata exceeds 4 MiB"));
        }
        let metadata: Metadata =
            serde_json::from_str(json).map_err(|e| invalid(&format!("schema JSON: {e}")))?;
        if metadata.version != 10
            || metadata.source_sha != REFERENCE_SOURCE
            || metadata.digest != V10_SCHEMA_DIGEST
        {
            return Err(invalid("schema version/source"));
        }
        let digest = decode_hash(&metadata.digest)?;
        if hash(metadata.digest_input.as_bytes()) != digest {
            return Err(invalid(
                "schema digest does not match original digest input",
            ));
        }
        let declared: serde_json::Value = serde_json::from_str(&metadata.digest_input)
            .map_err(|e| invalid(&format!("schema digest input: {e}")))?;
        let mut expected = vec![
            serde_json::json!("code-and-id-utf8"),
            fields_json(&metadata.level),
            fields_json(&metadata.player),
            fields_json(&metadata.common),
        ];
        for entity in &metadata.entities {
            expected.push(serde_json::json!([
                entity.code,
                fields_json(&entity.fields)
            ]));
            if entity.fields.len() < metadata.common.len()
                || entity.fields[..metadata.common.len()] != metadata.common
            {
                return Err(invalid("entity schema does not begin with common fields"));
            }
            check_fields(&entity.fields)?;
        }
        if declared != serde_json::Value::Array(expected) {
            return Err(invalid(
                "schema ordered declarations differ from digest input",
            ));
        }
        check_fields(&metadata.level)?;
        check_fields(&metadata.player)?;
        check_fields(&metadata.common)?;
        let mut names = HashSet::new();
        for Field(name, _) in metadata.level.iter().chain(metadata.player.iter()) {
            if !names.insert(name) {
                return Err(invalid("overlapping level/player fields"));
            }
        }
        let mut codes = HashSet::new();
        for entity in &metadata.entities {
            if entity.code.len() > 4096 || !codes.insert(&entity.code) {
                return Err(invalid("duplicate/oversized schema code"));
            }
        }
        Ok(Self {
            digest,
            level: metadata.level,
            player: metadata.player,
            common: metadata.common,
            entities: metadata.entities,
        })
    }
    pub fn digest(&self) -> [u8; 32] {
        self.digest
    }
    pub fn level(&self) -> &[Field] {
        &self.level
    }
    pub fn player(&self) -> &[Field] {
        &self.player
    }
    pub fn common(&self) -> &[Field] {
        &self.common
    }
    pub fn entities(&self) -> &[EntitySchema] {
        &self.entities
    }
    pub fn entity(&self, code: &str) -> Option<&EntitySchema> {
        self.entities.iter().find(|entry| entry.code == code)
    }
    pub fn entity_fields(&self, code: &str) -> &[Field] {
        self.entity(code)
            .map_or(&self.common, |entry| &entry.fields)
    }
}
fn fields_json(fields: &[Field]) -> serde_json::Value {
    serde_json::Value::Array(
        fields
            .iter()
            .map(|Field(name, value)| serde_json::json!([name, value]))
            .collect(),
    )
}
fn check_fields(fields: &[Field]) -> Result<(), Error> {
    let mut seen = HashSet::new();
    for Field(name, _) in fields {
        if name.is_empty() || name.len() > 4096 || !seen.insert(name) {
            return Err(invalid("empty, oversized, or duplicate field"));
        }
    }
    Ok(())
}
pub(crate) fn hash(bytes: &[u8]) -> [u8; 32] {
    Sha256::digest(bytes).into()
}
pub(crate) fn decode_hash(text: &str) -> Result<[u8; 32], Error> {
    if text.len() != 64
        || !text
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err(invalid("expected lowercase SHA-256"));
    }
    let mut result = [0; 32];
    for (index, byte) in result.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&text[index * 2..index * 2 + 2], 16)
            .map_err(|_| invalid("SHA-256"))?;
    }
    Ok(result)
}
pub(crate) fn invalid(context: &str) -> Error {
    Error::InvalidInput {
        context: context.into(),
    }
}
