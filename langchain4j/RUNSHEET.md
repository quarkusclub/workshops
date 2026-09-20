# Presenter run sheet

**Quarkus LangChain4j Workshop: Integrating Java applications with LLMs - Production Grade**
Length: 1h30. Slides: `slides/en.html` (EN) and `slides/index.html` (PT).

Pressing **S** in the deck opens the presenter notes window, with a timer and the next slide.
Share the **deck window**, not your whole screen, or the notes show up.

## 90 minute timeline

| Start | Length | Block | Mode |
|---|---|---|---|
| 00:00 | 5 min | Opening, the problem, Quarkus Club, agenda | |
| 00:05 | 7 min | Step 00 NVIDIA key | hands-on |
| 00:12 | 11 min | Step 01 First AI Service | hands-on |
| 00:23 | 4 min | Step 02 Model parameters | demo |
| 00:27 | 3 min | Step 03 Streaming | demo |
| 00:30 | 4 min | Step 04 System message | hands-on |
| 00:34 | 13 min | Step 05 RAG with EasyRAG | hands-on |
| 00:47 | 5 min | Step 06 EasyRAG from the inside | demo |
| 00:52 | 13 min | Step 07 Function calling and tools | hands-on |
| 01:05 | 7 min | Step 08 MCP | demo |
| 01:12 | 8 min | Step 09 Guardrails | demo |
| 01:20 | 5 min | Step 10 Observability | demo |
| 01:25 | 5 min | Wrap-up and questions | |

Announce the mode in the opening. The room needs to know when to type and when to
watch, or half of them fall behind on something that was meant to be a demo.

## The day before

- [ ] Run `scripts/prepare.sh` on **your** machine and confirm `READY`
- [ ] Generate 2 or 3 spare NVIDIA keys on an account of yours
- [ ] **Confirm the model in `application.properties` still exists.** Models leave the
      catalogue: run a test call with tool calling the day before
- [ ] Test the Step 07 conversation end to end, creating and cancelling a booking
- [ ] Pull the `pgvector/pgvector:pg17` image
- [ ] Send the preparation link to registered attendees
- [ ] Prepare a phone hotspot as a backup network

## On the day

- [ ] Arrive early and test the wifi with the Step 00 `curl`
- [ ] `export NVIDIA_API_KEY` done in the terminal you will project
- [ ] Deck open in a **separate window** from the notes window
- [ ] Agree a raised-hand signal for "done" and "stuck"

## Pace

The first model call is slow (around 30 seconds, cold JVM plus cold model). The ones
after land in 1 to 3 seconds. Warn the room or everyone thinks it hung.

A call with tools costs two round trips to the model, so 15 to 30 seconds is normal
from step 07 onward.

## What to cut when time runs short

1. **Step 06** becomes a single slide, the EasyRAG versus explicit RAG distinction. Saves 4 min.
2. **Step 10** becomes a one minute mention with the metrics slide. Saves 4 min.
3. **Step 08** becomes a demo on your screen without waiting for the room. Saves 4 min.

Do not cut 01, 05, 07 and 09: integration, context, action and safety, the spine of the title.

## Contingency

| Problem | Response |
|---|---|
| Model gone from the catalogue | Change `model-name` in `application.properties`, one line |
| Venue wifi dies | Hotspot for you, the room follows your screen |
| Many people without a key | Hand out the spares, fix it later |
| API slow or flaky | Walk the finished code of each step and show the logs |
| Room behind | Use the cut plan above, do not talk faster |

## Afterwards

- [ ] Share the deck and repository links
- [ ] Collect feedback while it is fresh
- [ ] Open issues for whatever blocked the room
- [ ] Send upstream anything that is a generic fix
