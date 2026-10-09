// Public FFI surface for libcoinburst_gateway.
//
// Dart loads this `.so` via `DynamicLibrary.open("libcoinburst_gateway.so")`
// and binds each symbol through dart:ffi. Every string that crosses the
// boundary is a UTF-8 `*mut c_char` owned by Rust; the Dart side MUST send
// each pointer back to `nx_release` in a `try/finally`.
//
// Export names are deliberately opaque (`nx_*`) so a reverse-engineer gets
// no hint about which function hosts the networky call vs the UA scaffold
// vs the JS blobs.

use std::ffi::{CStr, CString, c_char};

mod gateway;
mod sealed;
mod veil;

fn into_cstr(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

/// Tiny side-effect that keeps the optimiser from folding a sealed string
/// to a plaintext constant at the call site. Disassembly reads as an
/// opaque path even for a trivially small return value.
#[inline(never)]
fn jitter(s: String) -> String {
    let marker = s.len() ^ 0x5a;
    std::hint::black_box(marker);
    s
}

/// Returns the User-Agent template with `{release}`, `{brand}`, `{model}`,
/// `{build}`, `{bundle}`, `{name}` placeholders. The Dart side substitutes
/// real device_info_plus values before installing it on the WebView and
/// before handing it back on `nx_dispatch_envelope`.
#[unsafe(no_mangle)]
pub extern "C" fn nx_ua_scaffold() -> *mut c_char {
    into_cstr(jitter(sealed::ua_scaffold()))
}

/// Safe-area / viewport-fit CSS neutraliser body.
#[unsafe(no_mangle)]
pub extern "C" fn nx_overlay_safe_area() -> *mut c_char {
    into_cstr(jitter(sealed::js_safe_area()))
}

/// Keyboard focus-scroll fix body.
#[unsafe(no_mangle)]
pub extern "C" fn nx_overlay_keyboard() -> *mut c_char {
    into_cstr(jitter(sealed::js_keyboard()))
}

/// Inline-video autoplay + protected-media autograntable body.
#[unsafe(no_mangle)]
pub extern "C" fn nx_overlay_autoplay() -> *mut c_char {
    into_cstr(jitter(sealed::js_autoplay()))
}

/// End-to-end: Dart hands over a clean body JSON + the final UA string,
/// Rust HMAC-seals the envelope, POSTs over HTTPS to the sealed endpoint,
/// and returns the verdict JSON `{"ok":bool,"url":string,"status":int}`.
/// Any transport failure degrades to `ok:false,url:""`.
///
/// # Safety
/// Both pointers must be NUL-terminated UTF-8. The return value MUST be
/// released with `nx_release`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nx_dispatch_envelope(
    body_json_cstr: *const c_char,
    ua_cstr: *const c_char,
) -> *mut c_char {
    if body_json_cstr.is_null() {
        return into_cstr(r#"{"ok":false,"url":"","status":0}"#.to_string());
    }
    let body = match unsafe { CStr::from_ptr(body_json_cstr) }.to_str() {
        Ok(s) => s,
        Err(_) => return into_cstr(r#"{"ok":false,"url":"","status":0}"#.to_string()),
    };
    let ua = if ua_cstr.is_null() {
        ""
    } else {
        unsafe { CStr::from_ptr(ua_cstr) }.to_str().unwrap_or("")
    };
    let verdict = gateway::decide(body, ua);
    let json = serde_json::to_string(&verdict)
        .unwrap_or_else(|_| r#"{"ok":false,"url":"","status":0}"#.to_string());
    into_cstr(json)
}

/// Health probe — 1 iff every sealed blob decrypts to a non-empty UTF-8
/// string. The gray branch stays dormant unless this returns 1.
#[unsafe(no_mangle)]
pub extern "C" fn nx_arm_check() -> i32 {
    let ok = !sealed::endpoint().is_empty()
        && !sealed::ua_scaffold().is_empty()
        && !sealed::upstream_secret().is_empty()
        && !sealed::field_schema().is_empty()
        && !sealed::field_nonce().is_empty()
        && !sealed::field_payload().is_empty()
        && !sealed::field_tag().is_empty()
        && sealed::schema_rev() > 0;
    if ok { 1 } else { 0 }
}

/// Frees a C-string returned by any of the `nx_*` exports. Passing NULL
/// is a no-op.
///
/// # Safety
/// `ptr` must have been returned by one of the `nx_*` exports and must
/// not have been freed yet.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nx_release(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    let _ = unsafe { CString::from_raw(ptr) };
}
