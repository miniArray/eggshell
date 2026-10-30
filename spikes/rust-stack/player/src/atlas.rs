//! Texture atlas packing. Pure CPU logic; the GLES backend uploads the pages.
//! Each image keeps its own pixels. A one-pixel border repeats the image's
//! edge pixels, so nearest sampling at an image edge reads the same texel as
//! CLAMP_TO_EDGE did on a standalone texture.

pub const PAD: u32 = 1;
pub const PAGE_SIZES: [u32; 3] = [1024, 2048, 4096];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Placement {
    pub page: usize,
    /// Upper-left of the image's own pixels (inside the padding).
    pub x: u32,
    pub y: u32,
}

#[derive(Debug, PartialEq, Eq)]
pub struct Packed {
    pub page_size: u32,
    pub pages: usize,
    /// None: the image is too large for a page and stays a standalone texture.
    pub placements: Vec<Option<Placement>>,
}

fn shelf_pack(sizes: &[[u32; 2]], page: u32) -> (usize, Vec<Option<Placement>>) {
    let mut order: Vec<usize> = (0..sizes.len()).collect();
    order.sort_by_key(|&i| {
        (
            std::cmp::Reverse(sizes[i][1]),
            std::cmp::Reverse(sizes[i][0]),
            i,
        )
    });
    let mut placements = vec![None; sizes.len()];
    let (mut pages, mut x, mut y, mut shelf) = (0usize, 0u32, 0u32, 0u32);
    for i in order {
        let [w, h] = sizes[i];
        let (cw, ch) = (w + 2 * PAD, h + 2 * PAD);
        if w == 0 || h == 0 || cw > page || ch > page {
            continue;
        }
        if pages == 0 {
            pages = 1;
        }
        if x + cw > page {
            x = 0;
            y += shelf;
            shelf = 0;
        }
        if y + ch > page {
            pages += 1;
            x = 0;
            y = 0;
            shelf = 0;
        }
        placements[i] = Some(Placement {
            page: pages - 1,
            x: x + PAD,
            y: y + PAD,
        });
        x += cw;
        shelf = shelf.max(ch);
    }
    (pages, placements)
}

/// Smallest page size that holds every fitting image on one page; otherwise
/// several pages of the largest size allowed by the device limit.
pub fn pack(sizes: &[[u32; 2]], limit: u32) -> Packed {
    let allowed: Vec<u32> = PAGE_SIZES.iter().copied().filter(|&s| s <= limit).collect();
    let largest = *allowed.last().unwrap_or(&limit.min(1024));
    for &size in &allowed {
        let (pages, placements) = shelf_pack(sizes, size);
        let oversized_here = placements
            .iter()
            .zip(sizes)
            .any(|(p, s)| p.is_none() && s[0] + 2 * PAD <= largest && s[1] + 2 * PAD <= largest);
        if pages <= 1 && !oversized_here {
            return Packed {
                page_size: size,
                pages,
                placements,
            };
        }
    }
    let (pages, placements) = shelf_pack(sizes, largest);
    Packed {
        page_size: largest,
        pages,
        placements,
    }
}

/// RGBA pixels of one page. Unused space is transparent black.
pub fn compose(
    packed: &Packed,
    page: usize,
    images: &[(u32, u32, &[u8])],
) -> Result<Vec<u8>, String> {
    let size = packed.page_size as usize;
    let mut out = vec![0u8; size * size * 4];
    for (index, placement) in packed.placements.iter().enumerate() {
        let Some(p) = placement else { continue };
        if p.page != page {
            continue;
        }
        let (w, h, rgba) = images[index];
        if rgba.len() != w as usize * h as usize * 4 {
            return Err("atlas image byte length mismatch".into());
        }
        let pad = PAD as i64;
        for dy in -pad..h as i64 + pad {
            let sy = dy.clamp(0, h as i64 - 1) as usize;
            let ty = (p.y as i64 + dy) as usize;
            for dx in -pad..w as i64 + pad {
                let sx = dx.clamp(0, w as i64 - 1) as usize;
                let tx = (p.x as i64 + dx) as usize;
                let s = (sy * w as usize + sx) * 4;
                let t = (ty * size + tx) * 4;
                out[t..t + 4].copy_from_slice(&rgba[s..s + 4]);
            }
        }
    }
    Ok(out)
}

/// Map a coordinate normalized to the image into one normalized to the page.
pub fn remap(uv: f32, offset: u32, extent: u32, page: u32) -> f32 {
    ((offset as f64 + uv as f64 * extent as f64) / page as f64) as f32
}

/// Smallest distance, in texels, that a pixel centre's sample may lie from a
/// texel edge before the atlas is not used for that quad. Both the standalone
/// texture and the atlas page resolve a sample this far from an edge to the
/// same texel: f32 UV error on a 4096 page is about 2.4e-4 texel, and GPU
/// sampler subtexel precision is at least 1/256 texel.
pub const EDGE_MARGIN: f64 = 1.0 / 64.0;

/// True when every pixel centre this quad covers samples at least
/// EDGE_MARGIN texel from a texel edge, inside the image. Only axis-aligned
/// rectangles (any scale, flips and transposes allowed) qualify; others, and
/// samples that land on edges (text at half pixels), keep the standalone texture.
pub fn texel_safe(corners: &[[f32; 2]; 4], uv: &[[f32; 2]; 4], extent: [u32; 2]) -> bool {
    let size = [extent[0] as f64, extent[1] as f64];
    let s = |i: usize| [corners[i][0] as f64, corners[i][1] as f64];
    let t = |i: usize| [uv[i][0] as f64 * size[0], uv[i][1] as f64 * size[1]];
    for i in 0..4 {
        let (p, q) = (s(i), t(i));
        if !p.iter().chain(&q).all(|v| v.is_finite()) {
            return false;
        }
        if q[0] < 0.0 || q[1] < 0.0 || q[0] > size[0] || q[1] > size[1] {
            return false;
        }
    }
    // Parallelogram with edges 0->1 and 0->3, in screen and texel space.
    for k in 0..2 {
        if s(2)[k] != s(1)[k] + s(3)[k] - s(0)[k]
            || (t(2)[k] - (t(1)[k] + t(3)[k] - t(0)[k])).abs() > 1e-6
        {
            return false;
        }
    }
    let along = |d: [f64; 2]| match (d[0] != 0.0, d[1] != 0.0) {
        (true, false) => Some(0usize),
        (false, true) => Some(1usize),
        _ => None,
    };
    let mut screen_axes = [0usize; 2];
    for (n, j) in [1usize, 3].into_iter().enumerate() {
        let ds = [s(j)[0] - s(0)[0], s(j)[1] - s(0)[1]];
        let dt = [t(j)[0] - t(0)[0], t(j)[1] - t(0)[1]];
        let (Some(axis), Some(texel_axis)) = (along(ds), along(dt)) else {
            return false;
        };
        screen_axes[n] = axis;
        // Pixel centres n+0.5 inside [a, b) along this screen axis.
        let (a, b) = (s(0)[axis], s(j)[axis]);
        let (ta, tb) = (t(0)[texel_axis], t(j)[texel_axis]);
        let (lo, hi) = if a < b { (a, b) } else { (b, a) };
        let first = (lo - 0.5).ceil();
        if hi - lo > 8192.0 {
            return false;
        }
        let count = ((hi - 0.5 - first).ceil()).max(0.0) as usize;
        let r = (tb - ta) / (b - a);
        let u0 = ta + (first + 0.5 - a) * r;
        // Samples are u0 + n*r. If q*r is (almost) a whole number, their
        // fractional parts repeat every q samples, apart from a drift of
        // n*delta. Check one period and add the worst drift to the margin.
        let (period, drift) = (1..=64usize)
            .find_map(|q| {
                let x = q as f64 * r;
                let delta = (x - x.round()).abs() / q as f64;
                (delta * count as f64 <= EDGE_MARGIN).then_some((q, delta * count as f64))
            })
            .unwrap_or((count, 0.0));
        for n in 0..count.min(period) {
            let u = u0 + n as f64 * r;
            if (u - u.round()).abs() < EDGE_MARGIN + drift {
                return false;
            }
        }
    }
    screen_axes[0] != screen_axes[1]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn overlaps(a: (u32, u32, u32, u32), b: (u32, u32, u32, u32)) -> bool {
        a.0 < b.0 + b.2 && b.0 < a.0 + a.2 && a.1 < b.1 + b.3 && b.1 < a.1 + a.3
    }

    #[test]
    fn padded_cells_never_overlap_and_stay_inside_the_page() {
        let sizes: Vec<[u32; 2]> = (0..500u32)
            .map(|i| [1 + (i * 37) % 200, 1 + (i * 53) % 150])
            .collect();
        let packed = pack(&sizes, 16384);
        let cells: Vec<_> = packed
            .placements
            .iter()
            .zip(&sizes)
            .map(|(p, s)| {
                let p = p.expect("all fit");
                (
                    p.page,
                    (p.x - PAD, p.y - PAD, s[0] + 2 * PAD, s[1] + 2 * PAD),
                )
            })
            .collect();
        for (i, a) in cells.iter().enumerate() {
            assert!(a.1.0 + a.1.2 <= packed.page_size && a.1.1 + a.1.3 <= packed.page_size);
            for b in &cells[i + 1..] {
                assert!(a.0 != b.0 || !overlaps(a.1, b.1));
            }
        }
    }

    #[test]
    fn oversized_images_stay_standalone() {
        let packed = pack(&[[5000, 10], [10, 10]], 16384);
        assert_eq!(packed.placements[0], None);
        assert!(packed.placements[1].is_some());
        assert_eq!(packed.pages, 1);
        assert_eq!(packed.page_size, 1024);
    }

    #[test]
    fn many_images_use_several_pages_of_the_largest_size() {
        let sizes = vec![[1000u32, 1000u32]; 40];
        let packed = pack(&sizes, 16384);
        assert_eq!(packed.page_size, 4096);
        assert_eq!(packed.pages, 3);
        assert!(packed.placements.iter().all(Option::is_some));
    }

    #[test]
    fn composed_page_holds_exact_pixels_and_clamped_border() {
        let a: Vec<u8> = (0..2 * 2 * 4).map(|v| v as u8 + 1).collect();
        let b: Vec<u8> = vec![200; 3 * 4];
        let sizes = [[2, 2], [3, 1]];
        let packed = pack(&sizes, 16384);
        let page = compose(&packed, 0, &[(2, 2, &a), (3, 1, &b)]).unwrap();
        let size = packed.page_size as usize;
        let at = |x: usize, y: usize| page[(y * size + x) * 4..(y * size + x) * 4 + 4].to_vec();
        let p = packed.placements[0].unwrap();
        let (x, y) = (p.x as usize, p.y as usize);
        for j in 0..2 {
            for i in 0..2 {
                assert_eq!(
                    at(x + i, y + j),
                    a[(j * 2 + i) * 4..(j * 2 + i) * 4 + 4].to_vec()
                );
            }
        }
        // Border repeats the nearest edge texel, including corners.
        assert_eq!(at(x - 1, y - 1), a[0..4].to_vec());
        assert_eq!(at(x + 2, y + 1), a[12..16].to_vec());
        assert_eq!(at(x - 1, y + 1), a[8..12].to_vec());
    }

    /// Every pixel centre, one by one: the definition texel_safe must respect.
    fn brute_force_safe(corners: &[[f32; 2]; 4], uv: &[[f32; 2]; 4], extent: [u32; 2]) -> bool {
        let (x0, x1) = (corners[0][0] as f64, corners[1][0] as f64);
        let (y0, y1) = (corners[0][1] as f64, corners[3][1] as f64);
        let (u0, u1) = (
            uv[0][0] as f64 * extent[0] as f64,
            uv[1][0] as f64 * extent[0] as f64,
        );
        let (v0, v1) = (
            uv[0][1] as f64 * extent[1] as f64,
            uv[3][1] as f64 * extent[1] as f64,
        );
        let axis = |a: f64, b: f64, ta: f64, tb: f64| {
            let (lo, hi) = if a < b { (a, b) } else { (b, a) };
            let mut c = (lo - 0.5).ceil();
            while c + 0.5 < hi {
                let u = ta + (c + 0.5 - a) / (b - a) * (tb - ta);
                if (u - u.round()).abs() < EDGE_MARGIN {
                    return false;
                }
                c += 1.0;
            }
            true
        };
        axis(x0, x1, u0, u1) && axis(y0, y1, v0, v1)
    }
    #[test]
    fn texel_safe_never_accepts_what_the_definition_rejects() {
        let mut x = 0x2545_f491_4f6c_dd1d_u64;
        let mut next = || {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            x
        };
        let (mut agree, mut conservative) = (0, 0);
        for _ in 0..20_000 {
            let r = next();
            let w = [8u32, 16, 24, 32, 48, 64][(r % 6) as usize];
            let scale = [0.5f32, 1.0, 1.5, 2.0, 3.0, 2.0 / 3.0][((r >> 8) % 6) as usize];
            let sub = [0.0f32, 0.25, 0.37, 0.5, 0.0625, 1.0 / 3.0][((r >> 16) % 6) as usize];
            let x0 = ((r >> 24) % 600) as f32 + sub;
            let y0 = ((r >> 34) % 400) as f32 + sub / 2.0;
            let size = w as f32 * scale;
            let corners = [
                [x0, y0],
                [x0 + size, y0],
                [x0 + size, y0 + size],
                [x0, y0 + size],
            ];
            let flip = (r >> 44) % 2 == 1;
            let uv = if flip {
                [[1.0, 0.0], [0.0, 0.0], [0.0, 1.0], [1.0, 1.0]]
            } else {
                [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]
            };
            let fast = texel_safe(&corners, &uv, [w, w]);
            let slow = brute_force_safe(&corners, &uv, [w, w]);
            assert!(!fast || slow, "{corners:?} {uv:?} {w}");
            if fast == slow {
                agree += 1;
            } else {
                conservative += 1;
            }
        }
        assert!(agree > 19_000, "agree={agree} conservative={conservative}");
    }
    #[test]
    fn texel_safe_rejects_samples_near_texel_edges() {
        let uv = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]];
        let rect =
            |x: f32, y: f32, w: f32, h: f32| [[x, y], [x + w, y], [x + w, y + h], [x, y + h]];
        // Whole pixels, whole scale: samples sit at texel centres or quarters.
        assert!(texel_safe(&rect(10.0, 20.0, 16.0, 16.0), &uv, [16, 16]));
        assert!(texel_safe(&rect(10.0, 20.0, 32.0, 48.0), &uv, [16, 16]));
        // Sub-pixel position away from the half pixel: samples 0.13 texel from edges.
        assert!(texel_safe(&rect(10.37, 20.0, 16.0, 16.0), &uv, [16, 16]));
        // Half-pixel position at scale 1: samples land exactly on texel edges.
        assert!(!texel_safe(&rect(10.5, 20.0, 16.0, 16.0), &uv, [16, 16]));
        // Shrinking by 2 puts every sample on a texel edge.
        assert!(!texel_safe(&rect(10.0, 20.0, 8.0, 8.0), &uv, [16, 16]));
        // Fractional scale 1.5: some samples land on edges.
        assert!(!texel_safe(&rect(10.0, 20.0, 24.0, 16.0), &uv, [16, 16]));
        // Flipped and transposed UVs stay safe.
        let flipped = [[1.0, 0.0], [0.0, 0.0], [0.0, 1.0], [1.0, 1.0]];
        assert!(texel_safe(&rect(0.0, 0.0, 16.0, 16.0), &flipped, [16, 16]));
        let transposed = [[0.0, 0.0], [0.0, 1.0], [1.0, 1.0], [1.0, 0.0]];
        assert!(texel_safe(
            &rect(0.0, 0.0, 32.0, 16.0),
            &transposed,
            [16, 32]
        ));
        // Rotation and UV outside the image: never.
        let rotated = [[8.0, 0.0], [16.0, 8.0], [8.0, 16.0], [0.0, 8.0]];
        assert!(!texel_safe(&rotated, &uv, [16, 16]));
        let outside = [[0.0, 0.0], [2.0, 0.0], [2.0, 1.0], [0.0, 1.0]];
        assert!(!texel_safe(&rect(0.0, 0.0, 32.0, 16.0), &outside, [16, 16]));
        // f32 fractions of a 224-texel tileset, as the scene builder emits them.
        let (a, b) = ((64.0f64 / 224.0) as f32, (96.0f64 / 224.0) as f32);
        let (c, d) = ((128.0f64 / 224.0) as f32, (144.0f64 / 224.0) as f32);
        let odd = [[a, c], [b, c], [b, d], [a, d]];
        assert!(texel_safe(&rect(128.0, -2.0, 32.0, 16.0), &odd, [224, 224]));
    }
    #[test]
    fn remap_keeps_texel_centres_on_the_same_texel() {
        let (offset, extent, page) = (777u32, 48u32, 4096u32);
        for texel in 0..extent {
            for sub in [0.125f32, 0.25, 0.5, 0.75, 0.875] {
                let uv = (texel as f32 + sub) / extent as f32;
                let mapped = remap(uv, offset, extent, page) * page as f32;
                assert_eq!(mapped.floor() as u32, offset + texel);
            }
        }
        assert_eq!(
            remap(0.0, offset, extent, page) * page as f32,
            offset as f32
        );
        assert_eq!(
            remap(1.0, offset, extent, page) * page as f32,
            (offset + extent) as f32
        );
    }
}
