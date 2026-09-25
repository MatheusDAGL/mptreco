# MPTreco

Aplicação desktop feita com HTML, CSS, JavaScript e Electron. A interface permite:

- inserir um link de um site compatível com o yt-dlp;
- escolher entre vídeo MP4 e áudio MP3;
- selecionar a pasta de destino;
- acompanhar o progresso;
- cancelar um download em andamento.

## Aviso de uso

Baixe somente conteúdos que sejam seus, estejam em domínio público ou para os quais você tenha autorização. O uso da ferramenta deve respeitar direitos autorais e os termos aplicáveis ao conteúdo e à plataforma.

## Requisitos

- Windows 10/11, Linux ou macOS;
- Node.js 20 ou superior;
- acesso à internet durante a instalação e durante os downloads.

Não é necessário instalar manualmente o yt-dlp ou o FFmpeg. O comando `npm install` prepara as ferramentas na pasta `bin`.

## Instalação e inicialização

Abra um terminal na pasta do projeto e execute:

```bash
npm install
npm start
```

No Windows, também é possível executar:

```text
INSTALAR_E_INICIAR.bat
```

Depois da primeira instalação, use:

```text
INICIAR.bat
```

ou:

```bash
npm start
```

## Estrutura

```text
mptreco/
├── src/
│   ├── principal.js
│   ├── preload.js
│   └── interface/
│       ├── index.html
│       ├── estilos.css
│       └── interface.js
├── scripts/
│   └── preparar-ferramentas.js
├── bin/                    # criada automaticamente
├── package.json
├── INSTALAR_E_INICIAR.bat
└── INICIAR.bat
```

## Observações

- A opção MP3 usa o FFmpeg para extrair e converter o áudio.
- A opção Vídeo tenta gerar um arquivo MP4 com áudio incorporado.
- O projeto aceita URLs HTTP e HTTPS de sites compatíveis com o yt-dlp.
- Links de playlists do YouTube são baixados em uma subpasta com o nome da playlist.
- O programa não usa `exec()` nem concatenação de comandos. Os argumentos são enviados separadamente ao processo `yt-dlp`.
