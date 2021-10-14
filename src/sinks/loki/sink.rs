use super::config::{Encoding, LokiConfig, OutOfOrderAction};
use super::event::{GlobalTimestamps, LokiBatchEncoder, LokiEvent, LokiRecord, PartitionKey};
use super::service::{LokiRequest, LokiService};
use crate::config::log_schema;
use crate::config::SinkContext;
use crate::http::HttpClient;
use crate::internal_events::{
    LokiEventUnlabeled, LokiEventsProcessed, LokiOutOfOrderEventDropped,
    LokiOutOfOrderEventRewritten, TemplateRenderingFailed,
};
use crate::sinks::util::builder::SinkBuilderExt;
use crate::sinks::util::encoding::{EncodingConfig, EncodingConfiguration};
use crate::sinks::util::{BatchSettings, Compression, RequestBuilder};
use crate::template::Template;
use futures::stream::{BoxStream, Stream};
use futures::StreamExt;
use pin_project::pin_project;
use shared::encode_logfmt;
use snafu::Snafu;
use std::collections::HashMap;
use std::num::NonZeroUsize;
use std::pin::Pin;
use std::task::{Context, Poll};
use std::time::Duration;
use vector_core::buffers::Acker;
use vector_core::event::{self, Event, EventFinalizers, Finalizable, Value};
use vector_core::partition::Partitioner;
use vector_core::sink::StreamSink;
use vector_core::stream::BatcherSettings;

#[derive(Clone)]
pub struct KeyPartitioner(Option<Template>);

impl KeyPartitioner {
    pub const fn new(template: Option<Template>) -> Self {
        Self(template)
    }
}

impl Partitioner for KeyPartitioner {
    type Item = Event;
    type Key = Option<String>;

    fn partition(&self, item: &Self::Item) -> Self::Key {
        self.0.as_ref().and_then(|t| {
            t.render_string(item)
                .map_err(|error| {
                    emit!(&TemplateRenderingFailed {
                        error,
                        field: Some("tenant_id"),
                        drop_event: false,
                    })
                })
                .ok()
        })
    }
}

#[derive(Default)]
struct RecordPartitionner;

impl Partitioner for RecordPartitionner {
    type Item = LokiRecord;
    type Key = PartitionKey;

    fn partition(&self, item: &Self::Item) -> Self::Key {
        item.partition.clone()
    }
}

#[derive(Clone)]
pub struct LokiRequestBuilder {
    compression: Compression,
    encoder: LokiBatchEncoder,
}

#[derive(Debug, Snafu)]
pub enum RequestBuildError {
    #[snafu(display("Encoded payload is greater than the max limit."))]
    PayloadTooBig,
    #[snafu(display("Failed to build payload with error: {}", error))]
    Io { error: std::io::Error },
}

impl From<std::io::Error> for RequestBuildError {
    fn from(error: std::io::Error) -> RequestBuildError {
        RequestBuildError::Io { error }
    }
}

impl Default for LokiRequestBuilder {
    fn default() -> Self {
        Self {
            compression: Compression::None,
            encoder: LokiBatchEncoder::default(),
        }
    }
}

impl RequestBuilder<(PartitionKey, Vec<LokiRecord>)> for LokiRequestBuilder {
    type Metadata = (Option<String>, usize, EventFinalizers);
    type Events = Vec<LokiRecord>;
    type Encoder = LokiBatchEncoder;
    type Payload = Vec<u8>;
    type Request = LokiRequest;
    type Error = RequestBuildError;

    fn compression(&self) -> Compression {
        self.compression
    }

    fn encoder(&self) -> &Self::Encoder {
        &self.encoder
    }

    fn split_input(
        &self,
        input: (PartitionKey, Vec<LokiRecord>),
    ) -> (Self::Metadata, Self::Events) {
        let (key, mut events) = input;
        let batch_size = events.len();
        let finalizers = events
            .iter_mut()
            .fold(EventFinalizers::default(), |mut acc, x| {
                acc.merge(x.take_finalizers());
                acc
            });

        ((key.tenant_id, batch_size, finalizers), events)
    }

    fn build_request(&self, metadata: Self::Metadata, payload: Self::Payload) -> Self::Request {
        let (tenant_id, batch_size, finalizers) = metadata;
        emit!(&LokiEventsProcessed {
            byte_size: payload.len(),
        });

        LokiRequest {
            batch_size,
            finalizers,
            payload,
            tenant_id,
        }
    }
}

#[derive(Clone)]
pub(super) struct EventEncoder {
    key_partitioner: KeyPartitioner,
    encoding: EncodingConfig<Encoding>,
    labels: HashMap<Template, Template>,
    remove_label_fields: bool,
    remove_timestamp: bool,
}

impl EventEncoder {
    fn build_labels(&self, event: &Event) -> Vec<(String, String)> {
        self.labels
            .iter()
            .filter_map(|(key_template, value_template)| {
                if let (Ok(key), Ok(value)) = (
                    key_template.render_string(event),
                    value_template.render_string(event),
                ) {
                    Some((key, value))
                } else {
                    None
                }
            })
            .collect()
    }

    fn remove_label_fields(&self, event: &mut Event) {
        if self.remove_label_fields {
            for template in self.labels.values() {
                if let Some(fields) = template.get_fields() {
                    for field in fields {
                        event.as_mut_log().remove(&field);
                    }
                }
            }
        }
    }

    pub(super) fn encode_event(&self, mut event: Event) -> LokiRecord {
        let tenant_id = self.key_partitioner.partition(&event);
        let finalizers = event.take_finalizers();
        let mut labels = self.build_labels(&event);
        self.remove_label_fields(&mut event);

        let timestamp = match event.as_log().get(log_schema().timestamp_key()) {
            Some(event::Value::Timestamp(ts)) => ts.timestamp_nanos(),
            _ => chrono::Utc::now().timestamp_nanos(),
        };

        if self.remove_timestamp {
            event.as_mut_log().remove(log_schema().timestamp_key());
        }

        self.encoding.apply_rules(&mut event);
        let log = event.into_log();
        let event = match &self.encoding.codec() {
            Encoding::Json => {
                serde_json::to_string(&log).expect("json encoding should never fail.")
            }

            Encoding::Text => log
                .get(log_schema().message_key())
                .map(Value::to_string_lossy)
                .unwrap_or_default(),

            Encoding::Logfmt => encode_logfmt::to_string(log.into_parts().0)
                .expect("Logfmt encoding should never fail."),
        };

        // If no labels are provided we set our own default
        // `{agent="vector"}` label. This can happen if the only
        // label is a templatable one but the event doesn't match.
        if labels.is_empty() {
            emit!(&LokiEventUnlabeled);
            labels = vec![("agent".to_string(), "vector".to_string())]
        }

        let partition = PartitionKey::new(tenant_id, &mut labels);

        LokiRecord {
            labels,
            event: LokiEvent { timestamp, event },
            partition,
            finalizers,
        }
    }
}

#[pin_project]
struct FilterEncoder<St> {
    #[pin]
    input: St,
    encoder: EventEncoder,
    global_timestamps: GlobalTimestamps,
    out_of_order_action: OutOfOrderAction,
}

impl<St> FilterEncoder<St> {
    const fn new(
        input: St,
        encoder: EventEncoder,
        global_timestamps: GlobalTimestamps,
        out_of_order_action: OutOfOrderAction,
    ) -> Self {
        Self {
            input,
            encoder,
            global_timestamps,
            out_of_order_action,
        }
    }
}

impl<St> Stream for FilterEncoder<St>
where
    St: Stream<Item = Event> + Unpin,
{
    type Item = LokiRecord;

    fn size_hint(&self) -> (usize, Option<usize>) {
        self.input.size_hint()
    }

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let mut this = self.project();

        match this.input.as_mut().poll_next(cx) {
            Poll::Ready(Some(item)) => {
                let mut item = this.encoder.encode_event(item);

                let partition = &item.partition;
                let latest_timestamp = this.global_timestamps.take(partition);

                let latest_timestamp = latest_timestamp.unwrap_or(item.event.timestamp);

                if item.event.timestamp < latest_timestamp {
                    match this.out_of_order_action {
                        OutOfOrderAction::Drop => {
                            emit!(&LokiOutOfOrderEventDropped);
                            Poll::Ready(None)
                        }
                        OutOfOrderAction::RewriteTimestamp => {
                            emit!(&LokiOutOfOrderEventRewritten);
                            item.event.timestamp = latest_timestamp;
                            Poll::Ready(Some(item))
                        }
                    }
                } else {
                    this.global_timestamps
                        .insert(partition.clone(), item.event.timestamp);
                    Poll::Ready(Some(item))
                }
            }
            Poll::Ready(None) => Poll::Ready(None),
            Poll::Pending => Poll::Pending,
        }
    }
}

#[derive(Clone)]
pub struct LokiSink {
    acker: Acker,
    request_builder: LokiRequestBuilder,
    pub(super) encoder: EventEncoder,
    batch_settings: BatcherSettings,
    timeout: Duration,
    out_of_order_action: OutOfOrderAction,
    service: LokiService,
}

impl LokiSink {
    #[allow(clippy::missing_const_for_fn)] // const cannot run destructor
    pub fn new(config: LokiConfig, client: HttpClient, cx: SinkContext) -> crate::Result<Self> {
        Ok(Self {
            acker: cx.acker(),
            request_builder: LokiRequestBuilder::default(),
            encoder: EventEncoder {
                key_partitioner: KeyPartitioner::new(config.tenant_id),
                encoding: config.encoding,
                labels: config.labels,
                remove_label_fields: config.remove_label_fields,
                remove_timestamp: config.remove_timestamp,
            },
            batch_settings: BatchSettings::<()>::default()
                .parse_config(config.batch)?
                .into_batcher_settings()?,
            timeout: Duration::from_secs(config.batch.timeout_secs.unwrap_or(1)),
            out_of_order_action: config.out_of_order_action,
            service: LokiService::new(client, config.endpoint, config.auth)?,
        })
    }

    async fn run_inner(self: Box<Self>, input: BoxStream<'_, Event>) -> Result<(), ()> {
        let service = tower::ServiceBuilder::new().service(self.service);

        let filter = FilterEncoder::new(
            input,
            self.encoder.clone(),
            GlobalTimestamps::default(),
            self.out_of_order_action.clone(),
        );

        let sink = filter
            .batched(RecordPartitionner::default(), self.batch_settings)
            .request_builder(NonZeroUsize::new(1), self.request_builder.clone())
            .filter_map(|request| async move {
                match request {
                    Err(e) => {
                        error!("Failed to build Loki request: {:?}.", e);
                        None
                    }
                    Ok(req) => Some(req),
                }
            })
            .into_driver(service, self.acker);

        sink.run().await
    }
}

#[async_trait::async_trait]
impl StreamSink for LokiSink {
    async fn run(mut self: Box<Self>, input: BoxStream<'_, Event>) -> Result<(), ()> {
        self.run_inner(input).await
    }
}

#[cfg(test)]
mod tests {
    use super::{EventEncoder, FilterEncoder, KeyPartitioner};
    use crate::config::log_schema;
    use crate::sinks::loki::config::{Encoding, OutOfOrderAction};
    use crate::sinks::loki::event::GlobalTimestamps;
    use crate::sinks::util::encoding::EncodingConfig;
    use crate::template::Template;
    use crate::test_util::random_lines;
    use futures::stream::Stream;
    use std::collections::HashMap;
    use std::convert::TryFrom;
    use std::pin::Pin;
    use std::task::{Context, Poll};
    use vector_core::event::Event;

    async fn collect<St, E>(mut input: St, abort_after: usize) -> Vec<E>
    where
        St: Stream<Item = E> + std::marker::Unpin,
    {
        let mut stream = Pin::new(&mut input);
        let noop_waker = futures::task::noop_waker();
        let mut cx = Context::from_waker(&noop_waker);
        let mut res = Vec::new();
        let mut none_count: usize = 0;
        loop {
            match stream.as_mut().poll_next(&mut cx) {
                Poll::Pending => {}
                Poll::Ready(None) => {
                    none_count += 1;
                    if none_count >= abort_after {
                        return res;
                    }
                }
                Poll::Ready(Some(item)) => {
                    none_count = 0;
                    res.push(item);
                }
            }
        }
    }

    #[test]
    fn encoder_no_labels() {
        let encoder = EventEncoder {
            key_partitioner: KeyPartitioner::new(None),
            encoding: EncodingConfig::from(Encoding::Json),
            labels: HashMap::default(),
            remove_label_fields: false,
            remove_timestamp: false,
        };
        let mut event = Event::from("hello world");
        let log = event.as_mut_log();
        log.insert(log_schema().timestamp_key(), chrono::Utc::now());
        let record = encoder.encode_event(event);
        assert!(record.event.event.contains(log_schema().timestamp_key()));
        assert_eq!(record.labels.len(), 1);
        assert_eq!(
            record.labels[0],
            ("agent".to_string(), "vector".to_string())
        );
    }

    #[test]
    fn encoder_with_labels() {
        let mut labels = HashMap::default();
        labels.insert(
            Template::try_from("static").unwrap(),
            Template::try_from("value").unwrap(),
        );
        labels.insert(
            Template::try_from("{{ name }}").unwrap(),
            Template::try_from("{{ value }}").unwrap(),
        );
        let encoder = EventEncoder {
            key_partitioner: KeyPartitioner::new(None),
            encoding: EncodingConfig::from(Encoding::Json),
            labels,
            remove_label_fields: false,
            remove_timestamp: false,
        };
        let mut event = Event::from("hello world");
        let log = event.as_mut_log();
        log.insert(log_schema().timestamp_key(), chrono::Utc::now());
        log.insert("name", "foo");
        log.insert("value", "bar");
        let record = encoder.encode_event(event);
        assert!(record.event.event.contains(log_schema().timestamp_key()));
        assert_eq!(record.labels.len(), 2);
        let labels: HashMap<String, String> = record.labels.into_iter().collect();
        assert_eq!(labels["static"], "value".to_string());
        assert_eq!(labels["foo"], "bar".to_string());
    }

    #[test]
    fn encoder_no_ts() {
        let encoder = EventEncoder {
            key_partitioner: KeyPartitioner::new(None),
            encoding: EncodingConfig::from(Encoding::Json),
            labels: HashMap::default(),
            remove_label_fields: false,
            remove_timestamp: true,
        };
        let mut event = Event::from("hello world");
        let log = event.as_mut_log();
        log.insert(log_schema().timestamp_key(), chrono::Utc::now());
        let record = encoder.encode_event(event);
        assert!(!record.event.event.contains(log_schema().timestamp_key()));
    }

    #[test]
    fn encoder_no_record_labels() {
        let mut labels = HashMap::default();
        labels.insert(
            Template::try_from("static").unwrap(),
            Template::try_from("value").unwrap(),
        );
        labels.insert(
            Template::try_from("{{ name }}").unwrap(),
            Template::try_from("{{ value }}").unwrap(),
        );
        let encoder = EventEncoder {
            key_partitioner: KeyPartitioner::new(None),
            encoding: EncodingConfig::from(Encoding::Json),
            labels,
            remove_label_fields: true,
            remove_timestamp: false,
        };
        let mut event = Event::from("hello world");
        let log = event.as_mut_log();
        log.insert(log_schema().timestamp_key(), chrono::Utc::now());
        log.insert("name", "foo");
        log.insert("value", "bar");
        let record = encoder.encode_event(event);
        assert!(!record.event.event.contains("value"));
    }

    #[tokio::test]
    async fn filter_encoder_drop() {
        let encoder = EventEncoder {
            key_partitioner: KeyPartitioner::new(None),
            encoding: EncodingConfig::from(Encoding::Json),
            labels: HashMap::default(),
            remove_label_fields: false,
            remove_timestamp: false,
        };
        let base = chrono::Utc::now();
        let events = random_lines(100)
            .take(20)
            .map(Event::from)
            .enumerate()
            .map(|(i, mut event)| {
                let log = event.as_mut_log();
                let ts = if i % 5 == 1 {
                    base
                } else {
                    base + chrono::Duration::seconds(i as i64)
                };
                log.insert(log_schema().timestamp_key(), ts);
                event
            })
            .collect::<Vec<_>>();
        let mut stream = futures::stream::iter(events);
        let filter = FilterEncoder::new(
            &mut stream,
            encoder,
            GlobalTimestamps::default(),
            OutOfOrderAction::Drop,
        );
        let result = collect(filter, 2).await;
        assert_eq!(result.len(), 17);
    }
}