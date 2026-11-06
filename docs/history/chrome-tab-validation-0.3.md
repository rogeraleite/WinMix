# Validação — modo automático 0.3.0

Executada em 2026-11-05. App e extensão 0.3.0; protocolo local versão 1, com campos opcionais
para modo automático e capacidade de mute. O usuário aprovou somente YouTube e YouTube Music.

**Código e automação aprovados.** A extensão instalada no Chrome pessoal precisa ser recarregada
uma vez para adotar o novo manifest e as permissões. Não há ativação de abas individuais.
A checagem no serviço real e no perfil pessoal após essa atualização ainda é uma etapa separada.

## Verificações concluídas

| Verificação | Resultado |
| --- | --- |
| `swift test` | 13 testes aprovados, incluindo confirmação/timeout, mute sem volume e compatibilidade do protocolo |
| `node --test Tests/ChromeExtension/*.test.mjs` | 8 testes aprovados: composição de ganho, volume do site, players novos, reset, protocolo e restrição de origens |
| `python3 -m unittest discover -s Tests -p 'test_*.py'` | 2 testes aprovados: registro/atualização/remoção e proteção contra symlinks |
| Integração com app simulado | Aprovada sem popup ou ação da extensão |
| Integração com modelos/tap nativos | Aprovada com `ChromeTabModel`, `MixerModel` e Core Audio reais |
| Interface | Preview conectada/desconectada inspecionada; estado de mute sem slider falso |
| Permissões | Somente quatro origens HTTPS YouTube; sem `tabs`, `<all_urls>`, `activeTab`, `tabCapture`, `offscreen` ou `debugger` |

## O que o teste de navegador realmente cobre

O teste usa Chrome for Testing 148.0.7778.96, perfil e socket temporários. Páginas HTTPS com
hosts `www.youtube.com` e `music.youtube.com` são respondidas por fixtures locais. Uma página
`example.com` verifica a exclusão. Não são páginas do YouTube real nem uma sessão autenticada;
os dados abaixo não devem ser apresentados como validação do serviço em produção.

Nenhum popup é aberto e nenhuma ação da extensão é invocada. As páginas iniciam áudio e
aparecem automaticamente no estado enviado ao app. O teste confirma o valor nativo de
`HTMLMediaElement.volume`, separado do getter do site:

| Caso | Volume do site | Ganho da aba | Volume nativo do elemento |
| --- | --- | --- | --- |
| Aba YouTube | 0,800 | 0,300 | 0,240 |
| Aba YouTube Music | 0,600 | 0,700 | 0,420 |
| Site altera seu volume | 0,500 | 0,300 | 0,150 |
| Comando repetido | 0,500 | 0,300 | 0,150 |
| Player criado depois | 0,400 | 0,300 | 0,120 |
| Navegação na mesma aba | 0,800 | 0,300 | 0,240 |
| Após recarregar extensão e reaplicar ganho | 0,800 | 0,450 | 0,360 |
| Encerramento normal do app | 0,800 | 1,000 | 0,800 |

Também passaram: mute independente, linha preservada após pausa/mute, limpeza ao fechar aba,
comando de sessão expirada rejeitado, reconexão da ponte sem perder ganho, página fora da lista
sem controlador, player Web Audio sem slider falso e mute ainda funcional. A recarga da extensão
reconectou a página já aberta sem recarregar a página ou clicar no popup.

## Medição no Core Audio real

O modo `--native` controla apenas o Chrome for Testing, usa defaults privados e uma saída
explícita. A saída padrão e os volumes salvos do usuário permanecem inalterados. Resultado
final com Microsoft Teams Audio:

| Etapa | Pico na entrada do tap | Pico na saída | Saída/entrada |
| --- | --- | --- | --- |
| Duas abas + mestre 50% | 0,0000565 | 0,0000283 | 0,500 |
| Um player em 100% | 0,0001000 | 0,0000500 | 0,500 |
| Mesmo player em 30% | 0,0000300 | 0,0000150 | 0,500 |
| Rota para caixas do Mac | 0,0000741 | 0,0000370 | 0,500 |

O sinal do player em 30% foi 0,300 do sinal de referência, e o mestre multiplicou novamente
por 0,500. Isso confirma o ganho no áudio, além dos valores de interface. A análise lê buffers,
não faz uma medição acústica ou prova de ausência de cliques/transientes de navegação.
Uma tentativa de percorrer também os AirPods encontrou o UID indisponível durante a execução;
esse caso não foi declarado aprovado nesta versão.

## Infraestrutura de teste e limites

A carga apenas por flag de linha de comando deixava o perfil descartável sem Modo do
desenvolvedor. Ao recarregar, o Chrome desativava a extensão com o motivo
`DISABLE_UNSUPPORTED_DEVELOPER_EXTENSION`. O teste final usa a API oficial
`Extensions.loadUnpacked` do Chrome for Testing, que identifica a instalação de teste.
Não houve mudança nas preferências do Chrome pessoal nem tentativa de contornar o bloqueio
de `chrome://extensions` da ferramenta.

O processo de fundo registra os eventos de instalação/atualização e de abertura do navegador
para inicializar a descoberta. Conteúdos já abertos recebem bootstrap no documento principal;
novos frames autorizados recebem os scripts declarados. Grafos Web Audio arbitrários e players
sem elemento de áudio/vídeo compatível não são anunciados como controláveis por volume.

Os testes de captura da implementação 0.2.x estão preservados em
[histórico 0.2](history/chrome-tab-validation-0.2.md). Esse fluxo manual foi substituído e seus
arquivos de execução foram removidos. O [roteiro atual](chrome-manual-validation.md) mantém
as checagens do serviço real, suspensão real, chamadas, falhas abruptas e ambiente mínimo.
