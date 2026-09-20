# Credits and licence

## Where this workshop came from

This material is a **derivative work** of
[quarkusio/quarkus-workshop-langchain4j](https://github.com/quarkusio/quarkus-workshop-langchain4j){target="_blank"},
created and maintained by the Quarkus community.

Credit for the workshop design, the Miles of Smiles scenario, the diagrams and most of the code belongs entirely to the people listed below. Quarkus Club translated, adapted and reorganised it.

- **Fork base commit:** `2a33c7204b1165b7187b927ea9d74ecb13b92c4e` (18 September 2026)
- **Licence:** [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0){target="_blank"}

## What was modified

Section 4(b) of the Apache License 2.0 requires derivative works to state clearly which files were changed. These are the changes:

| Change | Detail |
|---|---|
| LLM provider | From OpenAI to the free NVIDIA API (NIM). In every `application.properties`: `base-url`, `api-key` and `model-name` |
| Timeout | `quarkus.langchain4j.timeout=2m` in every step. The 10s default does not survive a model that reasons over a tool schema, and the overrun shows up as a dead WebSocket rather than an error |
| Language | All documentation translated to Portuguese, with the English version kept |
| Step structure | Fixed skeleton (goal, concept, hands-on, checkpoint, troubleshooting) plus presenter notes |
| New Step 00 | Creating the NVIDIA key, a prerequisite upstream and content here |
| Scope | Section 1 only. Sections 2 and 3 were not ported |
| Preparation scripts | `prepare.sh` and `prepare.ps1`, which do not exist upstream |
| Visual identity | Quarkus Club colours and typography |

The Java code, the `pom.xml` files, the RAG resources and the diagrams remain as in the original, except where the table above says otherwise.

## The people who built the original

Alphabetically, from the repository history:

Ales Justin, Ardavan Ghaffari, Clement Escoffier, Daniel Oh, Don Bourne, Eric Deandrea,
Georgios Andrianakis, Guillaume Smet, Holly Cummins, Jan Martiska, Julio César, Julio Faerman,
Kevin Dubois, Mario Fusco, Martin Stefanko, Michal Broz, Ricardo Zanini,
Ronaldo Tavares da Silva, Thiago Rafael Ferreira, Toshiya Kobayashi.

!!! info "Want to contribute to the original?"
    Improvements that are not specific to this translation or to NVIDIA are far more useful sent to the
    [upstream repository](https://github.com/quarkusio/quarkus-workshop-langchain4j){target="_blank"}, where they reach many more people.

## Trademarks

Quarkus is a trademark of Red Hat, Inc. NVIDIA and NVIDIA NIM are trademarks of NVIDIA Corporation. Quarkus Club is an independent user group, unaffiliated with Red Hat or NVIDIA, and nothing here implies endorsement by either.

## This version

Maintained by [Quarkus Club](https://quarkusclub.github.io){target="_blank"}, also under the Apache License 2.0.
Found a mistake? Open an issue at [quarkusclub/workshops](https://github.com/quarkusclub/workshops){target="_blank"}.
