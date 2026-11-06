> Histórico de 0.2.x. O fluxo de captura descrito aqui foi substituído pelo modo automático em 0.3.0.

# Validação do controle de abas

Executada em 2026-11-04 neste Mac. Produto: MacVolume 0.2.0, extensão 0.2.0,
protocolo local versão 1.

**Estado atual (2026-11-05, 0.2.1):** 12 testes Swift, 10 testes JavaScript e 2 testes Python
aprovados. Integração real com mestre Core Audio, rotas virtuais, caixas do Mac, AirPods,
retomada de contexto interrompido, wake simulado e recuperação de IO aprovada. O ID fornecido foi registrado e a conexão com o Chrome cotidiano foi confirmada na interface do app em 2026-11-05. Os resultados detalhados da atualização
estão ao final; a primeira seção preserva o histórico de 0.2.0.

## Verificações concluídas

| Verificação | Resultado |
| --- | --- |
| `swift test` | 7 testes passaram: protocolo, framing, socket privado, perfil único, shutdown e modelo nativo |
| `node --test Tests/ChromeExtension/*.test.mjs` | 7 testes passaram: ganhos, mute, encerramento, falhas, cancelamento, validação, identidade e atividade |
| `python3 -m unittest discover -s Tests -p 'test_*.py'` | 2 testes passaram: instalação/atualização/remoção isoladas e proteção contra symlinks |
| Build de release | `build/MacVolume.app`, com ponte, extensão e scripts |
| Assinatura | Verificada com `codesign --verify --deep --strict` |
| Sintaxe | JavaScript, scripts Python, script shell e `Info.plist` verificados |
| Interface nativa | Previews conectada/desconectada renderizadas e inspecionadas; sliders e instruções legíveis |
| Confirmação de volume no modelo nativo | Valor muda após confirmação; timeout conserva o valor anterior; desconexão limpa comandos pendentes |

O teste de integração usou Google Chrome for Testing 148.0.7778.96 com perfil temporário,
a extensão e o executável ChromeBridge do pacote compilado, conectados a um servidor que
simula o app. O servidor Swift real foi testado separadamente nos testes de transporte;
o modelo SwiftUI foi testado com seu servidor, sem iniciar taps de áudio.

Foram abertas duas páginas do mesmo domínio local com tons de 440 e 660 Hz, em nível de pico
de −80 dBFS. A amostragem foi feita antes e depois do ganho no documento offscreen:

| Situação | Aba 1: saída/entrada RMS | Aba 2: saída/entrada RMS |
| --- | --- | --- |
| Volumes em 30% e 70% | 0,300 | 0,700 |
| Mute na aba 1 | 0,000 | 0,700 |
| Após desconectar e reconectar a ponte | 0,000 | 0,700 |

A primeira medição anterior também encontrou 0,299 para ganho de 0,300, dentro da tolerância
de amostragem de 0,015. Os testes exigem entrada capturada não nula; não comparam apenas
os percentuais reportados pela extensão.

Também passaram no navegador: habilitação pelo popup, captura simultânea de abas do mesmo
site, indicadores de atividade capturada, rejeição de comando de sessão expirada, reconexão
preservando ganhos, navegação na aba, remoção ao fechar uma aba e liberação das capturas por
mensagem de encerramento. O teste usa um perfil temporário e não registra a extensão no
Chrome pessoal do usuário.

Durante a preparação, o teste detectou que `--mute-audio`, incluído por padrão pelo Playwright
headless, silencia também a captura. O teste final remove essa opção e usa os tons de baixo
nível acima. O documento offscreen mede a atividade antes do ganho, pois o indicador `audible`
do Chrome pode ficar falso quando a reprodução direta é substituída pela captura.

## Pendências registradas na primeira execução (2026-11-04)

- Instalação e uso no perfil cotidiano do Google Chrome, incluindo a confirmação visual de suas permissões.
- Composição do ganho por aba com o tap Core Audio do volume mestre; a integração acima não inicia o mixer nativo.
- Troca de dispositivo físico, AirPods, sleep/wake e chamadas de áudio/vídeo durante a captura.
- Conteúdo protegido e sites reais com restrições próprias de reprodução/captura.
- Encerramento forçado do navegador/app e falhas abruptas durante inicialização de captura.
- Compatibilidade no piso declarado de Chrome 116 e macOS 14.4; o navegador automatizado usado foi o Chrome 148 deste Mac.

Esse era o estado inicial. A atualização abaixo registra quais itens foram concluídos;
o roteiro manual vinculado ao final contém as pendências atuais.


## Atualização 0.2.1 — 2026-11-05

A integração passou a usar o `ChromeTabModel`, `MixerModel` e `ProcessVolumeTap` reais,
com defaults desabilitados, socket temporário e controle restrito ao Chrome for Testing.
O MacVolume cotidiano permaneceu aberto. As duas abas receberam 30% e 70% pela interface
do modelo nativo, com confirmação pela extensão. Os ganhos medidos no offscreen foram
0,300 e 0,700; após mute da primeira aba, 0,000 e 0,700.

Foi interrompido um `AudioContext` real com `suspend()`: a extensão retomou a saída,
preservando os ganhos de ambas as abas. Testes com dependências simuladas cobrem também
recusa de retomada, limpeza após falha de inicialização e encerramento definitivo do contexto.
O campo opcional `issue` é compatível com o protocolo versão 1 e exibe o diagnóstico no app/popup.

| Etapa do mixer nativo | Pico de entrada | Pico de saída | Saída/entrada |
| --- | --- | --- | --- |
| Mestre 50%, aba 1 em mute | 0,0000726 | 0,0000363 | 0,500 |
| Mestre 50%, abas 30% e 70% | 0,0000997 | 0,0000498 | 0,500 |
| Rota para caixas do Mac | 0,0000978 | 0,0000489 | 0,500 |
| Retorno à saída virtual | 0,0000978 | 0,0000489 | 0,500 |
| Rota para AirPods conectados | 0,0000978 | 0,0000489 | 0,500 |
| Wake simulado, após reconstruir rota | 0,0000978 | 0,0000489 | 0,500 |
| IO parado e recuperado pelo watchdog | 0,0000978 | 0,0000489 | 0,500 |

Outro ensaio percorreu Microsoft Teams Audio → Background Music → Microsoft Teams Audio,
com sinal não nulo e razão 0,500 em todas as etapas. A geração da rota foi observada para
comprovar reconstrução após wake/stall, em vez de apenas ler um sinal anterior. Os valores
são medições dos buffers do tap; não constituem medição acústica, de ausência de cliques ou
prova de ausência de reprodução direta durante uma mudança.

A investigação identificou e corrigiu um defeito real: helpers de um app iniciado pelo
editor/terminal herdavam o agrupamento do lançador. O bundle que contém o executável agora
tem prioridade; serviços compartilhados continuam usando a responsabilidade do macOS.
Há testes para Chrome iniciado pelo editor, helper normal, WebKit compartilhado e CLI.
A tentativa de alterar somente a forma de lançamento do navegador de teste foi abandonada;
o teste final usa o agrupamento de produção corrigido, sem uma regra especial de teste.

Uma tentativa inicial de criar o tap excedeu o timeout de 15 segundos após recompilação.
O ensaio seguinte com a mesma lógica passou, incluindo rotas e recuperação. A demora inicial
em builds ad-hoc continua uma limitação operacional; não foi declarada corrigida. A amostra
da execução bem-sucedida mostrou o IO e as operações de rota ativos, sem espera permanente.

A extensão foi carregada manualmente pelo usuário. Em 2026-11-05, o ID fornecido foi registrado
pelo instalador para o executável no caminho estável de `build/MacVolume.app`. O manifest
foi lido de volta e validado (origem exata e executável existente). A interface do app mostrou
`Chrome connected` e identificou uma aba com áudio, ainda aguardando a habilitação de captura.
Não foram registrados títulos ou URLs pessoais como evidência.

O ícone foi adicionado ao manifest, usando o logo existente em PNGs RGBA de 16, 32, 48 e
128 pixels. Os caminhos/dimensões foram verificados e a versão de 128 pixels foi inspecionada.
A extensão carregada pelo usuário precisa ser recarregada para o Chrome atualizar o ícone.
A ferramenta continua impedida de abrir `chrome://extensions`; não foi tentada uma rota alternativa.

O [roteiro manual restante](../chrome-manual-validation.md) mantém pendentes a mudança global de
saída, suspensão real, modo de chamada dos AirPods, sites protegidos, falhas forçadas e o piso
Chrome 116/macOS 14.4. Não foram iniciadas chamadas nem feita publicação na Web Store.
