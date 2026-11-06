# Controle automático por aba — proposta

Requisito corrigido pelo usuário em 2026-11-05: abas com áudio devem aparecer no MacVolume
e aceitar controle sem clicar em “Enable this tab” para cada aba. A versão 0.2.x detectava abas automaticamente, mas exigia ativação individual para capturá-las.

**Estado: escopo aprovado em 2026-11-05 e implementado na versão 0.3.0; ativação no Chrome pessoal exige a recarga única da extensão.**

O escopo aprovado usa somente as origens HTTPS `youtube.com`, `www.youtube.com`,
`m.youtube.com` e `music.youtube.com`. O controle será feito nos elementos de áudio/vídeo
usados por esses sites. Interceptar grafos Web Audio arbitrários em outros sites não faz
parte desta entrega. Não haverá acesso genérico HTTP/HTTPS a outros domínios.

## Limite confirmado

`chrome.tabCapture` exige uma concessão por ação do usuário na extensão para a aba alvo.
A permissão genérica de acesso aos sites não substitui essa concessão de captura. Apenas
automatizar a chamada atual não resolve o requisito.

Referências: [tabCapture](https://developer.chrome.com/docs/extensions/reference/api/tabCapture)
e [checagem no Chromium](https://github.com/chromium/chromium/blob/main/chrome/browser/extensions/api/tab_capture/tab_capture_api.cc).

## Abordagem recomendada

Substituir o fluxo padrão de captura por controles nos players das páginas, através de
content scripts. Manter a descoberta automática de abas audíveis e a ponte nativa existente.

- Instalar o controlador automaticamente em páginas HTTP/HTTPS autorizadas e seus frames.
- Aplicar ganho nos elementos de áudio/vídeo usados pelos sites escolhidos, sem solicitar captura.
  Grafos Web Audio arbitrários ficam fora do escopo aprovado desta entrega.
- Conservar o volume do site como fator separado do ganho da aba, para não confundir os
  controles do player com os do MacVolume.
- Mostrar cada aba com título, domínio, volume, mute e capacidade real de controle.
- Confirmar os comandos no app e manter mute via API de abas mesmo quando o volume não
  puder ser controlado pelo player.
- Remover a exigência “Enable this tab” do fluxo automático.
- Informar conteúdo não suportado; não oferecer um slider que aparenta funcionar sem efeito.

Referência: [content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts).

## Permissão e limites que precisam ser aceitos

A extensão precisará de autorização para executar scripts nos sites abrangidos. A opção
de cobertura geral requer acesso a páginas HTTP/HTTPS; o Chrome pode apresentar esse acesso
como permissão para ler e alterar dados nesses sites. O recurso continua local e não deve
coletar ou transmitir conteúdo de páginas. A alternativa é autorizar somente uma lista
inicial de sites, com controle automático de todas as abas desses sites.

Não há garantia universal: páginas internas do Chrome, players restritos e caminhos de áudio
que o controlador não conseguir interceptar precisam apresentar limitação explícita. Contextos
Web Audio criados antes da instalação do controlador podem exigir recarregar a página uma
vez após atualizar a extensão. Novas páginas compatíveis devem funcionar automaticamente.

Um navegador Chromium modificado permitiria uma integração mais profunda, mas exigiria
manter e distribuir outro navegador. Não é equivalente a adicionar o recurso ao Chrome
instalado pelo usuário.

## Critérios de aceitação

1. Duas abas novas com áudio/vídeo aparecem e aceitam volumes independentes sem abrir o popup.
2. O mesmo funciona em segundo plano, em frames autorizados e ao iniciar novos players.
3. Player sem elemento HTML compatível apresenta volume indisponível; o mute continua utilizável.
4. Alterar o volume no site não desfaz o ganho da aba nem provoca multiplicação repetida.
5. Mute não remove a linha do painel; fechar uma aba limpa seu estado.
6. Abas ou fontes incompatíveis mostram a limitação real; a automação não é anunciada como
   controle universal de todo áudio do Chrome.

A escolha foi limitada pelo usuário ao YouTube e ao YouTube Music. A implementação não usa
a permissão genérica `tabs` nem acesso a outros sites. O guia atual está em `docs/chrome-tab-volume.md`.
