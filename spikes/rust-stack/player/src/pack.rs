//! Private presentation assets only. Nothing here creates or changes gameplay.
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::Cursor,
    path::{Component, Path, PathBuf},
};

pub const MANIFEST_SHA: &str = "814404aae5ec7e18591c5f56be292893f388150d9917dbd4d6314f3f1f624416";
pub const DRAWING_SHA: &str = "0d88f6f1af84c030c9a25315228169550afbc38c620c5f40623ae8d3e11a5f74";
pub const INVENTORY_SHA: &str = "06f5454b080a43776cc02710411cb8347bf905de6b522b0af254e164be2f8164";

pub fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
pub fn safe_file(root: &Path, file: &str) -> Result<PathBuf, String> {
    if file.is_empty()
        || file.contains([':', '\\'])
        || Path::new(file)
            .components()
            .any(|c| !matches!(c, Component::Normal(_)))
    {
        return Err(format!("unsafe asset path: {file}"));
    }
    let root = root.canonicalize().map_err(|e| e.to_string())?;
    let path = root.join(file).canonicalize().map_err(|e| e.to_string())?;
    if !path.starts_with(root) {
        return Err(format!("asset escapes pack: {file}"));
    }
    Ok(path)
}

/// File name of the optional role map in a pack folder.
pub const ROLES_FILE: &str = "roles.json";
/// Environment variable that names a role map outside the pack folder. It is read only
/// when the pack folder has no `roles.json`.
pub const ROLES_ENV: &str = "EGGSHELL_PACK_ROLES";

/// Neutral drawing roles (for example `tongue_left` or `stilt_feet`) mapped to the
/// `source_type` names of the pack's own visuals. The pack side supplies this map, so the
/// player never names a pack's visuals itself. A missing map or role means the pack has
/// no art for that role: the scene records a visual omission and draws without it.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Roles(std::collections::BTreeMap<String, String>);
impl Roles {
    /// Parses `{"version": 1, "roles": {"<role>": "<source type>", ...}}`.
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        let value: Value =
            serde_json::from_slice(bytes).map_err(|e| format!("pack role map: {e}"))?;
        if value.get("version").and_then(Value::as_u64) != Some(1) {
            return Err("pack role map: unsupported version (expected 1)".into());
        }
        let roles = value
            .get("roles")
            .and_then(Value::as_object)
            .ok_or("pack role map: `roles` must be an object")?;
        let mut map = std::collections::BTreeMap::new();
        for (role, source) in roles {
            let source = source
                .as_str()
                .filter(|s| !s.is_empty())
                .ok_or_else(|| format!("pack role map: role {role} needs a non-empty name"))?;
            map.insert(role.clone(), source.to_owned());
        }
        Ok(Self(map))
    }
    /// The role map for a pack folder: `<root>/roles.json`, else the file that
    /// `EGGSHELL_PACK_ROLES` names, else an empty map. A map that exists but does not
    /// parse is an error.
    pub fn find(root: &Path) -> Result<Self, String> {
        Self::find_with(root, std::env::var_os(ROLES_ENV))
    }
    fn find_with(root: &Path, fallback: Option<std::ffi::OsString>) -> Result<Self, String> {
        let path = match root.join(ROLES_FILE) {
            path if path.is_file() => path,
            _ => match fallback {
                Some(path) if !path.is_empty() => PathBuf::from(path),
                _ => return Ok(Self::default()),
            },
        };
        let bytes = fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        Self::parse(&bytes)
    }
    /// The pack visual `source_type` for a role, when the map has one.
    pub fn source(&self, role: &str) -> Option<&str> {
        self.0.get(role).map(String::as_str)
    }
}

pub struct Pack {
    pub root: PathBuf,
    pub manifest: Value,
    pub drawing: Value,
    pub density: u32,
    pub roles: Roles,
    file_hashes: std::collections::BTreeMap<String, String>,
}
impl Pack {
    pub fn open(root: &Path, inventory: &Path) -> Result<Self, String> {
        let file_hashes: std::collections::BTreeMap<String, String> =
            serde_json::from_slice(&fs::read(inventory).map_err(|e| e.to_string())?)
                .map_err(|e| e.to_string())?;
        if file_hashes.len() != 3028
            || hash(&serde_json::to_vec(&file_hashes).map_err(|e| e.to_string())?) != INVENTORY_SHA
        {
            return Err("private pack file inventory digest/count mismatch".into());
        }
        let bytes = fs::read(safe_file(root, "manifest.json")?).map_err(|e| e.to_string())?;
        if hash(&bytes) != MANIFEST_SHA {
            return Err("original pack manifest hash mismatch".into());
        }
        let manifest: Value = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
        let bytes = fs::read(safe_file(root, "drawing_facts.json")?).map_err(|e| e.to_string())?;
        if hash(&bytes) != DRAWING_SHA {
            return Err("original pack drawing facts hash mismatch".into());
        }
        let drawing = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
        let density = manifest.get("density").and_then(Value::as_u64).unwrap_or(1) as u32;
        if !(1..=4).contains(&density) {
            return Err("unsupported pack density".into());
        }
        let roles = Roles::find(root)?;
        Ok(Self {
            root: root.to_owned(),
            manifest,
            drawing,
            density,
            roles,
            file_hashes,
        })
    }
    /// The bytes of a pack file whose digest matches the pinned file inventory.
    pub fn verified_bytes(&self, file: &str) -> Result<Vec<u8>, String> {
        let bytes = fs::read(safe_file(&self.root, file)?).map_err(|e| e.to_string())?;
        if self.file_hashes.get(file).map(String::as_str) != Some(hash(&bytes).as_str()) {
            return Err(format!("private asset hash mismatch: {file}"));
        }
        Ok(bytes)
    }
    pub fn png(&self, file: &str) -> Result<Image, String> {
        let image = Image::load(&safe_file(&self.root, file)?)?;
        if self.file_hashes.get(file).map(String::as_str) != Some(image.sha256.as_str()) {
            return Err(format!("private asset hash mismatch: {file}"));
        }
        Ok(image)
    }
}
pub struct Image {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
    pub sha256: String,
}
impl Image {
    pub fn load(path: &Path) -> Result<Self, String> {
        let bytes = fs::read(path).map_err(|e| e.to_string())?;
        let sha256 = hash(&bytes);
        let mut decoder = png::Decoder::new(Cursor::new(bytes));
        decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
        let mut reader = decoder.read_info().map_err(|e| e.to_string())?;
        let mut data = vec![0; reader.output_buffer_size()];
        let info = reader.next_frame(&mut data).map_err(|e| e.to_string())?;
        let mut rgba = Vec::with_capacity(info.width as usize * info.height as usize * 4);
        let data = &data[..info.buffer_size()];
        match info.color_type {
            png::ColorType::Rgba => rgba.extend_from_slice(data),
            png::ColorType::Rgb => {
                for p in data.chunks_exact(3) {
                    rgba.extend_from_slice(&[p[0], p[1], p[2], 255]);
                }
            }
            png::ColorType::Grayscale => {
                for &p in data {
                    rgba.extend_from_slice(&[p, p, p, 255]);
                }
            }
            png::ColorType::GrayscaleAlpha => {
                for p in data.chunks_exact(2) {
                    rgba.extend_from_slice(&[p[0], p[0], p[0], p[1]]);
                }
            }
            _ => return Err("PNG expansion left indexed pixels".into()),
        }
        Ok(Self {
            width: info.width,
            height: info.height,
            rgba,
            sha256,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_traversal_before_read() {
        for path in ["../a", "/a", "a/../b", "C:a", "a\\b", ""] {
            assert!(safe_file(Path::new("."), path).is_err());
        }
    }
    #[test]
    fn role_map_parses_and_rejects_bad_shapes() {
        let roles =
            Roles::parse(br#"{"version":1,"roles":{"tongue_up":"Up","stilt_top":"Top"}}"#).unwrap();
        assert_eq!(roles.source("tongue_up"), Some("Up"));
        assert_eq!(roles.source("stilt_top"), Some("Top"));
        assert_eq!(roles.source("roll_sprite"), None);
        for bad in [
            &br#"{"roles":{}}"#[..],
            br#"{"version":2,"roles":{}}"#,
            br#"{"version":1}"#,
            br#"{"version":1,"roles":{"tongue_up":3}}"#,
            br#"{"version":1,"roles":{"tongue_up":""}}"#,
            b"not json",
        ] {
            assert!(Roles::parse(bad).is_err());
        }
    }
    #[test]
    fn role_map_comes_from_the_pack_folder_then_the_fallback_file() {
        let root = std::env::temp_dir().join(format!("eggshell-roles-{}", std::process::id()));
        let elsewhere = root.join("elsewhere.json");
        let folder = root.join("pack");
        fs::create_dir_all(&folder).unwrap();
        // No map anywhere: no roles, no error.
        assert_eq!(Roles::find_with(&folder, None).unwrap(), Roles::default());
        assert_eq!(
            Roles::find_with(&folder, Some(Default::default())).unwrap(),
            Roles::default()
        );
        fs::write(
            &elsewhere,
            br#"{"version":1,"roles":{"fire_shot":"Elsewhere"}}"#,
        )
        .unwrap();
        let found = Roles::find_with(&folder, Some(elsewhere.clone().into())).unwrap();
        assert_eq!(found.source("fire_shot"), Some("Elsewhere"));
        // A map in the pack folder wins over the fallback.
        fs::write(
            folder.join(ROLES_FILE),
            br#"{"version":1,"roles":{"fire_shot":"Here"}}"#,
        )
        .unwrap();
        let found = Roles::find_with(&folder, Some(elsewhere.into())).unwrap();
        assert_eq!(found.source("fire_shot"), Some("Here"));
        // A named fallback that is missing, or a bad map, is an error.
        fs::remove_file(folder.join(ROLES_FILE)).unwrap();
        assert!(Roles::find_with(&folder, Some(root.join("missing.json").into())).is_err());
        fs::write(folder.join(ROLES_FILE), b"{}").unwrap();
        assert!(Roles::find_with(&folder, None).is_err());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn digest_known() {
        assert_eq!(
            hash(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }
}

/// Optional visual-only sidecars: `foo.png` -> `foo.normal.png` (RGB tangent
/// normals: +X right, +Y up, +Z out). Sidecars are local spike art, outside the
/// pinned original inventory. Main images still require their original hash.
fn normal_sidecar(root: &Path, file: &str) -> Result<Option<Image>, String> {
    let Some(stem) = file.strip_suffix(".png") else {
        return Ok(None);
    };
    let name = format!("{stem}.normal.png");
    // Validate components even for a missing file; safe_file also rejects escaping symlinks.
    if Path::new(&name)
        .components()
        .any(|c| !matches!(c, Component::Normal(_)))
        || name.contains([':', '\\'])
    {
        return Err("unsafe normal sidecar path".into());
    }
    match fs::symlink_metadata(root.join(&name)) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(format!("normal sidecar: {e}")),
        Ok(_) => Image::load(&safe_file(root, &name)?).map(Some),
    }
}
impl Pack {
    pub fn normal(&self, file: &str, size: [u32; 2]) -> Result<Option<Image>, String> {
        let normal = normal_sidecar(&self.root, file)?;
        if normal.as_ref().is_some_and(|n| [n.width, n.height] != size) {
            return Err(format!("normal sidecar dimensions differ from {file}"));
        }
        Ok(normal)
    }
}
#[cfg(test)]
mod normal_tests {
    use super::*;
    #[test]
    fn optional_normal_sidecar_missing_present_and_unsafe() {
        let root = std::env::temp_dir().join(format!("eggshell-normals-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        assert!(normal_sidecar(&root, "foo.png").unwrap().is_none());
        assert!(normal_sidecar(&root, "../foo.png").is_err());
        let file = fs::File::create(root.join("foo.normal.png")).unwrap();
        let mut png = png::Encoder::new(file, 1, 1);
        png.set_color(png::ColorType::Rgb);
        png.write_header()
            .unwrap()
            .write_image_data(&[128, 128, 255])
            .unwrap();
        let n = normal_sidecar(&root, "foo.png").unwrap().unwrap();
        assert_eq!(n.rgba, [128, 128, 255, 255]);
        let pack = Pack {
            root: root.clone(),
            manifest: Value::Null,
            drawing: Value::Null,
            density: 1,
            roles: Roles::default(),
            file_hashes: Default::default(),
        };
        assert!(pack.normal("foo.png", [2, 1]).is_err());
        assert!(pack.normal("foo.png", [1, 1]).unwrap().is_some());
        fs::write(root.join("bad.normal.png"), b"not a PNG").unwrap();
        assert!(pack.normal("bad.png", [1, 1]).is_err());
        fs::remove_dir_all(root).unwrap();
    }
}
