//! Local presentation preferences. Never part of a core snapshot or replay.
use serde::{Deserialize, Serialize};
use std::{io::Write, path::Path};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct FeelSettings {
    pub shake_enabled: bool,
    pub pound_strength_px: i64,
    pub pound_steps: i64,
    pub hit_strength_px: i64,
    pub hit_steps: i64,
    pub dust_enabled: bool,
    pub dust_amount: i64,
    pub muffle_enabled: bool,
    pub muffle_strength: i64,
    pub sparkle_enabled: bool,
    pub splash_enabled: bool,
    pub goal_music_enabled: bool,
    pub goal_music_strength: i64,
}
impl Default for FeelSettings {
    fn default() -> Self {
        Self {
            shake_enabled: true,
            pound_strength_px: 3,
            pound_steps: 14,
            hit_strength_px: 2,
            hit_steps: 10,
            dust_enabled: true,
            dust_amount: 2,
            muffle_enabled: true,
            muffle_strength: 2,
            sparkle_enabled: true,
            splash_enabled: true,
            goal_music_enabled: true,
            goal_music_strength: 2,
        }
    }
}
impl FeelSettings {
    pub fn clamp(&mut self) {
        self.pound_strength_px = self.pound_strength_px.clamp(0, 8);
        self.hit_strength_px = self.hit_strength_px.clamp(0, 8);
        self.pound_steps = self.pound_steps.clamp(6, 30);
        self.hit_steps = self.hit_steps.clamp(6, 30);
        self.dust_amount = self.dust_amount.clamp(0, 3);
        self.muffle_strength = self.muffle_strength.clamp(0, 3);
        self.goal_music_strength = self.goal_music_strength.clamp(0, 3);
    }
    pub fn load(directory: &Path) -> Self {
        let path = directory.join("feel.json");
        let (mut settings, source) = match std::fs::read(&path) {
            Ok(bytes) => match serde_json::from_slice::<Self>(&bytes) {
                Ok(settings) => (settings, "file"),
                Err(_) => (Self::default(), "defaults-invalid"),
            },
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                (Self::default(), "defaults-missing")
            }
            Err(_) => (Self::default(), "defaults-unreadable"),
        };
        settings.clamp();
        println!("RUST_FEEL_SETTINGS source={source} path={path:?}");
        settings
    }
    pub fn save(&self, directory: &Path) -> Result<(), String> {
        let path = directory.join("feel.json");
        let temporary = directory.join("feel.json.tmp");
        let bytes = serde_json::to_vec_pretty(self).map_err(|e| e.to_string())?;
        let mut f = std::fs::File::create(&temporary).map_err(|e| format!("feel settings: {e}"))?;
        f.write_all(&bytes).map_err(|e| e.to_string())?;
        f.sync_all().map_err(|e| e.to_string())?;
        drop(f);
        std::fs::rename(temporary, path).map_err(|e| e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn old_settings_get_new_defaults_and_goal_strength_is_clamped() {
        let old = r#"{"shake_enabled":false,"pound_strength_px":4,"pound_steps":12,"hit_strength_px":1,"hit_steps":8,"dust_enabled":false,"dust_amount":1,"muffle_enabled":false,"muffle_strength":1}"#;
        let mut s: FeelSettings = serde_json::from_str(old).unwrap();
        assert!(!s.shake_enabled && !s.dust_enabled && !s.muffle_enabled);
        assert!(s.sparkle_enabled && s.splash_enabled && s.goal_music_enabled);
        assert_eq!(s.goal_music_strength, 2);
        for (input, expected) in [(-1, 0), (0, 0), (2, 2), (99, 3)] {
            s.goal_music_strength = input;
            s.clamp();
            assert_eq!(s.goal_music_strength, expected);
        }
    }
    #[test]
    fn load_defaults_invalid_partial_clamped_and_atomic_round_trip() {
        let dir = std::env::temp_dir().join(format!(
            "eggshell-feel-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir(&dir).unwrap();
        assert_eq!(FeelSettings::load(&dir), FeelSettings::default());
        std::fs::write(dir.join("feel.json"), b"invalid").unwrap();
        assert_eq!(FeelSettings::load(&dir), FeelSettings::default());
        std::fs::write(dir.join("feel.json"), br#"{"pound_strength_px":99,"hit_strength_px":-1,"pound_steps":-9,"hit_steps":100,"dust_amount":7,"muffle_strength":-3}"#).unwrap();
        let s = FeelSettings::load(&dir);
        assert_eq!(
            (
                s.pound_strength_px,
                s.hit_strength_px,
                s.pound_steps,
                s.hit_steps,
                s.dust_amount,
                s.muffle_strength
            ),
            (8, 0, 6, 30, 3, 0)
        );
        assert!(s.shake_enabled);
        s.save(&dir).unwrap();
        assert_eq!(FeelSettings::load(&dir), s);
        assert!(!dir.join("feel.json.tmp").exists());
        std::fs::remove_dir_all(dir).unwrap();
    }
}
