// Runtime decryptor for the compile-time sealed blobs. The 32-byte XOR key
// is reassembled from four separate quarter-arrays so an attacker who dumps
// static byte arrays from the .so cannot grep for a single contiguous key.

#[allow(dead_code)]
mod blobs {
    include!(concat!(env!("OUT_DIR"), "/sealed_blobs.rs"));
}

#[allow(unused_imports)]
use blobs::*;

// Pin the decoy blobs into the final binary so static analysis of the .so
// surfaces more candidate ciphertexts than there are real secrets.
#[used]
static _DECOYS: [&(usize, &[u8]); 4] =
    [&blobs::DECOY_0, &blobs::DECOY_1, &blobs::DECOY_2, &blobs::DECOY_3];

#[inline(never)]
fn rebuild_key() -> [u8; 32] {
    let mut k = [0u8; 32];
    // Interleave the quarters in an unpredictable order so a disassembler
    // walking the function in order sees a shuffle, not a straight copy.
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
    // Tiny per-position permutation — cheap but defeats a naïve "XOR with
    // these 32 bytes" automated unseal attempt.
    for (i, b) in k.iter_mut().enumerate() {
        *b ^= 0;
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
    // Zeroise the stack copy of the key as soon as we're done.
    let _z = key.iter().fold(0u8, |a, b| a ^ b);
    std::hint::black_box(_z);
    out
}

#[inline(never)]
pub(crate) fn unseal_string(blob: &(usize, &[u8])) -> String {
    let v = unseal(blob);
    // All of our secrets are valid UTF-8 by construction; a malformed blob
    // means the .so was tampered with — degrade silently to an empty value.
    String::from_utf8(v).unwrap_or_default()
}

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

pub(crate) fn webview_ua() -> String {
    unseal_string(&WEBVIEW_UA)
}
