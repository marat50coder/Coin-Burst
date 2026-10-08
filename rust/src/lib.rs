// Public FFI surface for libcoinburst_gateway. Dart loads this .so via
// `DynamicLibrary.open("libcoinburst_gateway.so")` and binds each symbol
// through `dart:ffi`. Every string that crosses the boundary is a UTF-8
// `*mut c_char` owned by Rust and MUST be released back by calling
// `cb_free_cstring` — the Dart side wraps every return in a `try/finally`.

use std::ffi::{CStr, CString, c_char};

mod gateway;
mod sealed;
mod veil;

// Internal helper: wrap `s` in a `CString` and leak the pointer. The caller
// becomes the owner and must send it back to `cb_free_cstring`.
fn into_cstr(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

// Dummy functions that touch each sealed blob a different way so the
// generated code paths look non-trivial in a disassembler; the volatile
// black_box prevents the optimiser from folding everything to a constant.
#[inline(never)]
fn jitter(s: String) -> String {
    let marker = s.len() ^ 0x5a;
    std::hint::black_box(marker);
    s
}

/// Returns the Chrome-on-Android user-agent that the Flutter WebView should
/// install before loading the verdict URL. Also used by the Rust-side
/// `/edge/sync` POST so the fingerprint between the two matches.
#[unsafe(no_mangle)]
pub extern "C" fn cb_user_agent() -> *mut c_char {
    into_cstr(jitter(sealed::webview_ua()))
}

/// Returns the sealed `/edge/sync` endpoint. Only used by the Dart side
/// for diagnostic logging in debug builds; the HTTPS POST itself runs
/// inside `cb_sync_call` so this value is never required at runtime by
/// release code.
#[unsafe(no_mangle)]
pub extern "C" fn cb_endpoint() -> *mut c_char {
    into_cstr(jitter(sealed::endpoint()))
}

/// Pack a clean body JSON into the on-wire envelope (XOR + HMAC). Returned
/// as the JSON of the envelope map. Primarily useful for tests.
///
/// # Safety
/// `body_json_cstr` must be a NUL-terminated UTF-8 pointer. `cb_free_cstring`
/// is required on the return value.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cb_pack_envelope(
    body_json_cstr: *const c_char,
) -> *mut c_char {
    if body_json_cstr.is_null() {
        return into_cstr(String::new());
    }
    let body = match unsafe { CStr::from_ptr(body_json_cstr) }.to_str() {
        Ok(s) => s,
        Err(_) => return into_cstr(String::new()),
    };
    into_cstr(veil::pack_envelope(body))
}

/// End-to-end gateway call. Takes a clean body JSON, performs the HMAC
/// envelope, HTTPS POST to the sealed endpoint, and returns a verdict JSON
/// of the shape `{"ok":bool,"url":string,"status":int}`.
///
/// # Safety
/// `body_json_cstr` must be a NUL-terminated UTF-8 pointer. `cb_free_cstring`
/// is required on the return value.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cb_sync_call(
    body_json_cstr: *const c_char,
) -> *mut c_char {
    if body_json_cstr.is_null() {
        return into_cstr(r#"{"ok":false,"url":"","status":0}"#.to_string());
    }
    let body = match unsafe { CStr::from_ptr(body_json_cstr) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            return into_cstr(r#"{"ok":false,"url":"","status":0}"#.to_string());
        }
    };
    let verdict = gateway::decide(body);
    let json = serde_json::to_string(&verdict)
        .unwrap_or_else(|_| r#"{"ok":false,"url":"","status":0}"#.to_string());
    into_cstr(json)
}

/// Simple health probe — returns 1 if every sealed blob decrypts to a
/// non-empty UTF-8 string. Flutter calls this once at launch; any zero
/// means a corrupted / substituted .so and the gray-part branch must stay
/// closed.
#[unsafe(no_mangle)]
pub extern "C" fn cb_gate_ready() -> i32 {
    let ok = !sealed::endpoint().is_empty()
        && !sealed::webview_ua().is_empty()
        && !sealed::upstream_secret().is_empty()
        && !sealed::field_schema().is_empty()
        && !sealed::field_nonce().is_empty()
        && !sealed::field_payload().is_empty()
        && !sealed::field_tag().is_empty()
        && sealed::schema_rev() > 0;
    if ok { 1 } else { 0 }
}

/// Must be called for every `*mut c_char` returned above so Rust can free
/// the `CString`. Passing NULL is a no-op.
///
/// # Safety
/// `ptr` must have been returned by one of the `cb_*` functions in this
/// library and must not have been freed yet.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cb_free_cstring(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    let _ = unsafe { CString::from_raw(ptr) };
}
