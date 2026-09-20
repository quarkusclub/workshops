# Créditos e licença

## De onde este workshop veio

Este material é uma **obra derivada** do
[quarkusio/quarkus-workshop-langchain4j](https://github.com/quarkusio/quarkus-workshop-langchain4j){target="_blank"},
criado e mantido pela comunidade Quarkus.

O crédito pelo desenho do workshop, pelo cenário da Miles of Smiles, pelos diagramas e pela maior parte do código é integralmente das pessoas listadas abaixo. O Quarkus Club traduziu, adaptou e reorganizou.

- **Commit base do fork:** `2a33c7204b1165b7187b927ea9d74ecb13b92c4e` (18 de setembro de 2026)
- **Licença:** [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0){target="_blank"}

## O que foi modificado

A Apache License 2.0, na seção 4(b), exige que obras derivadas declarem de forma clara quais arquivos foram alterados. Foram estas as mudanças:

| Mudança | Detalhe |
|---|---|
| Provider do LLM | De OpenAI para a API gratuita da NVIDIA (NIM). Em cada `application.properties`: `base-url`, `api-key` e `model-name` |
| Timeout | `quarkus.langchain4j.timeout=2m` em todos os steps. O padrão de 10s não sobrevive a um modelo que raciocina sobre um schema de tool, e o estouro aparece como WebSocket morto, não como erro |
| Idioma | Toda a documentação traduzida para português, mantendo a versão em inglês |
| Estrutura dos steps | Esqueleto fixo (objetivo, conceito, mão na massa, checkpoint, troubleshooting) e notas do apresentador |
| Novo Step 00 | Criação da chave da NVIDIA, que no original era pré-requisito e aqui é conteúdo |
| Escopo | Apenas a Section 1. As Sections 2 e 3 não foram portadas |
| Scripts de preparação | `prepare.sh` e `prepare.ps1`, que não existem no original |
| Identidade visual | Cores e tipografia do Quarkus Club |

O código Java, os `pom.xml`, os recursos de RAG e os diagramas permanecem como no original, salvo onde a tabela acima indica.

## Pessoas que construíram o original

Em ordem alfabética, a partir do histórico do repositório:

Ales Justin, Ardavan Ghaffari, Clement Escoffier, Daniel Oh, Don Bourne, Eric Deandrea,
Georgios Andrianakis, Guillaume Smet, Holly Cummins, Jan Martiska, Julio César, Julio Faerman,
Kevin Dubois, Mario Fusco, Martin Stefanko, Michal Broz, Ricardo Zanini,
Ronaldo Tavares da Silva, Thiago Rafael Ferreira, Toshiya Kobayashi.

!!! info "Quer contribuir com o original?"
    Melhorias que não sejam específicas da tradução ou da NVIDIA são muito mais úteis enviadas para o
    [repositório upstream](https://github.com/quarkusio/quarkus-workshop-langchain4j){target="_blank"}, onde alcançam muito mais gente.

## Marcas

Quarkus é uma marca da Red Hat, Inc. NVIDIA e NVIDIA NIM são marcas da NVIDIA Corporation. O Quarkus Club é um grupo de usuários independente, sem vínculo com a Red Hat ou com a NVIDIA, e nada aqui implica endosso de nenhuma das duas.

## Esta versão

Mantida pelo [Quarkus Club](https://quarkusclub.github.io){target="_blank"}, também sob Apache License 2.0.
Encontrou um erro? Abra uma issue em [quarkusclub/workshops](https://github.com/quarkusclub/workshops){target="_blank"}.
