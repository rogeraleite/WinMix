# Volume individual em sites do Chrome

Pedido de implementação em 2026-11-06, após a revisão dos controles ausentes.

## Decisão

Ampliar o controlador existente de elementos HTML audio/video para páginas HTTP e HTTPS.
Ele mantém o volume do site separado do ganho da aba, sem capturar áudio. O mestre do
Chrome continua global. A alternativa tabCapture exige gesto por aba e contraria o fluxo
automático; controlar por processo Core Audio não identifica as abas de forma confiável.

Descobrir abas com áudio em todos os sites e manter as já detectadas após pausa/mute.
A permissão tabs permite informar abas com áudio mesmo se o acesso ao site for retido;
host_permissions permite os controladores em HTTP/HTTPS. Páginas internas, Web Store,
arquivos e grafos Web Audio sem player compatível exibem volume indisponível e mute.
O recurso não promete controlar qualquer origem de som. Não incluir modo anônimo.

## Fluxo e interface

Publicar modo automatic-sites sem quebrar a leitura do modo antigo automatic-youtube.
Exibir instrução de atualização quando a extensão antiga estiver conectada, incluindo o
passo de acesso aos sites. O popup continua apenas informativo e oferece reconexão.

Durante um arraste, manter o slider habilitado e exibir o valor solicitado com estado
APPLYING. Enviar no máximo um comando por aba por vez, substituindo o próximo ganho pelo
valor mais recente. Confirmar cada comando pelo requestID e enviar o último ganho após
a confirmação. Em erro, timeout, troca de sessão ou desconexão, descartar valores
enfileirados e voltar ao último estado confirmado. Abas diferentes são independentes.

## Validação e entrega

Testar escopo HTTP/HTTPS, esquemas bloqueados, fila de arraste, isolamento, confirmação,
erro e desconexão. Exercitar players em domínios diferentes, frames, navegação, recarga,
pausa/mute e caso Web Audio negativo num Chrome for Testing com perfil temporário.
Gerar versão 0.5.0 do app e extensão. Preservar o bundle anterior antes de atualizar.
Ativar a extensão pessoal somente com a autorização de acesso solicitada pelo Chrome;
essa concessão é a etapa final do usuário. Documentar evidências e limites reais.

## Restrições

- macOS 14.4+, Chrome 116+, Swift e JavaScript sem dependências novas de produção.
- Nenhuma captura/gravação ou transmissão externa de conteúdo.
- Volume por aba entre 0% e 100%; Boost permanece no mestre.
- Instalação existente conserva pasta, ID e registro da ponte.
