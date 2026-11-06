# Volume e play/pause por aba: YouTube e YouTube Music

MacVolume e extensão 0.4.0, 2026-11-06. Requer macOS 14.4+ e Chrome 116+.

Quando uma aba do YouTube ou YouTube Music reproduz áudio, ela aparece automaticamente
na seção **CHROME TABS** do MacVolume com título, domínio, volume, mute e play/pause. Abas
pausadas permanecem disponíveis para retomar. Não há botão de
ativação por aba. Outras páginas ficam fora do controle automático.

## Atualizar a instalação existente

O ID e o registro da ponte existentes continuam válidos se o app e a pasta da extensão
permanecerem nos mesmos caminhos.

1. Em `chrome://extensions`, clique em **Recarregar** no cartão **MacVolume Tabs**.
2. Se o Chrome pedir, autorize acesso somente ao YouTube e ao YouTube Music.
3. Abra ou continue reproduzindo áudio nesses sites e use os controles no MacVolume.

Abas que já executavam o controlador 0.3 precisam de uma recarga da página para receber
play/pause. O painel informa **Reload this page once** nesses casos; o volume continua
disponível. Isso é uma migração única do código da página, não uma ativação de cada aba.
Novas páginas compatíveis recebem os controles automaticamente.

Essa é uma atualização única da extensão, não uma habilitação de cada aba. A extensão tenta
conectar automaticamente os players das páginas que já estavam abertas. Se o Chrome impedir
uma injeção por falta de permissão, o painel informa a limitação; confira o acesso ao site
na configuração da extensão. O popup tem status e **Reconnect**, sem controles de ativação.

O controle de navegador usado pelo agente bloqueia `chrome://extensions`; a recarga e a
confirmação das permissões precisam ser feitas pelo usuário. O app pode mostrar uma mensagem
pedindo atualizar a extensão enquanto a versão anterior ainda estiver carregada no Chrome.

## Primeira instalação

```sh
./scripts/build-app.sh
```

No Chrome, abra `chrome://extensions`, ative **Modo do desenvolvedor** e escolha **Carregar
sem compactação**. Selecione `Extensions/Chrome` e copie seu ID. Depois:

```sh
python3 scripts/install-chrome-bridge.py ID_DA_EXTENSAO --app "$PWD/build/MacVolume.app"
open build/MacVolume.app
```

A extensão conecta automaticamente; o botão **Reconnect** serve para tentar novamente se o
app estiver fechado durante a primeira tentativa. Não é necessário abrir o popup para que
abas sejam detectadas ou controladas.

O instalador registra somente `com.rogerleite.macvolume.chrome` em:

```text
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/
```

Ele permite o ID exato e usa o caminho absoluto da ponte no `.app`, sem `sudo`. Mover o app
ou carregar a extensão de outra pasta pode exigir atualizar o registro com `--replace`.

## Permissões e escopo

As origens autorizadas são somente:

- `https://youtube.com/*`
- `https://www.youtube.com/*`
- `https://m.youtube.com/*`
- `https://music.youtube.com/*`

As permissões técnicas são `scripting`, `nativeMessaging`, `storage` e `alarms`. O acesso aos
sites também permite obter título/URL somente dessas páginas. A extensão não solicita
`tabs`, `<all_urls>`, `activeTab`, `tabCapture`, `offscreen` ou `debugger`.

O controlador ajusta volume e reprodução dos elementos de áudio/vídeo nas páginas autorizadas.
Não captura ou grava áudio, não coleta texto de páginas e não transmite conteúdo para serviços
externos. A ponte local troca apenas comandos e estado. Modo anônimo e outros sites estão
fora do escopo. Frames novos autorizados recebem o controlador; o bootstrap de páginas já
abertas prioriza o player do documento principal, sem depender de frames de anúncios.

## Comportamento dos controles

- O ganho da aba se combina com o volume do player. Player em 80% e aba em 30% produzem
  volume efetivo de 24%, antes do mestre do Chrome e da saída do sistema.
- Alterar o volume no player mantém esse fator separado; comandos repetidos não multiplicam
  o resultado novamente.
- Novos players da mesma aba recebem o ganho automaticamente. Navegação dentro dos sites
  autorizados mantém o ajuste durante a sessão; abas fechadas ou fora desses sites têm seu
  estado removido.
- Pausar ou silenciar não elimina a linha já detectada. A API de abas aplica o mute; ele
  pode estar disponível mesmo quando o player não suporta controle de volume.
- O app exibe valores confirmados. Sem um player compatível, informa a limitação em vez de
  oferecer um slider aparentemente funcional.
- O controle geral do Chrome no mixer é o mestre de todas as abas, inclusive páginas que
  não fazem parte da lista automática. Boost continua sendo uma opção desse mestre.
- O botão Pause interrompe os players compatíveis que estão tocando na aba selecionada,
  inclusive em frames autorizados. Play retoma somente os players pausados pelo MacVolume;
  sem esse conjunto, tenta o player mais recentemente ativo no documento principal.
  Players novos, anúncios pré-carregados e elementos sem histórico de reprodução não são
  iniciados arbitrariamente. Abas diferentes mantêm reprodução e ganhos independentes.
- Play/pause preserva volume e mute. Um player silenciado ou com ganho zero ainda pode
  estar tocando; o botão exibe Pause nesse estado. Mudanças feitas no site também aparecem.
- Se o navegador bloquear Play, o painel mostra a falha e orienta iniciar a reprodução no
  próprio site uma vez. Falhas parciais entre frames mostram o estado real e o erro, sem
  afirmar que todos os players concluíram o comando. Reconectar não repete comandos antigos.
- Ao encerrar o app, a restauração de volume/mute não reinicia players pausados nem
  interrompe players que continuam tocando.
- Se somente a ponte desconectar, os ganhos das páginas permanecem enquanto a extensão
  estiver ativa. O app desabilita comandos até a reconexão.
- Encerrar normalmente o MacVolume restaura o volume original dos players e desfaz o mute
  aplicado pela extensão, respeitando mudanças de mute feitas pelo usuário.
- Recarregar/desativar a extensão interrompe sua sessão; os ajustes não são salvos como IDs
  permanentes de abas. Não dependa de manter um ganho após uma falha ou encerramento forçado.

O suporte é ao player de áudio/vídeo usado nesses sites, não a todo grafo Web Audio arbitrário.
Caminhos de áudio não suportados são apresentados explicitamente. Compatibilidade com cada
variante futura do YouTube depende de validação; não há promessa de controle universal.

## Mesmo repositório, mesmo produto

| Componente | Código |
| --- | --- |
| App e controles | `Sources/MacVolume/ChromeTab*.swift` |
| Controlador do player | `Extensions/Chrome/media-controller.js`, `page-controller.js` |
| Ponte de conteúdo e descoberta | `Extensions/Chrome/content-bridge.js`, `background.js` |
| Ponte nativa e protocolo | `Sources/ChromeBridge/`, `Sources/ChromeSupport/` |
| Registro/remoção | `scripts/*-chrome-bridge.py` |

O build inclui a extensão, os scripts e os guias em `Contents/Resources`. Em Settings, os
botões **Show Chrome Extension Folder** e **Open Installation Instructions** ajudam a
configurar uma distribuição compilada. Carregar a cópia do `.app` em outra pasta produz
outro ID; mantenha a pasta originalmente registrada para evitar essa troca.

Os ícones usam o logo do app em PNGs de 16, 32, 48 e 128 pixels. Para regenerá-los:

```sh
python3 scripts/make-icon.py --chrome-only
```

Para remover: remova a extensão no Chrome e execute:

```sh
python3 scripts/uninstall-chrome-bridge.py
```

## Verificação reproduzível

```sh
swift test
node --test Tests/ChromeExtension/*.test.mjs
python3 -m unittest discover -s Tests -p 'test_*.py'
./scripts/build-app.sh build/validation/MacVolume.app
```

O teste de integração usa Playwright e Chrome for Testing em perfil temporário, com páginas
HTTPS de teste nos hosts aprovados, sem abrir o popup ou invocar a ação da extensão. Ele não
usa o perfil pessoal nem acessa o YouTube real; os resultados de fixtures não substituem a
verificação do serviço em produção.

```sh
PLAYWRIGHT_MODULE=/caminho/para/playwright CHROME_BINARY="/caminho/para/Google Chrome for Testing" MACVOLUME_TEST_APP=build/validation/MacVolume.app node scripts/test-chrome-integration.mjs
```

Com mixer/tap Core Audio reais, informe uma saída explícita. `--probe --devices` lista os UIDs:

```sh
build/validation/MacVolume.app/Contents/MacOS/MacVolume --probe --devices
PLAYWRIGHT_MODULE=/caminho/para/playwright CHROME_BINARY="/caminho/para/Google Chrome for Testing" MACVOLUME_TEST_APP=build/validation/MacVolume.app MACVOLUME_TEST_OUTPUT=UID node scripts/test-chrome-integration.mjs --native
```

`MACVOLUME_TEST_OUTPUTS` aceita uma lista JSON de saídas adicionais. Os probes usam um socket
privado e não alteram a saída padrão ou os volumes salvos. O modo nativo controla somente o
Chrome for Testing. Os tons das fixtures são de baixo nível; a fixture negativa Web Audio
usa um nível maior para ultrapassar o limiar de detecção audível do navegador.

Veja os [resultados de validação](chrome-tab-validation.md) e o [roteiro manual](chrome-manual-validation.md).
