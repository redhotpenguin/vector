use crate::{event::Event, Result};
use bytes::Bytes;
use prost::Message;
use std::sync::Arc;

mod dd_proto {
    include!(concat!(env!("OUT_DIR"), "/datadog.agentpayload.rs"));
}

use dd_proto::SketchPayload;

pub(crate) fn decode_ddsketch(frame: Bytes, _: Option<Arc<str>>) -> Result<Vec<Event>> {
    // decode protobuf payload
    let payload = SketchPayload::decode(frame)?;

    for s in payload.sketches.iter() {
        debug!(
            message = "Deserialized a datadog sketch payload - /api/beta/sketches",
            name = ?s.metric,
            host = ?s.host,
        );
    }
    Ok(vec![])
}

