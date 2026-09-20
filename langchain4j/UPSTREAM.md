# Upstream tracking

This workshop is a fork of
[quarkusio/quarkus-workshop-langchain4j](https://github.com/quarkusio/quarkus-workshop-langchain4j).

| | |
| --- | --- |
| Fork base commit | `2a33c7204b1165b7187b927ea9d74ecb13b92c4e` |
| Fork base date | 2026-09-18 |
| Scope taken | Section 1 only, steps 01 to 10 plus the MCP server |
| Scope skipped | Section 2, Section 3, `section-1/step-11` (Jlama), RHEL setup |
| Licence | Apache License 2.0 |

See [`../NOTICE`](../NOTICE) for the formal statement of modifications.

## Re-syncing with upstream

```bash
git -C /path/to/quarkus-workshop-langchain4j fetch origin
git -C /path/to/quarkus-workshop-langchain4j log --oneline 2a33c72..origin/main -- section-1 docs/docs/section-1
```

Review that range and port what is relevant. Update the base commit in this file and in
`NOTICE` when you do.

## Known upstream defects

Found while porting, reported here so they are not lost. The plan is to fix them here and
send the generic ones upstream.

### 1. Dead OpenTelemetry configuration keys in step-09

`section-1/step-09` sets three properties that Quarkus 3.39.3 reports as unrecognised and
ignores:

```
quarkus.otel.logs.enabled
quarkus.otel.traces.enabled
quarkus.otel.exporter.otlp.traces.headers
```

The keys themselves are fine. The cause is that `step-09/pom.xml` has **no observability
dependency at all**, so nothing claims them. Building upstream unmodified at its own fork
commit shows the split precisely: step-09 emits all three warnings, and step-10, which
declares the same `quarkus.otel.*` keys but does carry `quarkus-opentelemetry`, emits none.

This makes defect 1 and defect 6 the same defect seen twice: step-09 carries observability
configuration one step before the extension that would give it meaning.

Same sweep, same Quarkus version, `section-1/step-11` (Jlama, not ported here) has eight
dead keys, four of them `quarkus.langchain4j.jlama.*`. Recorded as observed, not diagnosed.

Impact: the observability step teaches configuration that does nothing. Quarkus only warns,
so a green CI never catches it.

The third key carries a second problem. Its committed value is
`authorization=Bearer my_secret`, so the step models putting a bearer token straight into
`application.properties`. It is a placeholder, and the key is dead anyway, but it is still
the pattern a reader copies. The fix upstream is the same as here: drop the block, and
where such a header is genuinely needed, read it from the environment.

### 2. Dead reference to a missing image

`docs/docs/section-1/step-10.md` line 11 references `images/observability.png`, which does
not exist in the repository. The reference sits inside an HTML comment, so it does not
render as a broken image. Minor, but it breaks the page for anyone who uncomments it.

### 3. MCP documentation contradicts the working code

`docs/docs/section-1/step-08.md` instructs the reader to use values that do not match the
code in the same repository:

| The doc says | The working code uses |
| --- | --- |
| `-x quarkus-mcp-server-sse` | `quarkus-mcp-server-http` |
| `transport-type=http` | `transport-type=streamable-http` |
| `url=http://localhost:8081/mcp/sse/` | `url=http://localhost:8081/mcp` |

Impact: the highest of the three. Following the text literally, the MCP client cannot
connect, and steps 09 and 10 both depend on that server running. This fork documents the
values from the working code.

### 4. `@Timeout(5000)` in step-10 cannot be met

`CustomerSupportAgent` in step-10 declares `@Timeout(5000)` with `@Retry(maxRetries = 3)`.
That method is not one model call, it is a chain: a guardrail LLM round trip, a vector
search, then the main call generating a long answer. Measured end to end it takes about
34 seconds, so at 5s the step only ever demonstrates its own fallback. Observed: 137
seconds before the user saw the fallback message.

Raw provider latency is not the cause. A single warm call takes about 1 second.

Fixed here as `@Timeout(60000)` and `@Retry(maxRetries = 1, delay = 2000)`, with the
reasoning in a comment. Aggressive retry over a slow call is how a timeout becomes a 429.

### 5. `quarkus.langchain4j.timeout` left at its 10s default

Only steps 01 and 08 override it upstream. Every other step inherits 10 seconds, which no
call carrying a tool schema survives. Over a WebSocket the timeout does not surface as a
chat error, it kills the connection, so the attendee sees a frozen page with nothing in
the browser explaining why.

Fixed here as `timeout=2m` in the ten projects that talk to a model.

### 6. The traceId lesson sits one step too early

step-09 set `quarkus.log.console.format` with `%X{traceId}` while having no OpenTelemetry
extension, so the field was always empty. step-10, which has the extension and whose
documentation says "notice the traceId", did not set the format at all.

Fixed here by moving the log format to step-10, where it now resolves.

### 7. The step-10 metrics example cannot be reproduced from the step-10 instructions

`docs/docs/section-1/step-10.md` tells the reader to add only
`quarkus-micrometer-opentelemetry`, then shows this as the expected output:

```
# HELP langchain4j_aiservices_seconds_max
langchain4j_aiservices_seconds_count{aiservice="CustomerSupportAgent",method="chat",} 1.0
langchain4j_aiservices_seconds_sum{aiservice="CustomerSupportAgent",method="chat",} 2.485171837
```

Two separate problems.

First, that text is Prometheus scrape output (the `# HELP` and `# TYPE` lines, and the
trailing comma before the closing brace, are the Micrometer Prometheus registry's format).
`quarkus-micrometer-opentelemetry` ships metrics over OTLP and exposes no scrape endpoint,
so `GET /q/metrics` returns **404**. Reproducing the block needs
`quarkus-micrometer-registry-prometheus`, which the page never mentions.

Second, the metric names are stale. Measured against quarkus-langchain4j 1.14.0.CR3:

| Shown upstream | Actually emitted |
| --- | --- |
| `langchain4j_aiservices_seconds_count` | `langchain4j_aiservices_timed_seconds_count` |
| `langchain4j_aiservices_seconds_sum` | `langchain4j_aiservices_timed_seconds_sum` |
| `langchain4j_aiservices_seconds_max` | `langchain4j_aiservices_timed_seconds_max` |
| not shown | `langchain4j_aiservices_counted_total` |

A query for `langchain4j_aiservices_seconds_count` returns an empty vector.

Worth knowing: the unit depends on the exporter. Through the Prometheus registry the
series are in **seconds**; the same metrics arriving in the LGTM Grafana through OTLP are
named `langchain4j_aiservices_timed_milliseconds_*`. Reading one as the other is a
factor-of-1000 error.

Fixed here by adding the Prometheus registry to `section-1/step-10/pom.xml` and
regenerating the slide from a real run.

### 8. Step 07 silently breaks the build for anyone who did step 03

Step 07 reverts `CustomerSupportAgent.chat()` from `Multi<String>` to `String`, but nothing
in `docs/docs/section-1/step-07.md` says to revert `CustomerSupportAgentWebSocket` as well.
Anyone who followed step 03 hits:

```
incompatible types: java.lang.String cannot be converted to io.smallrye.mutiny.Multi<java.lang.String>
```

The finished `step-07` sources are correct, so the defect is only in the written path: it
hits exactly the readers who typed along instead of copying the folder. It also drops
streaming for the rest of Section 1 without ever saying so.

### 9. Two documented request bodies show a field the code no longer sends

`docs/docs/section-1/step-06.md` (line 351) and `docs/docs/section-1/step-10.md` (line 67)
paste a captured request body that contains:

```
  "max_tokens" : 1000,
```

Every `application.properties` upstream sets `max-completion-tokens=1000`, and that property
puts `max_completion_tokens` on the wire, not `max_tokens`. Thirteen request bodies captured
from runs here show the current field with the same value:

```
"max_completion_tokens" : 1000
```

So the two samples were captured back when the config used `max-tokens`, and were never
refreshed. `max-tokens` is now deprecated in the extension:

```java
/**
 * @deprecated For newer OpenAI models, use {@code maxCompletionTokens} instead
 */
@Deprecated
Optional<Integer> maxTokens();
```

Worth knowing while hunting for others: **a deprecated config key does not warn at build
time.** `mvn package` on a project that sets `max-tokens` prints nothing. The warning only
appears when the application starts:

```
WARN [io.quarkus.config] The "quarkus.langchain4j.openai.chat-model.max-tokens"
config property is deprecated and should not be used anymore.
```

Scanning the extension bytecode for `@Deprecated` config methods and grepping the workshop
for each one, no `application.properties` upstream uses a deprecated key. These two
documentation samples are the whole of it. The step-10 sample is visibly old in other ways
too: `"model" : "gpt-4o"` and `Today is 2025-01-10`.

### Not a defect, but a trap when reusing regions

`RagRetriever.java` has three regions and `ragretriever-2` contains only `.build(); } }`,
the tail of the method. The documentation always concatenates region 1 with region 2.
Including region 2 alone renders a meaningless fragment.

### Models leave the catalogue

The single most likely way this workshop breaks. A model name pinned in
`application.properties` has a silent expiry date: `meta/llama-3.3-70b-instruct` now
returns HTTP 410, end of life 26 August 2026.

Worth proposing upstream: a line in the README telling presenters to revalidate the model
before each delivery, since it is the most probable failure and the least obvious.

Choosing a replacement needs more than one call. Of eight candidates tested five times
each, `mistral-nemotron` passed tool calling once and failed the next five; the smaller
Nemotron reasoning models leak chain-of-thought into `content`, which breaks both the chat
and a guardrail typed as `double`; and `gpt-oss-20b` was fast and consistent but scored the
prompt injection at 0.00 to 0.05, meaning it does not detect the attack at all.

## Port hazard, not an upstream defect

`section-1/step-05` declared no in-process embedding model, so `easy-rag` fell back to the
embedding model provided by the `quarkus-langchain4j-openai` extension. Harmless upstream;
with `base-url` repointed at NVIDIA it would request an OpenAI embedding model name from
NVIDIA's catalogue and fail at ingestion. `mvn verify` passes, because the break is a
runtime model lookup.

Fixed here by adding `langchain4j-embeddings-bge-small-en-q`, matching steps 06 to 10.

General lesson: repointing a provider through `base-url` is only safe for the calls you
enumerated. A provider serves several kinds of model (chat, embeddings, reranking, vision),
each with its own default that may not exist at the destination.

## Deliberate divergences from upstream

These are choices, not defects. They will conflict on re-sync, so they are recorded
here rather than discovered later.

### `RagRetriever` ships the main-path version, not the Advanced RAG one

Upstream's `step-06/.../RagRetriever.java` is split into three regions, and its written
guide renders two different programs from that one file:

    main lesson ("The retriever and augmentor")  ->  ragretriever-1 + ragretriever-2
    optional section ("Advanced RAG")            ->  ragretriever-1 + 3 + 2

Region 3 is an anonymous `ContentInjector` that rewrites the user message by hand,
appending `"Please, only use the following information:"` and each retrieved segment.
It belongs to the optional section, which upstream explicitly frames as "just to give
an example" of extending the pattern.

The file on disk holds the post-Advanced-RAG end state. Our deck loaded that file whole,
with no `data-region`, so the slide presented the advanced variant as if it were the
baseline. Steps 07 to 10 carry the same end state forward.

Our steps 06 to 10 now ship the main-path version: retriever plus
`DefaultRetrievalAugmentor.builder().contentRetriever(...).build()`. The injector is
presented on its own slide as the optional path it is, which is upstream's own pedagogy.
That also keeps all five steps behaviourally identical, where upstream silently changes
behaviour between the lesson a reader follows and the files steps 07 to 10 contain.

Region markers went with it, since the three-part split no longer has three parts.

Reference: https://quarkus.io/quarkus-workshop-langchain4j/section-1/step-06/#advanced-rag

Affected files, all five identical:

    section-1/step-{06,07,08,09,10}/src/main/java/dev/langchain4j/quarkus/workshop/RagRetriever.java

Verified with `./mvnw -o -pl section-1/step-06,...,section-1/step-10 compile`, exit 0.
