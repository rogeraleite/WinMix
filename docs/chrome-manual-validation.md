# Validação no Chrome pessoal — 0.5.0

Atualizado em 2026-11-06. As fixtures automatizadas usam perfil separado; não substituem
esta validação em serviços reais. A extensão pessoal ainda precisa receber o novo acesso.

## Ativação

1. Abrir MacVolume 0.5.0.
2. Recarregar MacVolume Tabs em `chrome://extensions`.
3. Autorizar o novo acesso aos sites HTTP/HTTPS e aos metadados das abas.
4. Conferir acesso automático aos sites; recarregar uma vez páginas antigas se necessário.

## Cenários

| Cenário | Resultado esperado | Estado |
| --- | --- | --- |
| Duas abas reais em sites distintos | Duas linhas e ganhos independentes, sem abrir popup. | Pendente após concessão de acesso. |
| Arraste contínuo | Slider permanece ativo; valor final é confirmado. | Testado no modelo/fixtures; falta gesto na sessão pessoal. |
| Abas já abertas e nova aba em segundo plano | Descoberta automática ao tocar áudio. | Confirmar no perfil pessoal após atualizar. |
| Volume no site + volume da aba | Ganhos multiplicados uma vez, sem acumular. | Confirmar com os players reais. |
| Pausa/mute/ganho zero | Linha permanece; play/pause não altera volume/mute. | Confirmar nos serviços reais. |
| Sem acesso ao site | Aba audível com diagnóstico e mute; sem falso slider. | Confirmar ao reter acesso no Chrome pessoal. |
| Web Audio sem HTML audio/video | Diagnóstico de volume indisponível, mute funciona. | Caso negativo em fixture; confirmar variantes reais. |
| Página interna/Web Store/arquivo | Sem promessa de slider funcional; sem injeção nesses contextos. | Escopo coberto por teste; audibilidade depende da página. |
| Troca de saída/suspensão/AirPods em chamada | Recuperação e ganhos preservados ou erro visível. | Pendente no modo 0.5.0. |
| Encerramento normal | Volume original restaurado sem mudar play/pause. | Fixture; confirmar na sessão pessoal. |
| Falhas abruptas | Conferir restauração/reconexão sem presumir preservação. | Pendente. |
| Chrome 116/macOS 14.4 | Compatibilidade no piso declarado. | Não executado neste Mac. |

Registrar versão, dispositivo, etapa, resultado e erro visível. Não registrar títulos/URLs
privados nem áudio de chamadas. Histórico de fixtures em `history/`.
