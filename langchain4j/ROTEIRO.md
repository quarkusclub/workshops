# Roteiro do apresentador

**Quarkus LangChain4j Workshop: Integrando aplicações Java com LLMs - Production Grade**
Duração: 1h30. Slides: `slides/index.html` (PT) e `slides/en.html` (EN).

Apertando **S** nos slides abre a janela de notas do apresentador, com timer e próximo slide.
Compartilhe a **janela do deck**, não a tela inteira, senão as notas aparecem.

## Cronograma de 90 minutos

| Início | Duração | Bloco | Modo |
|---|---|---|---|
| 00:00 | 5 min | Abertura, o problema, Quarkus Club, agenda | |
| 00:05 | 7 min | Step 00 Chave da NVIDIA | mão na massa |
| 00:12 | 11 min | Step 01 Primeiro AI Service | mão na massa |
| 00:23 | 4 min | Step 02 Parâmetros do modelo | demo |
| 00:27 | 3 min | Step 03 Streaming | demo |
| 00:30 | 4 min | Step 04 System message | mão na massa |
| 00:34 | 13 min | Step 05 RAG com EasyRAG | mão na massa |
| 00:47 | 5 min | Step 06 EasyRAG por dentro | demo |
| 00:52 | 13 min | Step 07 Function calling e tools | mão na massa |
| 01:05 | 7 min | Step 08 MCP | demo |
| 01:12 | 8 min | Step 09 Guardrails | demo |
| 01:20 | 5 min | Step 10 Observabilidade | demo |
| 01:25 | 5 min | Fechamento e perguntas | |

Anuncie o modo na abertura. A sala precisa saber quando digita e quando só assiste,
senão metade fica para trás tentando acompanhar o que era demonstração.

## Checklist da véspera

- [ ] Rodar `scripts/prepare.sh` na **sua** máquina e confirmar `READY`
- [ ] Gerar de 2 a 3 chaves reserva da NVIDIA em uma conta sua
- [ ] **Confirmar que o modelo do `application.properties` ainda existe.** Modelos saem do
      catálogo: rode uma chamada de teste com tool calling na véspera
- [ ] Testar a conversa do Step 07 de ponta a ponta, incluindo criar e cancelar reserva
- [ ] Baixar a imagem `pgvector/pgvector:pg17`
- [ ] Enviar o link de preparação para os inscritos
- [ ] Preparar hotspot de celular como rede reserva

## Checklist do dia

- [ ] Chegar cedo e testar o wi-fi com o `curl` do Step 00
- [ ] `export NVIDIA_API_KEY` feito no terminal que você vai projetar
- [ ] Deck aberto em **janela separada** da janela de notas
- [ ] Combinar sinal de mão levantada para "terminei" e "travei"

## Ritmo

A primeira chamada ao modelo é lenta (por volta de 30 segundos, entre JVM fria e modelo frio).
As seguintes ficam em 1 a 3 segundos. Avise a sala, senão todo mundo acha que travou.

Uma chamada com tools custa dois round trips ao modelo, então de 15 a 30 segundos é normal
nos steps 07 em diante.

## O que cortar quando o tempo apertar

1. **Step 06** vira um slide só, o da distinção EasyRAG contra RAG explícito. Economiza 4 min.
2. **Step 10** vira menção de 1 minuto com o slide de métricas. Economiza 4 min.
3. **Step 08** vira demonstração na sua tela sem esperar a sala. Economiza 4 min.

Não corte 01, 05, 07 e 09: são integração, contexto, ação e segurança, a espinha do título.

## Contingência

| Problema | Resposta |
|---|---|
| Modelo sumiu do catálogo | Trocar `model-name` no `application.properties`, é uma linha |
| Wi-fi do local caiu | Hotspot para você, a sala acompanha sua tela |
| Muita gente sem chave | Distribuir as reservas, resolver depois |
| API lenta ou instável | Seguir pelo código pronto de cada step e mostrar os logs |
| Sala atrasada | Plano de cortes acima, não acelere a fala |

## Depois

- [ ] Compartilhar o link do deck e do repositório
- [ ] Recolher feedback enquanto está fresco
- [ ] Abrir issues no repositório para o que travou a sala
- [ ] Mandar upstream o que for correção genérica
