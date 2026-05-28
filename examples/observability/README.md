# Observability

windows11-zombie ships with three opt-in observability hooks:

1. **`events.log`** — sibling of `audit.log` under `state/logs/`.
   Same JSONL shape but **outside** the hash chain — used for routine
   lifecycle events (service start/stop, config reload, queue depth).
2. **Prometheus `/metrics` endpoint** — set `ZOMBIE_METRICS=1` in
   the service environment to expose `/metrics` on the existing
   loopback port. Counters: `tool_invocations_total`, `policy_denies_total`,
   `http_requests_total`.
3. **Grafana dashboard** — minimal starter dashboard in
   `grafana-dashboard.json`. Import via Grafana UI: *Dashboards →
   New → Import*.

For OTLP/OpenTelemetry export, run a [Prometheus → OTLP](https://prometheus.io/docs/prometheus/latest/feature_flags/#otlp-receiver)
gateway or scrape `/metrics` with the OpenTelemetry Collector's
`prometheus` receiver. We do **not** ship an OTLP exporter in the agent
itself to keep the dependency footprint small.

## Scraping the loopback endpoint

Prometheus is typically on a separate host; the simplest pattern is to
run a small Windows Exporter sidecar that scrapes `127.0.0.1:7878` and
forwards to your central Prometheus over Tailscale / VPN.
