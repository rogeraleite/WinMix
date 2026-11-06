# Validação — controles por aba 0.4.0

Executada em 2026-11-06. App e extensão 0.4.0; protocolo local versão 1 com comando
explícito `playback` e capacidades opcionais. Escopo: somente YouTube e YouTube Music.

A versão adiciona Play/Pause ao lado de volume/mute no MacVolume, preserva abas pausadas
e distingue reprodução de audibilidade. Abas com mute ou ganho zero continuam oferecendo
Pause enquanto o player está tocando.

## Verificações

| Verificação | Resultado |
| --- | --- |
| `swift test` | 15 testes aprovados; transporte, confirmação, timeout, desconexão e capacidade de reprodução |
| `node --test Tests/ChromeExtension/*.test.mjs` | 14 testes aprovados; ganhos independentes, seleção de players, pausa repetida, retomada, rejeição/timeout e protocolo |
| `python3 -m unittest discover -s Tests -p 'test_*.py'` | 2 testes aprovados |
| Integração com app simulado | Aprovada em Chrome for Testing, sem popup/ativação por aba |
| Integração com app nativo | Aprovada com `ChromeTabModel`, `MixerModel`, ponte e Core Audio reais |
| Interface | Previews conectada/desconectada inspecionadas; Play/Pause e capacidades desabilitadas sem cortes no layout |
| Escopo | Mesmas quatro origens HTTPS; sem novas permissões, captura ou serviços externos |

## Casos de integração

O teste usa Chrome for Testing 148.0.7778.96 em perfil/socket temporários. As páginas
HTTPS nos hosts aprovados são fixtures locais, não o serviço real nem a sessão pessoal.
O caminho nativo envia os comandos pelo mesmo `ChromeTabModel` usado na interface.

- Duas abas recebem ganhos independentes de 30% e 70%. Os volumes reais dos players
  são 0,240 e 0,420 para volumes de site 0,800 e 0,600.
- Pause/Play em uma aba mantém a outra tocando e preserva os dois ganhos e mutes.
- A linha pausada permanece e oferece retomada; mudanças pelo próprio site são refletidas.
- Pause/Play com mute e ganho zero preserva esses valores e usa reprodução real.
- Vários players ativos na aba são pausados/retomados; um player apenas pré-carregado
  não inicia. Pause repetido não perde os alvos de retomada.
- Um frame autorizado participa dos comandos. Uma rejeição de Play nesse frame mostra
  erro e o estado real do player principal que retomou, sem alegar sucesso total.
- Uma rejeição determinística `NotAllowedError`, injetada no ponto de chamada nativa do
  controlador, percorre a ponte até o app. O ganho continua inalterado; o usuário recebe
  orientação para iniciar no site. Isso testa propagação de erro, não a política real
  de autoplay de uma conta do YouTube.
- Estado de controlador legado 0.3 mantém volume e desabilita play/pause com instrução
  de recarregar a página. A retomada de capacidades modernas também foi verificada.
- Navegação elimina alvos antigos e conserva o ganho. Reconexão não repete playback.
  Recarga da extensão reconecta páginas abertas com controlador moderno.
- `example.com` continua sem controlador. Web Audio sem player compatível mantém mute
  e apresenta volume/playback indisponíveis.
- Fechar uma aba limpa a linha. Reconectar a ponte mantém uma aba pausada sem reiniciá-la.
  Encerrar o app restaura volume sem parar a aba que toca nem reiniciar a que está pausada.

## Core Audio

A integração nativa usa defaults privados, apenas Chrome for Testing e saída explícita
Microsoft Teams Audio (`MSLoopbackDriverDevice_UID`). Não altera a saída padrão nem os
volumes salvos do usuário.

| Etapa | Pico na entrada | Pico na saída | Saída/entrada |
| --- | --- | --- | --- |
| Duas abas, mestre em 50% | 0,0000565 | 0,0000283 | 0,500 |
| Um player em 100%, mestre em 50% | 0,0001000 | 0,0000500 | 0,500 |
| Mesmo player em 30%, mestre em 50% | 0,0000300 | 0,0000150 | 0,500 |

O ganho do player é 0,300 em relação à referência e o mestre mantém fator 0,500.
Valores são leituras digitais, não medição acústica nem prova de ausência de transientes.

## Ativação e limites

Recarregar **MacVolume Tabs** uma vez em `chrome://extensions` carrega a versão 0.4.0.
Páginas que ainda executam o controlador antigo precisam de uma recarga da própria página,
conforme indicado na linha. Novas páginas compatíveis funcionam sem ativação individual.
O ID e a pasta da extensão permanecem os mesmos.

Validação no YouTube/YouTube Music reais, autoplay real, suspensão, chamadas/AirPods,
falhas abruptas e piso Chrome 116/macOS 14.4 continuam no
[roteiro manual](chrome-manual-validation.md). Não foram declarados aprovados por fixtures.

Evidências anteriores: [0.3.0](history/chrome-tab-validation-0.3.md) e
[0.2.x](history/chrome-tab-validation-0.2.md).
