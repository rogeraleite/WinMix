# Validação — volume por aba 0.5.0

Executada em 2026-11-06. App e extensão 0.5.0. Modo `automatic-sites`, com leitura
compatível do modo antigo `automatic-youtube`. Escopo do controlador: players HTML
em HTTP/HTTPS, com diagnóstico e mute para áudio sem player compatível.

## Resultados

| Verificação | Resultado |
| --- | --- |
| `swift test` | 17 aprovados; inclui coalescência do arraste, isolamento, erro, timeout, troca de sessão e desconexão. |
| `node --test Tests/ChromeExtension/*.test.mjs` | 17 aprovados; inclui fila independente por aba, barreira de restauração, inicialização HTTP, escopo, ganhos e playback. |
| Instalador Python | 2 aprovados. |
| Build release 0.5.0 | Aprovado, app e ponte assinados ad hoc. |
| Integração com app simulado | Aprovada, extensão e ponte reais em perfil temporário. |
| Integração com modelos nativos/Core Audio | Aprovada em saída explícita Microsoft Teams Audio. |
| Interface | Preview conectado inspecionado; sliders, percentuais e mensagens sem cortes. |
| Chrome pessoal e serviços reais | Aguardam recarga da extensão e novo acesso aos sites pelo usuário. |

## Evidências

Chrome for Testing 148.0.7778.96, perfil/socket temporários. Fixtures HTTP/HTTPS locais,
sem popup ou ação por aba e sem acessar a sessão pessoal.

- Três abas detectadas automaticamente: YouTube, YouTube Music e outro domínio HTTP.
- Ganhos 30% e 70% resultam em volumes nativos HTML 0.240 e 0.420, com volumes do site
  0.800 e 0.600. A terceira aba em 55% resulta em 0.440.
- Arraste nativo 20%, 40%, 60%, 80% confirma 80%; player da terceira aba termina em 0.640.
- Navegação da terceira aba HTTP para outro domínio HTTPS conserva o ganho de 55%.
- Pausa/mute não removem a aba, não afetam outra aba e mantêm ganhos independentes.
- Players dinâmicos e frame autorizado herdam o ganho; Play não inicia elementos apenas
  pré-carregados. Rejeição de Play mantém estado real e propaga diagnóstico.
- Web Audio sem elemento HTML é detectado como volume indisponível e aceita mute.
- Recarga da extensão reconecta páginas existentes; encerrar restaura volumes sem
  reiniciar players pausados nem interromper os que continuam tocando.
- Testes de fila demonstram que um player bloqueado não bloqueia comandos em outra aba,
  e que restauração aguarda comandos anteriores.

## Falhas encontradas durante a implementação

O primeiro teste HTTP revelou uso de `crypto.randomUUID` fora de contexto seguro. Um teste
reproduziu `crypto.randomUUID is not a function`; a ponte passou a usar `getRandomValues`
e o cenário HTTP passou. O slider também permanece disponível durante confirmações
intermediárias dos frames, sem perder o último valor solicitado.

Uma tentativa de integração expirou na conexão inicial. O helper de teste substituía o
alarme periódico de reconexão por um único disparo durante o registro do host. Ele agora
preserva a periodicidade e aguarda o intervalo de reconexão. As integrações simulada e
nativa passaram; não foi necessário mudar o mecanismo de reconexão de produção.

## Core Audio

Somente Chrome for Testing, defaults privados e saída `MSLoopbackDriverDevice_UID`.
Não houve mudança de saída padrão nem dos volumes salvos do usuário.

| Etapa | Entrada | Saída | Razão |
| --- | --- | --- | --- |
| Abas com mestre em 50% | 0.0000568 | 0.0000284 | 0.500 |
| Player em 100%, mestre em 50% | 0.0001000 | 0.0000500 | 0.500 |
| Player em 30%, mestre em 50% | 0.0000300 | 0.0000150 | 0.500 |

São leituras digitais, não medição acústica ou prova de ausência de transientes.

## Instalação local

App 0.5.0 instalado e aberto no caminho já registrado `build/MacVolume.app`. A cópia
0.4.0 foi preservada em `build/MacVolume.backup-0.4.0-01e91eb.app`. Os arquivos da
extensão empacotada conferem byte a byte com `Extensions/Chrome`. A interface real
mostrou **Extension update required** com a extensão pessoal antiga ainda conectada.
Nenhuma ampliação de acesso no perfil pessoal foi concedida automaticamente.

## Limites e ativação

A cobertura é de players compatíveis; não inclui grafos Web Audio arbitrários, arquivos,
páginas internas ou Web Store. Em páginas com fontes mistas, o ganho HTML não garante
cobertura de todo áudio. Não foi validado o piso Chrome 116/macOS 14.4 neste equipamento.

Reabrir o app 0.5.0, recarregar MacVolume Tabs em `chrome://extensions` e autorizar o
acesso HTTP/HTTPS e `tabs`. A concessão pessoal deve ser feita pelo usuário. O app mostra
**Extension update required** enquanto a extensão antiga continuar conectada. Conferir
serviços reais, permissões retidas, suspensão, chamadas e falhas abruptas pelo
[roteiro manual](chrome-manual-validation.md).

Histórico: [0.4.0](history/chrome-tab-validation-0.4.md),
[0.3.0](history/chrome-tab-validation-0.3.md), [0.2.x](history/chrome-tab-validation-0.2.md).
