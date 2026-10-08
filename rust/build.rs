// Compile-time string sealer for the Coin Burst gateway.
//
// At build time we generate `src/sealed_blobs.rs` containing every gray-part
// literal as a tuple `(len, [u8; N])` of XOR-encrypted bytes. The decryption
// key is split into four quarters, interleaved with build-time salt, and
// never appears as a single contiguous array in the binary. This forces a
// reverse-engineer to recover and recombine four separate blobs before any
// plaintext becomes readable.
//
// Secrets live in the environment or in gitignored rust/gateway.local so the
// raw text never enters git:
//   CB_ENDPOINT, CB_UPSTREAM_SECRET, CB_FIELD_SCHEMA, CB_FIELD_NONCE,
//   CB_FIELD_PAYLOAD, CB_FIELD_TAG, CB_SCHEMA_REV, CB_WEBVIEW_UA
// A checkout without either source fails the build instead of sealing
// empty strings into the .so.

use rand::RngCore;
use std::env;
use std::fs;
use std::io::Write;
use std::path::Path;

/// Reads `rust/gateway.local` (gitignored). Env vars win over the file so a
/// CI job can inject values without writing them to disk. Nothing in this
/// function falls back to a baked-in secret — a public checkout must not
/// contain the relay key or the endpoint in plaintext.
fn load_local_file() -> std::collections::HashMap<String, String> {
    let mut map = std::collections::HashMap::new();
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

fn secret(local: &std::collections::HashMap<String, String>, key: &str) -> String {
    if let Ok(v) = env::var(key) {
        if !v.is_empty() {
            return v;
        }
    }
    local.get(key).cloned().filter(|v| !v.is_empty()).unwrap_or_default()
}

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    for e in [
        "CB_ENDPOINT",
        "CB_UPSTREAM_SECRET",
        "CB_FIELD_SCHEMA",
        "CB_FIELD_NONCE",
        "CB_FIELD_PAYLOAD",
        "CB_FIELD_TAG",
        "CB_SCHEMA_REV",
        "CB_WEBVIEW_UA",
    ] {
        println!("cargo:rerun-if-env-changed={e}");
    }

    println!("cargo:rerun-if-changed=gateway.local");
    let local = load_local_file();
    let endpoint = secret(&local, "CB_ENDPOINT");
    let upstream_secret = secret(&local, "CB_UPSTREAM_SECRET");
    let field_schema = secret(&local, "CB_FIELD_SCHEMA");
    let field_nonce = secret(&local, "CB_FIELD_NONCE");
    let field_payload = secret(&local, "CB_FIELD_PAYLOAD");
    let field_tag = secret(&local, "CB_FIELD_TAG");
    let schema_rev = secret(&local, "CB_SCHEMA_REV");
    // GAME THEME CATEGORY: casual, slot/casino look-alike (points only, no
    // real-money gambling). The UA keeps an AppId/AppName suffix so the
    // relay can shed clearly-bot traffic later. Value lives in gateway.local.
    let webview_ua = secret(&local, "CB_WEBVIEW_UA");
    if endpoint.is_empty()
        || upstream_secret.is_empty()
        || field_schema.is_empty()
        || webview_ua.is_empty()
    {
        panic!(
            "gray-part values missing: set CB_* env vars or write rust/gateway.local (gitignored)"
        );
    }

    // Deterministic-but-per-build 32-byte key (changes every rebuild).
    // `gen` is a reserved keyword in Rust 2024, so we fill the per-build
    // 32-byte XOR key via `next_u32` instead of `rng.gen()`.
    let mut rng = rand::thread_rng();
    let mut key = [0u8; 32];
    for b in key.iter_mut() {
        *b = (rng.next_u32() & 0xff) as u8;
    }

    // Split the key into four quarters that we store in separate static
    // arrays. The decryptor interleaves them at runtime; a plain hex scan
    // for a single 32-byte key will miss it.
    let (k0, k1, k2, k3) = (&key[0..8], &key[8..16], &key[16..24], &key[24..32]);

    let out_dir = env::var_os("OUT_DIR").unwrap();
    let dest = Path::new(&out_dir).join("sealed_blobs.rs");
    let mut f = fs::File::create(&dest).unwrap();

    writeln!(
        f,
        "// AUTO-GENERATED. Do not commit — regenerated on every `cargo build`."
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
    emit_sealed(&mut f, "WEBVIEW_UA", &webview_ua, &key);

    // Also seal a few decoy blobs so grep over the .so for base64/XOR-ish
    // patterns surfaces more candidates than there are real secrets.
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
        // Each byte XORed with (key[i mod 32] XOR i-as-u8) so the ciphertext
        // isn't a trivial repeat of the key.
        sealed.push(b ^ key[i % 32] ^ (i as u8).wrapping_mul(31));
    }
    write!(f, "pub(crate) const {name}: (usize, &[u8]) = ({n}, &[").unwrap();
    for b in &sealed {
        write!(f, "0x{b:02x}, ").unwrap();
    }
    writeln!(f, "]);").unwrap();
}
