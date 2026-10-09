// Envelope packer — mirrors the FastAPI relay in scripts/relay_service.py.
// The field names, HMAC secret, and schema revision all live sealed in
// src/sealed.rs so an apktool dump shows nothing wire-shaped.

use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use hmac::{Hmac, Mac};
use rand::RngCore;
use sha2::{Digest, Sha256};

use crate::sealed;

type HmacSha256 = Hmac<Sha256>;

fn keystream(secret: &[u8], nonce: &[u8], len: usize) -> Vec<u8> {
    let mut out = Vec::with_capacity(len);
    let mut counter: u32 = 0;
    while out.len() < len {
        let mut h = Sha256::new();
        h.update(secret);
        h.update(nonce);
        h.update(counter.to_be_bytes());
        out.extend_from_slice(&h.finalize());
        counter = counter.wrapping_add(1);
    }
    out.truncate(len);
    out
}

/// Pack `body_json` into the on-wire envelope. Field names (`h/j/l/x`),
/// schema rev, and HMAC secret all unseal at call time.
pub(crate) fn pack_envelope(body_json: &str) -> String {
    let secret = sealed::upstream_secret();
    let mut nonce = [0u8; 16];
    rand::thread_rng().fill_bytes(&mut nonce);

    let raw = body_json.as_bytes();
    let ks = keystream(&secret, &nonce, raw.len());
    let mut enc = Vec::with_capacity(raw.len());
    for (b, k) in raw.iter().zip(ks.iter()) {
        enc.push(b ^ k);
    }

    let mut mac = HmacSha256::new_from_slice(&secret).expect("hmac len");
    mac.update(&nonce);
    mac.update(&enc);
    let tag_full = mac.finalize().into_bytes();
    let tag_hex = {
        let mut s = String::with_capacity(32);
        for b in &tag_full {
            use std::fmt::Write;
            let _ = write!(&mut s, "{b:02x}");
        }
        s[..16].to_string()
    };

    let nonce_hex = {
        let mut s = String::with_capacity(32);
        for b in &nonce {
            use std::fmt::Write;
            let _ = write!(&mut s, "{b:02x}");
        }
        s
    };
    let payload_b64 = URL_SAFE_NO_PAD.encode(&enc);

    let mut json = serde_json::Map::new();
    json.insert(sealed::field_schema(), sealed::schema_rev().into());
    json.insert(sealed::field_nonce(), nonce_hex.into());
    json.insert(sealed::field_payload(), payload_b64.into());
    json.insert(sealed::field_tag(), tag_hex.into());
    serde_json::Value::Object(json).to_string()
}
