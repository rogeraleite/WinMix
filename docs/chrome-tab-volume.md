# Volume individual por aba do Chrome

App e extensão 0.5.0, 2026-11-06. Requer macOS 14.4+ e Chrome 116+.

Abas com áudio/vídeo em sites HTTP/HTTPS aparecem automaticamente em **CHROME TABS**,
com título, domínio e controles independentes. Players compatíveis recebem volume entre
0% e 100%, mute e play/pause. Pausa e mute preservam a linha. O slider geral do Chrome
continua como mestre de todas as abas, inclusive áudio sem suporte ao ganho individual.

## Atualizar a instalação existente

1. Abra o MacVolume 0.5.0. O app novo deve estar aberto antes da extensão nova.
2. Em `chrome://extensions`, recarregue **MacVolume Tabs**, na pasta originalmente instalada.
3. Autorize o novo acesso a sites HTTP/HTTPS e aos metadados das abas quando o Chrome pedir.
4. Inicie ou continue a reprodução. Se uma página antiga ainda não aparecer ou pedir recarga,
   confira o acesso ao site e recarregue essa página uma vez.

O ID e o registro da ponte permanecem válidos na mesma pasta e caminho do app. Reconnect,
no popup, tenta novamente a conexão com o app. Não há ativação por aba. A configuração
precisa permitir execução nos sites desejados; acesso apenas ao clicar impede automação
em segundo plano. A concessão de acesso deve ser feita pelo usuário no Chrome.

O app detecta extensões antigas e mostra **Extension update required**, em vez de tratar
uma ponte conectada como prova de que os novos controles estão disponíveis.

## Primeira instalação

```sh
./scripts/build-app.sh
```

No Chrome, abra `chrome://extensions`, ative Modo do desenvolvedor, escolha Carregar sem
compactação e selecione `Extensions/Chrome`. Copie o ID e execute:

```sh
python3 scripts/install-chrome-bridge.py ID_DA_EXTENSAO --app "$PWD/build/MacVolume.app"
open build/MacVolume.app
```

O instalador registra `com.rogerleite.macvolume.chrome` somente para o ID informado em
`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`, sem sudo. Se mover o
app ou a extensão, atualize o registro com `--replace`. Em Settings, **Show Chrome Extension
Folder** e **Open Installation Instructions** abrem os recursos incluídos no bundle.

## Permissões e limites

- `tabs`: descobrir abas com áudio e seus metadados mesmo quando falta acesso ao site.
- `http://*/*` e `https://*/*`: executar o controlador de áudio/vídeo nos sites autorizados.
- `scripting`, `nativeMessaging`, `storage` e `alarms`: injeção, ponte local, estado de sessão
  e reconexão. Não utiliza `activeTab`, `tabCapture`, `offscreen` ou `debugger`.

A extensão não captura nem grava áudio, não coleta texto das páginas e não envia conteúdo
para serviços externos. A ponte local troca apenas comandos e estado de abas com áudio.
Não há modo anônimo, acesso a arquivos ou controle de páginas internas do Chrome/Web Store.

O ganho atua nos elementos HTML audio/video. Grafos Web Audio sem um player compatível,
players restritos e frames sem acesso não têm garantia de controle. Uma aba audível sem
player reconhecido mostra a limitação e oferece mute. Em uma página que mistura players
HTML com outras fontes de som, o slider cobre os players compatíveis; ele não garante
alterar o áudio de toda a página. Não é um controle universal de qualquer som do Chrome.

Frames HTTP/HTTPS novos recebem o controlador. A atualização de documentos já abertos
conecta o documento principal; players em frames antigos podem exigir uma recarga da página.

## Comportamento

- Player do site em 80% e aba em 30% resultam em 24%, antes do mestre do Chrome e do sistema.
  Alterar o player mantém os fatores separados; repetir um comando não acumula multiplicação.
- Durante o arraste, o valor solicitado aparece com **APPLYING**. O slider permanece ativo.
  Há uma requisição por aba; valores intermediários são substituídos pelo mais recente.
  A confirmação envia o próximo ganho. Outras abas mantêm sua própria fila.
- Erro, timeout ou desconexão descartam ajustes enfileirados e mostram o último estado
  confirmado. Trocar a sessão ou fechar a aba também limpa seus comandos pendentes.
- Novos players herdam o ganho. Navegar entre sites mantém o ganho da aba durante a sessão;
  navegar para uma página restrita encerra seu controle de player.
- Ajustar o slider remove mute da aba. Play/pause preserva ganho e mute.
- Pause interrompe os players compatíveis ativos. Play retoma os pausados pelo app ou o
  player principal mais recentemente ativo. Players apenas pré-carregados não são iniciados.
  Bloqueios de Play e falhas parciais são informados com o estado real.
- Ao encerrar normalmente o app, o volume dos players é restaurado e o mute aplicado pela
  extensão é desfeito, respeitando mudanças feitas pelo usuário. A reprodução não é reiniciada.
- Desconectar somente a ponte preserva os ganhos enquanto a extensão está ativa. Recarregar
  ou desativar a extensão interrompe a sessão; ganhos não são IDs persistentes de abas.
  Encerramento forçado não garante restauração imediata.

## Verificação

```sh
swift test
node --test Tests/ChromeExtension/*.test.mjs
python3 -m unittest discover -s Tests -p 'test_*.py'
./scripts/build-app.sh build/validation/MacVolume.app
```

Integração isolada, com páginas HTTP/HTTPS controladas, extensão e ponte reais:

```sh
PLAYWRIGHT_MODULE=/caminho/para/playwright CHROME_BINARY="/caminho/para/Google Chrome for Testing" MACVOLUME_TEST_APP=build/validation/MacVolume.app node scripts/test-chrome-integration.mjs
```

Acrescente `MACVOLUME_TEST_OUTPUT=UID` e `--native` para testar modelos nativos e mestre Core
Audio em saída explícita, sem alterar saída padrão, defaults ou perfil pessoal.

Resultados em [chrome-tab-validation.md](chrome-tab-validation.md). Testes em serviços e
perfil pessoais estão separados em [chrome-manual-validation.md](chrome-manual-validation.md).

Para remover, desinstale a extensão e execute `python3 scripts/uninstall-chrome-bridge.py`.
