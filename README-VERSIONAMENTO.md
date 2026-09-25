# Versionamento e publicação do MPTreco

## Visão geral

A versão oficial do MPTreco é representada por uma tag Git anotada no formato SemVer:

```text
vMAJOR.MINOR.PATCH
```

A branch oficial de publicação é `main`.

```text
Validação → versão npm → build local → commit → push da main → tag anotada
                                                               ↓
                        GitHub Actions → build limpa → GitHub Release + instalador
```

## Arquivos do fluxo

- `scripts/PUBLICAR-VERSAO-OFICIAL.ps1`: valida, calcula a versão, gera uma build local, cria o commit e envia a tag.
- `.github/workflows/publicar-release-oficial.yml`: gera uma build limpa no Windows e publica o instalador e os metadados de atualização na Release.
- `package.json` e `package-lock.json`: armazenam a versão exibida pelo aplicativo e usada no nome do instalador.

## Requisitos locais

- Windows.
- Git configurado com acesso de escrita ao repositório.
- Node.js 20 ou superior.
- Dependências instaladas.
- `yt-dlp`, FFmpeg e FFprobe preparados na pasta `bin`.
- Branch `main` sincronizada com `origin/main`.

Não é necessário instalar ou autenticar o GitHub CLI localmente. A Release é criada pelo GitHub Actions usando o token do próprio repositório.

## Conventional Commits e SemVer

O incremento automático considera os commits posteriores à última tag e o commit que será criado pela publicação:

| Commit | Incremento |
|---|---|
| `fix`, `security`, `perf`, `refactor`, `style`, `docs`, `test`, `build`, `ci`, `chore` | PATCH |
| `feat` | MINOR |
| Cabeçalho com `!` ou corpo com `BREAKING CHANGE:` | MAJOR |

Exemplos:

```text
fix(download): corrige percentual de progresso
feat(playlist): organiza arquivos em uma pasta própria
feat(interface)!: altera o fluxo principal do aplicativo
```

Quando necessário, substitua o cálculo automático usando `-Bump Patch`, `-Bump Minor` ou `-Bump Major`.

## Publicação

Execute na raiz do MPTreco:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\PUBLICAR-VERSAO-OFICIAL.ps1 `
  -CommitMessage "feat: melhora downloads e interface" `
  -ReleaseTitle "Melhorias nos downloads" `
  -Description "Adiciona organização de playlists e melhora a apresentação do progresso." `
  -Changes @(
    "organiza playlists explícitas em uma pasta própria",
    "remove o identificador do nome dos arquivos",
    "exibe 100% somente após a conclusão do processamento"
  ) `
  -Files @(
    ".github/workflows/publicar-release-oficial.yml",
    "README-VERSIONAMENTO.md",
    "README.md",
    "package.json",
    "package-lock.json",
    "scripts/PUBLICAR-VERSAO-OFICIAL.ps1",
    "src/principal.js",
    "src/preload.js",
    "src/interface/index.html",
    "src/interface/estilos.css",
    "src/interface/interface.js"
  ) `
  -Bump Auto
```

Todos os arquivos alterados devem aparecer em `-Files`. A publicação será interrompida se houver um arquivo modificado, novo ou removido que não tenha sido informado conscientemente.

Antes do push, o script apresenta um resumo e solicita confirmação. O parâmetro `-NoConfirm` deve ser reservado para automações controladas.

## Etapas executadas

1. Valida Git, Node.js, npm, branch `main`, `origin` e os arquivos do fluxo.
2. Executa `git fetch origin --tags --prune`.
3. Confirma que a branch local não está atrás nem divergente de `origin/main`.
4. Confere a lista explícita recebida em `-Files`.
5. Calcula a próxima versão SemVer.
6. Atualiza `package.json` e `package-lock.json` sem criar tag pelo npm.
7. Executa `git diff --cached --check` e `node --check` nos JavaScript alterados.
8. Executa a build local com `npm.cmd run dist`.
9. Confirma que `dist/MPTreco-Setup-X.Y.Z.exe`, seu `.blockmap` e `dist/latest.yml` foram criados.
10. Cria o commit e gera as notas da Release.
11. Após confirmação, envia a `main` e cria uma tag anotada.
12. O GitHub Actions executa `npm ci`, gera outra build em `windows-latest`, cria a Release e anexa os três arquivos de atualização.

## Artefatos

A build local permanece em `dist`, que não é versionada pelo Git.

O artefato oficial é a build limpa gerada pelo GitHub Actions:

```text
MPTreco-Setup-X.Y.Z.exe
MPTreco-Setup-X.Y.Z.exe.blockmap
latest.yml
```

O `latest.yml` informa ao aplicativo qual versão baixar e contém o hash do instalador. O `.blockmap` permite downloads diferenciais. A pasta `win-unpacked` não é publicada.

## Atualização automática no aplicativo

Ao abrir uma versão instalada no Windows, o MPTreco consulta a última Release pública do GitHub. Se houver uma versão superior, aparece um botão abaixo do número da versão. Ao clicar, o aplicativo baixa a atualização, verifica o arquivo e inicia o instalador após o download. A instalação por usuário normalmente reinicia o aplicativo sem intervenção; instalações em pastas protegidas podem solicitar permissão do Windows.

O modo `npm start` não consulta atualizações. A primeira versão com o atualizador precisa ser instalada manualmente; as seguintes podem ser instaladas pelo aplicativo. A Release precisa estar publicada e conter o instalador, seu `.blockmap` e o `latest.yml` da mesma build.

Os instaladores deste projeto não são assinados. Por isso, a verificação Authenticode está desabilitada; o hash do download é conferido, mas o Windows pode exibir avisos do SmartScreen. Não substitua os arquivos de uma versão já distribuída: publique uma versão superior quando precisar corrigir algo.

## Recuperação de falhas

Se a publicação for cancelada na confirmação, o commit e a atualização de versão permanecerão apenas no repositório local.

Se o commit subir, mas o push da tag falhar, envie posteriormente a tag indicada na mensagem apresentada pelo script.

Se a tag subir, mas a build ou a Release falhar, abra **GitHub → Actions → Publicar Release Oficial**, corrija o problema e execute novamente o workflow informando a tag existente.

O workflow atualiza uma Release já existente e substitui o instalador de mesmo nome, permitindo uma nova tentativa segura para a mesma tag.

## Verificação final

Após a publicação, confirme:

```powershell
git status
git describe --tags --always --dirty
git tag --points-at HEAD
```

O resultado esperado é uma árvore limpa, a nova tag no commit atual e uma Release no GitHub contendo descrição e instalador.
