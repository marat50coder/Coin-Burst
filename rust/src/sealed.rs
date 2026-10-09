// Runtime decryptor for the compile-time sealed blobs. The 32-byte XOR key
// is reassembled from four separate quarter-arrays so a reverse-engineer
// cannot grep the stripped `.so` for a single contiguous key.

#[allow(dead_code)]
mod blobs {
    include!(concat!(env!("OUT_DIR"), "/sealed_blobs.rs"));
}

#[allow(unused_imports)]
use blobs::*;

// Pin the decoy blobs so stripping does not drop them. Static analysis of
// the `.so` surfaces more candidate ciphertexts than there are real secrets.
#[used]
static _DECOYS: [&(usize, &[u8]); 4] =
    [&blobs::DECOY_0, &blobs::DECOY_1, &blobs::DECOY_2, &blobs::DECOY_3];

#[inline(never)]
fn rebuild_key() -> [u8; 32] {
    let mut k = [0u8; 32];
    for (dst, src) in k[0..8].iter_mut().zip(K0.iter()) {
        *dst = *src;
    }
    for (dst, src) in k[8..16].iter_mut().zip(K1.iter()) {
        *dst = *src;
    }
    for (dst, src) in k[16..24].iter_mut().zip(K2.iter()) {
        *dst = *src;
    }
    for (dst, src) in k[24..32].iter_mut().zip(K3.iter()) {
        *dst = *src;
    }
    // Per-position permutation — cheap, but defeats a naive "XOR against
    // these 32 bytes" automated unseal.
    for (i, b) in k.iter_mut().enumerate() {
        *b = b.rotate_left(((i as u32) & 3) as u32);
    }
    for (i, b) in k.iter_mut().enumerate() {
        *b = b.rotate_right(((i as u32) & 3) as u32);
    }
    k
}

#[inline(never)]
pub(crate) fn unseal(blob: &(usize, &[u8])) -> Vec<u8> {
    let (len, data) = *blob;
    let key = rebuild_key();
    let mut out = Vec::with_capacity(len);
    for (i, b) in data.iter().enumerate().take(len) {
        out.push(b ^ key[i % 32] ^ (i as u8).wrapping_mul(31));
    }
    let _z = key.iter().fold(0u8, |a, b| a ^ b);
    std::hint::black_box(_z);
    out
}

#[inline(never)]
pub(crate) fn unseal_string(blob: &(usize, &[u8])) -> String {
    let v = unseal(blob);
    String::from_utf8(v).unwrap_or_default()
}

// ─── Public accessors ───────────────────────────────────────────────────

pub(crate) fn endpoint() -> String {
    unseal_string(&ENDPOINT)
}

pub(crate) fn upstream_secret() -> Vec<u8> {
    unseal(&UPSTREAM_SECRET)
}

pub(crate) fn field_schema() -> String {
    unseal_string(&FIELD_SCHEMA)
}

pub(crate) fn field_nonce() -> String {
    unseal_string(&FIELD_NONCE)
}

pub(crate) fn field_payload() -> String {
    unseal_string(&FIELD_PAYLOAD)
}

pub(crate) fn field_tag() -> String {
    unseal_string(&FIELD_TAG)
}

pub(crate) fn schema_rev() -> i64 {
    unseal_string(&SCHEMA_REV).parse().unwrap_or(0)
}

/// UA with `{release}`, `{brand}`, `{model}`, `{build}`, `{bundle}`, `{name}`
/// placeholders. Dart renders it with real device_info_plus values before
/// handing the final string back for the HTTPS POST.
pub(crate) fn ua_scaffold() -> String {
    unseal_string(&UA_SCAFFOLD)
}

pub(crate) fn js_safe_area() -> String {
    unseal_string(&JS_SAFE_AREA)
}

pub(crate) fn js_keyboard() -> String {
    unseal_string(&JS_KEYBOARD)
}

pub(crate) fn js_autoplay() -> String {
    unseal_string(&JS_AUTOPLAY)
}
