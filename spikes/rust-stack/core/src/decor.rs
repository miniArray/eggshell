//! Static scenery codes (decor.gd): no step or contact; placement facts only.

/// decor.gd CODES
pub(crate) fn is_decor(code: &str) -> bool {
    let Some(index) = code.strip_prefix('d').and_then(|n| n.parse::<i64>().ok()) else {
        return false;
    };
    code == format!("d{index}")
        && (1..=76).contains(&index)
        && ![5, 6, 7, 8, 22, 23, 25, 26].contains(&index)
}
fn index(code: &str) -> i64 {
    code[1..].parse().unwrap_or(0)
}
/// decor.gd resized: extendable scenery with an E1 height.
pub(crate) fn resized(code: &str) -> bool {
    let i = index(code);
    (14..=23).contains(&i)
        || [27, 28, 75].contains(&i)
        || (31..=54).contains(&i)
        || (56..=67).contains(&i)
}
/// decor.gd frame_count
pub(crate) fn frame_count(code: &str) -> i64 {
    let i = index(code);
    if [1, 2, 22, 23].contains(&i) {
        2
    } else if [3, 4].contains(&i) {
        5
    } else if (5..=13).contains(&i) || [25, 26].contains(&i) {
        4
    } else if (68..=72).contains(&i) {
        7
    } else if [75, 76].contains(&i) {
        6
    } else {
        1
    }
}
/// decor.gd layer_for
pub(crate) fn layer_for(code: &str) -> i64 {
    let i = index(code);
    if (14..=21).contains(&i) || (31..=54).contains(&i) {
        5
    } else if (9..=13).contains(&i) {
        12
    } else if i == 23 {
        6
    } else {
        7
    }
}
