//! Private presentation assets only. Nothing here constructs or changes gameplay.
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

pub struct Pack {
    pub root: PathBuf,
    pub manifest: Value,
    pub drawing: Value,
    pub density: u32,
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
        Ok(Self {
            root: root.to_owned(),
            manifest,
            drawing,
            density,
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
    fn digest_known() {
        assert_eq!(
            hash(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }
}
