# Validação no Chrome pessoal — 0.5.0

Atualizado em 2026-11-06. As fixtures automatizadas usam perfil separado; não substituem
esta validação em serviços reais. Extensão pessoal 0.5.0 recarregada após autorização
do usuário, com **On all sites** confirmado e conexão no modo novo.

## Ativação

1. Abrir MacVolume 0.5.0.
2. Recarregar MacVolume Tabs em `chrome://extensions`.
3. Autorizar o novo acesso aos sites HTTP/HTTPS e aos metadados das abas.
4. Conferir acesso automático aos sites; recarregar uma vez páginas antigas se necessário.

## Cenários

| Cenário | Resultado esperado | Estado |
| --- | --- | --- |
| Duas abas reais do YouTube | Duas linhas e ganhos independentes, sem abrir popup. | Aprovado: 30% e 70% confirmados; ganhos restaurados a 100% ao terminar. |
| Duas abas reais em sites distintos | Duas linhas e ganhos independentes, sem abrir popup. | Fixtures aprovadas; confirmar outros serviços reais. |
| Arraste contínuo | Slider permanece ativo; valor final é confirmado. | Testado no modelo/fixtures; falta gesto na sessão pessoal. |
| Abas já abertas e nova aba em segundo plano | Descoberta automática ao tocar áudio. | Duas abas existentes do YouTube aprovadas, sem recarga das páginas. Nova aba em segundo plano coberta por fixtures. |
| Volume no site + volume da aba | Ganhos multiplicados uma vez, sem acumular. | Confirmar com os players reais. |
| Pausa/mute/ganho zero | Linha permanece; play/pause não altera volume/mute. | Pausa pelo app e retenção das duas linhas aprovadas no YouTube real. Mute/ganho zero permanecem cobertos por fixtures. |
| Sem acesso ao site | Aba audível com diagnóstico e mute; sem falso slider. | Confirmar ao reter acesso no Chrome pessoal. |
| Web Audio sem HTML audio/video | Diagnóstico de volume indisponível, mute funciona. | Caso negativo em fixture; confirmar variantes reais. |
| Página interna/Web Store/arquivo | Sem promessa de slider funcional; sem injeção nesses contextos. | Escopo coberto por teste; audibilidade depende da página. |
| Troca de saída/suspensão/AirPods em chamada | Recuperação e ganhos preservados ou erro visível. | Pendente no modo 0.5.0. |
| Encerramento normal | Volume original restaurado sem mudar play/pause. | Fixture; confirmar na sessão pessoal. |
| Falhas abruptas | Conferir restauração/reconexão sem presumir preservação. | Pendente. |
| Chrome 116/macOS 14.4 | Compatibilidade no piso declarado. | Não executado neste Mac. |

Registrar versão, dispositivo, etapa, resultado e erro visível. Não registrar títulos/URLs
privados nem áudio de chamadas. Histórico de fixtures em `history/`.
