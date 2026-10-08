// End-to-end gateway call: body JSON → envelope → HTTPS POST → verdict.
// All of the network I/O happens inside the .so so the endpoint URL and
// the User-Agent used for the call never materialise in Dart memory.

use std::time::Duration;

use crate::{sealed, veil};

#[derive(serde::Serialize)]
pub(crate) struct Verdict {
    pub ok: bool,
    pub url: String,
    pub status: u16,
}

/// Pack the clean body, POST to the sealed endpoint, parse the config
/// answer. Returns a verdict that is safe for the Flutter side to see
/// (just a boolean + a URL to open, no secrets).
pub(crate) fn decide(body_json: &str) -> Verdict {
    let envelope = veil::pack_envelope(body_json);
    let endpoint = sealed::endpoint();
    let ua = sealed::webview_ua();

    let agent = ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(8))
        .timeout(Duration::from_secs(20))
        // Do NOT forward X-Forwarded-For; the upstream config.php 404s
        // "No data" if any proxy header leaks through.
        .user_agent(&ua)
        .build();

    let resp = agent
        .post(&endpoint)
        .set("Content-Type", "application/json")
        .set("Accept", "application/json")
        .send_string(&envelope);

    let (status, body) = match resp {
        Ok(r) => (r.status(), r.into_string().unwrap_or_default()),
        Err(ureq::Error::Status(code, r)) => (code, r.into_string().unwrap_or_default()),
        Err(_) => (0, String::new()),
    };

    // Successful config answer looks like `{"ok":true,"url":"…"}`.
    if status == 200 {
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&body) {
            let ok = v.get("ok").and_then(|x| x.as_bool()).unwrap_or(false);
            let url = v
                .get("url")
                .and_then(|x| x.as_str())
                .unwrap_or("")
                .to_string();
            if ok && !url.is_empty() {
                return Verdict { ok: true, url, status };
            }
        }
    }

    Verdict {
        ok: false,
        url: String::new(),
        status,
    }
}
