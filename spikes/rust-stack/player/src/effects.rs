//! Read-only palette sampling from map_effects.gd. No saved state is changed.
use eggshell_spike_core::PaletteSwap;
use std::sync::LazyLock;
const FROM: [&str; 5] = [
    "240,248,184-128,184,152-112,136,168-128,184,152-128,112,104-112,136,168-128,184,152-128,112,104-112,136,168-128,184,152-128,112,104-112,136,168-128,112,104",
    "248,248,248-156,231,255-115,198,222-156,231,255-90,156,181-115,198,222-156,231,255-90,156,181-115,198,222-156,231,255-90,156,181-115,198,222-90,156,181",
    "255,198,123-239,156,123-189,123,82-239,156,123-115,107,82-189,123,82-255,198,123-115,107,82-189,123,82-255,198,123-115,107,82-189,123,82-115,107,82",
    "248,248,192-224,200,144-160,112,88-224,200,144-104,64,32-160,112,88-224,200,144-104,64,32-160,112,88-224,200,144-104,64,32-160,112,88-224,200,144",
    "200,176,152-144,128,104-96,88,72-144,128,104-24,16,8-96,88,72-144,128,104-24,16,8-96,88,72-144,128,104-24,16,8-96,88,72-144,128,104",
];
const TO: [&str; 5] = [
    "248,248,248-248,248,248-208,232,248-176,232,200-240,224,216-160,184,216-152,208,176-176,160,152-136,160,192-128,184,152-152,136,128-112,136,168-128,112,104",
    "224,248,248-184,248,248-144,240,248-240,248,248-120,200,208-232,248,248-216,248,248-200,248,248-176,248,248-168,240,248-152,232,240-128,208,232-104,168,192",
    "248,248,248-248,248,248-208,232,248-248,192,120-240,224,216-232,152,120-248,192,120-176,160,152-184,120,80-248,192,120-152,136,128-184,120,80-128,112,104",
    "248,248,248-248,248,248-255,255,209-255,246,225-207,188,173-203,156,133-242,226,187-151,116,88-186,136,111-224,200,144-125,87,57-160,112,88-224,200,144",
    "248,248,248-248,248,248-186,182,170-216,206,190-112,99,86-156,150,137-182,167,145-91,74,56-130,123,108-144,128,104-61,44,28-96,88,72-144,128,104",
];
fn table(source: [&str; 5]) -> [[[u8; 3]; 13]; 5] {
    source.map(|s| {
        let values: Vec<_> = s
            .split('-')
            .map(|c| {
                let v: Vec<u8> = c
                    .split(',')
                    .map(|v| v.parse().expect("source palette byte"))
                    .collect();
                v.try_into().expect("source palette RGB")
            })
            .collect();
        values.try_into().expect("source palette length")
    })
}
static TABLE_FROM: LazyLock<[[[u8; 3]; 13]; 5]> = LazyLock::new(|| table(FROM));
static TABLE_TO: LazyLock<[[[u8; 3]; 13]; 5]> = LazyLock::new(|| table(TO));
pub fn shimmer(name: &str, tick: i64) -> Vec<PaletteSwap> {
    let variant = if name == "cave64" {
        Some(0)
    } else {
        name.strip_prefix("cave64_")
            .and_then(|v| v.parse::<usize>().ok())
            .filter(|v| (1..=4).contains(v))
    };
    let Some(v) = variant else {
        return Vec::new();
    };
    if tick < 60 || tick % 60 >= 42 {
        return Vec::new();
    }
    let phase = (tick % 60 / 6) as usize;
    let from = &TABLE_FROM[v];
    let to = &TABLE_TO[v];
    if phase == 6 {
        return vec![if v == 0 {
            PaletteSwap {
                from: TABLE_FROM[0][12],
                to: TABLE_TO[0][12],
            }
        } else if v == 1 {
            PaletteSwap {
                from: TABLE_FROM[1][0],
                to: TABLE_TO[1][0],
            }
        } else {
            PaletteSwap {
                from: [0; 3],
                to: [0; 3],
            }
        }];
    }
    let pairs: &[(usize, usize)] = match phase {
        0 => &[(0, 0)],
        1 => &[(1, 1)],
        2 => &[(2, 2), (3, 3)],
        3 => &[(4, 4), (5, 5), (6, 6)],
        4 => &[(7, 7), (8, 8)],
        5 => &[(10, 10), (11, 12)],
        _ => unreachable!(),
    };
    pairs
        .iter()
        .map(|(a, b)| PaletteSwap {
            from: from[*a],
            to: to[*b],
        })
        .collect()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn source_shimmer_boundaries() {
        assert!(shimmer("cave64", 59).is_empty());
        assert_eq!(shimmer("cave64", 60).len(), 1);
        assert_eq!(shimmer("cave64", 78).len(), 3);
        assert_eq!(shimmer("cave64", 90)[1].to, TABLE_TO[0][12]);
        assert!(shimmer("cave64", 102).is_empty());
        assert!(shimmer("cave32", 60).is_empty());
    }
}
