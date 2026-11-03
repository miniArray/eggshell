//! Matched diagnostic primitives only. No gameplay, private art or timing claim.
use crate::{
    geometry::UNIT_UV,
    gles::{Gles, Quad},
    pack::Image,
};
use sdl2::{event::Event, keyboard::Keycode};
use sha2::{Digest, Sha256};
use std::{
    io::Write,
    path::PathBuf,
    time::{Duration, Instant},
};

fn image() -> Image {
    let mut rgba = vec![0; 256 * 4 * 4];
    for y in 0..4 {
        for x in 0..256 {
            let p = match y {
                0 => [x as u8, 0, 0, 255],
                1 => [0, x as u8, 0, 255],
                2 => [0, 0, x as u8, 255],
                _ => [x as u8, x as u8, x as u8, 255],
            };
            rgba[(y * 256 + x) * 4..(y * 256 + x + 1) * 4].copy_from_slice(&p);
        }
    }
    let sha256 = format!("{:x}", Sha256::digest(&rgba));
    Image {
        width: 256,
        height: 4,
        rgba,
        sha256,
    }
}
fn quads(image: usize) -> Vec<Quad> {
    [0.25, 0.5, 0.75, 1.0]
        .into_iter()
        .enumerate()
        .map(|(i, alpha)| {
            let y = 64.0 + i as f32 * 80.0;
            Quad {
                image,
                corners: [[64.0, y], [576.0, y], [576.0, y + 32.0], [64.0, y + 32.0]],
                uv: UNIT_UV,
                color: [1.0, 1.0, 1.0, alpha],
                palette: Vec::new(),
            }
        })
        .collect()
}
pub fn run(args: impl Iterator<Item = String>) -> Result<(), String> {
    let paths: Vec<_> = args.map(PathBuf::from).collect();
    if paths.len() != 2 {
        return Err("--blend-probe NEW_PRIVATE_PNG NEW_PRIVATE_METADATA".into());
    }
    for path in &paths {
        if path.exists() {
            return Err(format!("probe evidence already exists: {}", path.display()));
        }
    }
    let mut gpu = Gles::open(true, false)?;
    let mut events = gpu.sdl.event_pump()?;
    let texture = image();
    let texture_sha = texture.sha256.clone();
    let index = gpu.upload(&texture)?;
    let commands = quads(index);
    let fbo_png = paths[0].with_file_name("blend-rgba8-fbo.png");
    let fbo_json = paths[1].with_file_name("blend-rgba8-fbo.json");
    let rgb10_png = paths[0].with_file_name("blend-rgb10-a2-fbo.png");
    let rgb10_json = paths[1].with_file_name("blend-rgb10-a2-fbo.json");
    let copy_png = paths[0].with_file_name("blend-rgb10-a2-copy-rgba8.png");
    let copy_json = paths[1].with_file_name("blend-rgb10-a2-copy-rgba8.json");
    let es300_png = paths[0].with_file_name("blend-rgb10-a2-es300-fbo.png");
    let es300_json = paths[1].with_file_name("blend-rgb10-a2-es300-fbo.json");
    let es300_copy_png = paths[0].with_file_name("blend-rgb10-a2-es300-copy-rgba8.png");
    let es300_copy_json = paths[1].with_file_name("blend-rgb10-a2-es300-copy-rgba8.json");
    for path in [
        &fbo_png,
        &fbo_json,
        &rgb10_png,
        &rgb10_json,
        &copy_png,
        &copy_json,
        &es300_png,
        &es300_json,
        &es300_copy_png,
        &es300_copy_json,
    ] {
        if path.exists() {
            return Err(format!("probe evidence already exists: {}", path.display()));
        }
    }
    let maps = std::fs::read("/proc/self/maps").map_err(|e| e.to_string())?;
    let maps_path = paths[1].with_extension("maps");
    use std::os::unix::fs::OpenOptionsExt;
    let mut maps_file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&maps_path)
        .map_err(|e| e.to_string())?;
    maps_file.write_all(&maps).map_err(|e| e.to_string())?;
    let start = Instant::now();
    let mut rgb10_target = None;
    for pass in 0..3 {
        // Default control completes unchanged before creating the sole variable.
        let target = if pass == 0 {
            None
        } else {
            Some(gpu.create_diagnostic_unorm_target(pass == 2)?)
        };
        if pass == 2 {
            rgb10_target = target;
        }
        gpu.bind_diagnostic_target(target)?;
        let info = gpu.framebuffer_info()?;
        let actual_internal_format = target
            .map(|t| gpu.diagnostic_target_internal_format(t))
            .transpose()?;
        let (png, json) = match pass {
            0 => (&paths[0], &paths[1]),
            1 => (&fbo_png, &fbo_json),
            _ => (&rgb10_png, &rgb10_json),
        };
        for frame in 0..4 {
            for event in events.poll_iter() {
                if matches!(
                    event,
                    Event::Quit { .. }
                        | Event::KeyDown {
                            keycode: Some(Keycode::Escape),
                            ..
                        }
                ) {
                    return Err("blend probe interrupted".into());
                }
            }
            if start.elapsed() > Duration::from_secs(5) {
                return Err("blend probe hard bound".into());
            }
            let size = gpu.begin([42, 46, 56])?;
            if size != [640, 480] {
                return Err(format!("probe requires640x480, actual={size:?}"));
            }
            let counts = gpu.draw(&commands)?;
            if frame == 3 {
                gpu.check_error()?;
                gpu.capture(png)?;
                let metadata = serde_json::json!({"mode":"diagnostic-only-no-gameplay-no-performance","target":match pass {0=>"current-owned-Gles-default-window",1=>"owned-RGBA8-FBO",_=>"owned-RGB10_A2-FBO"},"capture_before_present_or_blit":true,"actual_target_texture_internal_format_enum":actual_internal_format,"width":640,"height":480,"gpu_draws":4,"background_rgba8":[42,46,56,255],"texture_rgba_sha256":texture_sha,"texture_dimensions":[256,4],"quad_size":[512,32],"x":64,"ys":[64,144,224,304],"modulation_alpha":[0.25,0.5,0.75,1.0],"quads":counts.quads,"framebuffer":info,"startup_maps_path":maps_path,"audio":"disabled","actual_delivered_frames":null});
                std::fs::write(
                    json,
                    serde_json::to_vec_pretty(&metadata).map_err(|e| e.to_string())?,
                )
                .map_err(|e| e.to_string())?;
            }
            if let Some(target) = target {
                gpu.present_diagnostic_target(target)?;
            } else {
                gpu.present()?;
            }
            std::thread::sleep(Duration::from_millis(25));
            // The blit restores default bindings; next FBO frame rebinds the target.
            gpu.bind_diagnostic_target(target)?;
        }
    }
    let source = rgb10_target.ok_or("missing rendered RGB10 diagnostic source")?;
    let copy_target = gpu.create_diagnostic_readback_target()?;
    let copy_state = gpu.diagnostic_shader_copy(source, copy_target, "unchanged-ESSL100")?;
    let info = gpu.framebuffer_info()?;
    gpu.capture(&copy_png)?;
    let metadata = serde_json::json!({"mode":"diagnostic-only-no-gameplay-no-performance","target":"RGB10_A2-shader-copy-to-RGBA8","width":640,"height":480,"source_render_shader":"unchanged-ESSL100","source_render_target_internal_format_enum":gpu.diagnostic_target_internal_format(source)?,"copy_target_internal_format_enum":gpu.diagnostic_target_internal_format(copy_target)?,"texture_rgba_sha256":texture_sha,"copy_state":copy_state,"framebuffer":info,"startup_maps_path":maps_path,"capture_before_present_or_blit":true,"source_direct_control":"blend-rgb10-a2-fbo.png","actual_delivered_frames":null});
    std::fs::write(
        &copy_json,
        serde_json::to_vec_pretty(&metadata).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    gpu.present_diagnostic_target(copy_target)?;
    // All4immutable controls are complete. Only now switch original rendering
    // interface/output precision; texture, math, blending and target stay the same.
    gpu.select_diagnostic_es300_render()?;
    let target300 = gpu.create_diagnostic_unorm_target(true)?;
    gpu.bind_diagnostic_target(Some(target300))?;
    for frame in 0..4 {
        if start.elapsed() > Duration::from_secs(5) {
            return Err("blend probe hard bound".into());
        }
        if gpu.begin([42, 46, 56])? != [640, 480] {
            return Err("probe framebuffer resized".into());
        }
        gpu.draw(&commands)?;
        if frame == 3 {
            gpu.capture(&es300_png)?;
            let info = gpu.framebuffer_info()?;
            let metadata = serde_json::json!({"mode":"diagnostic-only-no-gameplay-no-performance","target":"owned-RGB10_A2-ESSL300-render","source_render_shader":"ESSL300-explicit-highp-output","numeric_math":"unchanged","texture_rgba_sha256":texture_sha,"source_direct_control":"blend-rgb10-a2-fbo.png","framebuffer":info,"actual_target_texture_internal_format_enum":gpu.diagnostic_target_internal_format(target300)?,"startup_maps_path":maps_path,"capture_before_present_or_blit":true,"actual_delivered_frames":null});
            std::fs::write(
                &es300_json,
                serde_json::to_vec_pretty(&metadata).map_err(|e| e.to_string())?,
            )
            .map_err(|e| e.to_string())?;
        }
        gpu.present_diagnostic_target(target300)?;
        gpu.bind_diagnostic_target(Some(target300))?;
        std::thread::sleep(Duration::from_millis(25));
    }
    let copy300 = gpu.create_diagnostic_readback_target()?;
    let state300 =
        gpu.diagnostic_shader_copy(target300, copy300, "ESSL300-explicit-highp-output")?;
    gpu.capture(&es300_copy_png)?;
    let metadata = serde_json::json!({"mode":"diagnostic-only-no-gameplay-no-performance","target":"ESSL300-render-RGB10_A2-shader-copy-to-RGBA8","source_render_shader":"ESSL300-explicit-highp-output","source_direct_control":"blend-rgb10-a2-es300-fbo.png","copy_control":"blend-rgb10-a2-copy-rgba8.png","copy_state":state300,"framebuffer":gpu.framebuffer_info()?,"source_render_target_internal_format_enum":gpu.diagnostic_target_internal_format(target300)?,"copy_target_internal_format_enum":gpu.diagnostic_target_internal_format(copy300)?,"texture_rgba_sha256":texture_sha,"startup_maps_path":maps_path,"capture_before_present_or_blit":true,"actual_delivered_frames":null});
    std::fs::write(
        &es300_copy_json,
        serde_json::to_vec_pretty(&metadata).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    gpu.present_diagnostic_target(copy300)?;
    gpu.bind_diagnostic_target(None)?;
    println!(
        "RUST_BLEND_PROBE_DONE draws=18 targets=6 diagnostic_only=true gameplay=false performance_claim=false"
    );
    std::io::stdout().flush().map_err(|e| e.to_string())?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn control_texture_and_quads_match_parent_spec() {
        let image = image();
        assert_eq!(&image.rgba[..4], &[0, 0, 0, 255]);
        for (row, p) in [
            [255, 0, 0, 255],
            [0, 255, 0, 255],
            [0, 0, 255, 255],
            [255, 255, 255, 255],
        ]
        .iter()
        .enumerate()
        {
            let offset = (row * 256 + 255) * 4;
            assert_eq!(&image.rgba[offset..offset + 4], p);
        }
        let q = quads(7);
        assert_eq!(q.len(), 4);
        for (i, quad) in q.iter().enumerate() {
            assert_eq!(quad.image, 7);
            assert_eq!(quad.corners[0], [64.0, 64.0 + i as f32 * 80.0]);
            assert_eq!(quad.color[3], (i + 1) as f32 / 4.0);
            assert_eq!(quad.uv, UNIT_UV);
        }
    }
}
