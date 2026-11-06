# Chrome all-sites volume implementation plan

**Goal:** controles individuais em players HTTP/HTTPS e arraste contínuo sem perda do último ganho.

**Architecture:** reutilizar controlador HTML, extensão e ponte local. Descobrir abas via
tabs e separar ganho confirmado de ganho solicitado; uma requisição por aba com coalescência.

**Tech Stack:** SwiftUI, Swift Package Manager, Chrome MV3, Node tests, Playwright.

**Spec:** `docs/superpowers/specs/2026-11-06-chrome-all-sites-design.md`

## Global constraints

- macOS 14.4+, Chrome 116+, sem dependências novas de produção.
- Nenhuma captura/gravação ou transmissão externa de conteúdo.
- Ganhos 0...1 por aba; Boost permanece no mestre.
- Preservar pasta/ID/registro da instalação e bundle anterior.

## Tasks

- [x] Escopo: testar supportedURL para HTTP/HTTPS, portas e esquemas privados; atualizar
  scope.js, manifest, background.js e popup para todos os sites. Descobrir abas sem acesso,
  preservar mute e reportar falta de player/permissão. Modo automatic-sites compatível na ponte.
- [x] Arraste: teste nativo envia 0.2, 0.4 e 0.8 antes de confirmar a primeira requisição;
  exigir uma primeira mensagem 0.2 e uma segunda 0.8, sem 0.4. Outra aba envia imediatamente.
  Cobrir timeout/erro/desconexão/sessão e descarte de filas. Implementar requestedVolumes,
  confirmação/flush no ChromeTabModel e slider habilitado enquanto aguarda confirmação.
- [x] Integração: adaptar script existente para três domínios, HTTP e HTTPS; validar
  recarga de páginas existentes e caso negativo Web Audio. Rodar suites Swift/Node/Python,
  build em build/validation/MacVolume.app e integração isolada com ponte real.
- [x] Entrega: atualizar documentação/versionamento, conferir previews e diff; preservar
  bundle anterior, instalar app 0.5.0 no caminho registrado e verificar estado de execução.
  Deixar a concessão de acesso aos sites para o usuário se o Chrome a solicitar.

Execução nesta sessão, em sequência. Reutilizar fixtures e testes de transporte existentes.

Validação: 17 Swift + 17 JavaScript + 2 Python; integrações simulada/nativa aprovadas.
Ativação no perfil pessoal concluída após autorização explícita do usuário.

App 0.5.0 instalado e aberto em `build/MacVolume.app`; bundle 0.4.0 preservado em
`build/MacVolume.backup-0.4.0-01e91eb.app`. A interface real confirmou
`Extension update required` com a extensão pessoal ainda antiga.

Após autorização, extensão pessoal atualizada de 0.2.1 para 0.5.0, **On all sites**
confirmado e modo automático conectado. Duas abas reais do YouTube apareceram sem
recarregar as páginas, com ganhos independentes de 30% e 70% e pausa pelo app.
Ao terminar, ambas foram restauradas para ganho de 100% e reprodução pausada.
