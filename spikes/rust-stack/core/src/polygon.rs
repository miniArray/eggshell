//! Closed integer polygon contact. Concavity and touching edges are preserved.
use crate::Position;

fn cross(a: Position, b: Position, p: Position) -> i64 {
    b.x.wrapping_sub(a.x)
        .wrapping_mul(p.y.wrapping_sub(a.y))
        .wrapping_sub(b.y.wrapping_sub(a.y).wrapping_mul(p.x.wrapping_sub(a.x)))
}
pub fn contains(points: &[Position], p: Position) -> bool {
    let mut inside = false;
    for index in 0..points.len() {
        let a = points[index];
        let b = points[(index + 1) % points.len()];
        let c = cross(a, b, p);
        if c == 0
            && a.x.min(b.x) <= p.x
            && p.x <= a.x.max(b.x)
            && a.y.min(b.y) <= p.y
            && p.y <= a.y.max(b.y)
        {
            return true;
        }
        if (a.y > p.y) != (b.y > p.y) && (c > 0) == (b.y > a.y) {
            inside = !inside;
        }
    }
    inside
}
pub fn segments_meet(a: Position, b: Position, c: Position, d: Position) -> bool {
    if a.x.max(b.x) < c.x.min(d.x)
        || c.x.max(d.x) < a.x.min(b.x)
        || a.y.max(b.y) < c.y.min(d.y)
        || c.y.max(d.y) < a.y.min(b.y)
    {
        return false;
    }
    let same_side = |a: i64, b: i64| a > 0 && b > 0 || a < 0 && b < 0;
    !same_side(cross(a, b, c), cross(a, b, d)) && !same_side(cross(c, d, a), cross(c, d, b))
}
pub fn overlaps_box(points: &[Position], bounds: [i64; 4]) -> bool {
    let [left, top, right, bottom] = bounds;
    if contains(points, Position { x: left, y: top }) {
        return true;
    }
    let corners = [
        Position { x: left, y: top },
        Position { x: right, y: top },
        Position {
            x: right,
            y: bottom,
        },
        Position { x: left, y: bottom },
    ];
    for i in 0..points.len() {
        let a = points[i];
        let b = points[(i + 1) % points.len()];
        if left <= a.x && a.x <= right && top <= a.y && a.y <= bottom {
            return true;
        }
        for j in 0..4 {
            if segments_meet(a, b, corners[j], corners[(j + 1) % 4]) {
                return true;
            }
        }
    }
    false
}
pub fn overlaps_polygon(a: &[Position], b: &[Position]) -> bool {
    if a.is_empty() || b.is_empty() {
        return false;
    }
    if contains(a, b[0]) || contains(b, a[0]) {
        return true;
    }
    for i in 0..a.len() {
        for j in 0..b.len() {
            if segments_meet(a[i], a[(i + 1) % a.len()], b[j], b[(j + 1) % b.len()]) {
                return true;
            }
        }
    }
    false
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn concave_cutout_is_not_a_bounding_box_and_edges_count() {
        let l = [
            Position { x: 0, y: 0 },
            Position { x: 4, y: 0 },
            Position { x: 4, y: 2 },
            Position { x: 2, y: 2 },
            Position { x: 2, y: 4 },
            Position { x: 0, y: 4 },
        ];
        assert!(!overlaps_box(&l, [3, 3, 4, 4]));
        assert!(overlaps_box(&l, [2, 3, 3, 4]));
        assert!(overlaps_box(&l, [1, 1, 1, 1]));
        assert!(!overlaps_box(&[], [0, 0, 1, 1]));
        assert!(segments_meet(
            Position { x: 0, y: 0 },
            Position { x: 0, y: 4 },
            Position { x: 0, y: 2 },
            Position { x: 0, y: 5 }
        ));
    }
}
