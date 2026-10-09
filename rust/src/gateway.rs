// End-to-end gateway call: body JSON → envelope → HTTPS POST → verdict.
// All I/O happens inside the `.so` so the endpoint URL never materialises
// in Dart memory. The User-Agent arrives from Dart (built from
// device_info_plus data) so the fingerprint matches what the WebView will
// install.

use std::time::Duration;

use crate::{sealed, veil};

#[derive(serde::Serialize)]
pub(crate) struct Verdict {
    pub ok: bool,
    pub url: String,
    pub status: u16,
}

pub(crate) fn decide(body_json: &str, user_agent: &str) -> Verdict {
    let envelope = veil::pack_envelope(body_json);
    let endpoint = sealed::endpoint();

    let agent = ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(8))
        .timeout(Duration::from_secs(21))
        .user_agent(user_agent)
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
