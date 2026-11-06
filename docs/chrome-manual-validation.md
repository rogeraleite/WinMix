# Verificação no Chrome pessoal — controles por aba 0.4.0

Atualizado em 2026-11-06. Os testes automatizados usam páginas controladas em perfil
separado. A etapa abaixo confirma o comportamento no YouTube/YouTube Music reais do usuário.

## Atualização única

1. Recarregar **MacVolume Tabs** em `chrome://extensions`.
2. Se solicitado, confirmar acesso somente aos hosts do YouTube e YouTube Music.
3. Manter o MacVolume 0.4.0 aberto.
4. Recarregar uma vez páginas que ainda executam o controlador 0.3 quando o painel pedir;
   novas páginas recebem play/pause automaticamente.

O ID anteriormente registrado permanece válido na mesma pasta. O agente não consegue operar
essa página por política do controle de navegador. Não há ativação por aba depois da atualização.

## Roteiro

| Cenário | Ação | Resultado esperado | Estado |
| --- | --- | --- | --- |
| Abas que já estavam abertas | Continuar/iniciar reprodução normal no YouTube Music ou YouTube após atualizar a extensão. | A aba aparece com volume/mute sem abrir o popup ou recarregar cada aba. | Bootstrap aprovado em fixtures; confirmar no serviço real após atualização. |
| Nova aba em segundo plano | Abrir outro vídeo/música e iniciar reprodução normalmente. | Uma linha distinta aparece no app; o controle não depende do popup. | Automação aprovada; confirmar com os players reais. |
| Volume do player + volume da aba | Ajustar o player e depois a aba em 30%; repetir o ajuste. | O fator de 30% se mantém sem acumular multiplicações. | Automação aprovada. |
| Mute/pausa | Silenciar e pausar uma aba. | A linha permanece, com estado correto, e a outra aba mantém seu ganho. | Automação aprovada. |
| Play/pause independente | Com duas abas tocando, usar Pause e depois Play somente em uma. | A outra continua tocando; os dois ganhos e mutes permanecem iguais. | Fixtures e modelo nativo aprovados; confirmar no serviço real. |
| Pausa pelo próprio site | Pausar no YouTube e retomar pelo MacVolume. | A linha reflete a pausa e Play retoma o player principal mais recentemente ativo. | Automação aprovada; confirmar no serviço real. |
| Player silenciado/ganho zero | Silenciar ou zerar o ganho, depois usar Pause/Play. | O botão reflete reprodução real e não altera ganho nem mute. | Automação aprovada. |
| Bloqueio de reprodução | Observar uma página que recusa Play. | Erro visível e orientação para iniciar no site; sem falso estado de sucesso. | Rejeição determinística coberta em fixture; política real depende da página. |
| Frames e falha parcial | Usar uma página autorizada com players em mais de um frame. | Pause/Play atinge os alvos corretos e mostra falha parcial com estado real. | Fixtures aprovadas; confirmar variantes reais quando presentes. |
| Site fora da lista | Reproduzir em outro site. | Não há controlador ou linha automática desse site. O mestre genérico do Chrome continua global. | Escopo aprovado por testes. |
| Player não suportado | Observar um caminho de áudio sem elemento compatível. | Não há slider de volume falso; mute pode estar disponível. | Caso negativo Web Audio aprovado em fixture. |
| Troca global de saída | Em momento adequado, alternar a preferência de saída do macOS e voltar. | O mestre segue a saída; os ganhos de páginas são preservados. | Rotas explícitas medidas; preferência global ainda manual. |
| Suspensão/chamada | Fazer suspensão real ou, numa chamada iniciada pelo próprio usuário, alternar AirPods para entrada/saída. | Recuperação ou diagnóstico visível, sem falsos controles ativos. | Pendente no modo automático. |
| Encerramento normal | Fechar o MacVolume. | Restaurar o volume original dos players e desfazer somente o mute aplicado pela extensão. | Automação aprovada. |
| Encerramento forçado/remoção | Usar conteúdo de baixo volume ao testar falhas. | Conferir restauração e reconexão; não presumir preservação de ganho em falha abrupta. | Recarga da extensão coberta; falhas forçadas ainda manuais. |
| Piso de compatibilidade | Repetir em Chrome 116/macOS 14.4 separados. | Compatibilidade com o piso declarado. | Não executado neste Mac. |

Registre somente versão, dispositivo, etapa, resultado e erro visível. Não é necessário
registrar títulos/URLs privados nem áudio de chamadas. Resultados anteriores ao modo automático
estão preservados em `docs/history/chrome-tab-validation-0.2.md`.
