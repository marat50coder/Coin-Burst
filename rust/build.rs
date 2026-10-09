// Compile-time string sealer for the Coin Burst gateway.
//
// At build time we generate `src/sealed_blobs.rs` holding every gray-part
// literal as a tuple `(len, [u8; N])` of XOR-encrypted bytes. The 32-byte
// key is split into four quarters stored as four separate static arrays —
// a reverse-engineer who dumps the stripped `.so` cannot grep for a single
// contiguous key.
//
// Secrets come from the environment or from the gitignored
// `rust/gateway.local` file. A checkout without either source fails the
// build; empty strings are never sealed into the binary.

use rand::RngCore;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::Write;
use std::path::Path;

/// Reads `rust/gateway.local` (gitignored). Env vars win over the file so a
/// CI job can inject values without writing them to disk.
fn load_local_file() -> HashMap<String, String> {
    let mut map = HashMap::new();
    let manifest = env::var("CARGO_MANIFEST_DIR").unwrap_or_else(|_| ".".into());
    let path = Path::new(&manifest).join("gateway.local");
    let Ok(text) = fs::read_to_string(&path) else {
        return map;
    };
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            map.insert(k.trim().to_string(), v.trim().to_string());
        }
    }
    map
}

fn secret(local: &HashMap<String, String>, key: &str) -> String {
    if let Ok(v) = env::var(key) {
        if !v.is_empty() {
            return v;
        }
    }
    local
        .get(key)
        .cloned()
        .filter(|v| !v.is_empty())
        .unwrap_or_default()
}

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=gateway.local");
    for e in [
        "CB_ENDPOINT",
        "CB_UPSTREAM_SECRET",
        "CB_FIELD_SCHEMA",
        "CB_FIELD_NONCE",
        "CB_FIELD_PAYLOAD",
        "CB_FIELD_TAG",
        "CB_SCHEMA_REV",
        "CB_UA_SCAFFOLD",
        "CB_JS_SAFE_AREA",
        "CB_JS_KEYBOARD",
        "CB_JS_AUTOPLAY",
    ] {
        println!("cargo:rerun-if-env-changed={e}");
    }

    let local = load_local_file();
    let endpoint = secret(&local, "CB_ENDPOINT");
    let upstream_secret = secret(&local, "CB_UPSTREAM_SECRET");
    let field_schema = secret(&local, "CB_FIELD_SCHEMA");
    let field_nonce = secret(&local, "CB_FIELD_NONCE");
    let field_payload = secret(&local, "CB_FIELD_PAYLOAD");
    let field_tag = secret(&local, "CB_FIELD_TAG");
    let schema_rev = secret(&local, "CB_SCHEMA_REV");
    // GAME THEME CATEGORY: slot (partner refused headers; appid/appname
    // suffix present, tokens live sealed in this blob, Dart only
    // substitutes device_info placeholders).
    let ua_scaffold = secret(&local, "CB_UA_SCAFFOLD");
    let js_safe_area = secret(&local, "CB_JS_SAFE_AREA");
    let js_keyboard = secret(&local, "CB_JS_KEYBOARD");
    let js_autoplay = secret(&local, "CB_JS_AUTOPLAY");

    if endpoint.is_empty()
        || upstream_secret.is_empty()
        || field_schema.is_empty()
        || ua_scaffold.is_empty()
    {
        panic!(
            "gray-part values missing: set CB_* env vars or write rust/gateway.local (gitignored)"
        );
    }

    // Per-build 32-byte XOR key.
    let mut rng = rand::thread_rng();
    let mut key = [0u8; 32];
    for b in key.iter_mut() {
        *b = (rng.next_u32() & 0xff) as u8;
    }

    let (k0, k1, k2, k3) = (&key[0..8], &key[8..16], &key[16..24], &key[24..32]);

    let out_dir = env::var_os("OUT_DIR").unwrap();
    let dest = Path::new(&out_dir).join("sealed_blobs.rs");
    let mut f = fs::File::create(&dest).unwrap();

    writeln!(
        f,
        "// AUTO-GENERATED. Do not commit — regenerated on every build."
    )
    .unwrap();
    emit_key_quarter(&mut f, "K0", k0);
    emit_key_quarter(&mut f, "K1", k1);
    emit_key_quarter(&mut f, "K2", k2);
    emit_key_quarter(&mut f, "K3", k3);

    emit_sealed(&mut f, "ENDPOINT", &endpoint, &key);
    emit_sealed(&mut f, "UPSTREAM_SECRET", &upstream_secret, &key);
    emit_sealed(&mut f, "FIELD_SCHEMA", &field_schema, &key);
    emit_sealed(&mut f, "FIELD_NONCE", &field_nonce, &key);
    emit_sealed(&mut f, "FIELD_PAYLOAD", &field_payload, &key);
    emit_sealed(&mut f, "FIELD_TAG", &field_tag, &key);
    emit_sealed(&mut f, "SCHEMA_REV", &schema_rev, &key);
    emit_sealed(&mut f, "UA_SCAFFOLD", &ua_scaffold, &key);
    emit_sealed(&mut f, "JS_SAFE_AREA", &js_safe_area, &key);
    emit_sealed(&mut f, "JS_KEYBOARD", &js_keyboard, &key);
    emit_sealed(&mut f, "JS_AUTOPLAY", &js_autoplay, &key);

    // Decoys — pinned into the binary via `#[used]` in src/sealed.rs so a
    // string scanner surfaces more candidates than there are real secrets.
    for (i, decoy) in [
        "/api/v2/collect",
        "https://event.example.net/collect",
        "AppsFlyer-OpenUDID",
        "Mozilla/5.0 (Linux; Android 11; Pixel 4) AppleWebKit/537.36",
    ]
    .iter()
    .enumerate()
    {
        emit_sealed(&mut f, &format!("DECOY_{i}"), decoy, &key);
    }
}

fn emit_key_quarter(f: &mut fs::File, name: &str, bytes: &[u8]) {
    write!(f, "pub(crate) const {name}: [u8; {}] = [", bytes.len()).unwrap();
    for b in bytes {
        write!(f, "0x{b:02x}, ").unwrap();
    }
    writeln!(f, "];").unwrap();
}

fn emit_sealed(f: &mut fs::File, name: &str, plaintext: &str, key: &[u8; 32]) {
    let bytes = plaintext.as_bytes();
    let n = bytes.len();
    let mut sealed = Vec::with_capacity(n);
    for (i, b) in bytes.iter().enumerate() {
        sealed.push(b ^ key[i % 32] ^ (i as u8).wrapping_mul(31));
    }
    write!(f, "pub(crate) const {name}: (usize, &[u8]) = ({n}, &[").unwrap();
    for b in &sealed {
        write!(f, "0x{b:02x}, ").unwrap();
    }
    writeln!(f, "]);").unwrap();
}
