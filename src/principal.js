const {
    app,
    BrowserWindow,
    dialog,
    ipcMain,
    Menu,
    nativeImage,
    shell
} = require('electron');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

if (process.platform === 'win32') {
    app.setAppUserModelId('com.matheusdagl.mptreco');
}

let janelaPrincipal = null;
let processoDownload = null;
let downloadCancelado = false;
let ultimaPastaDownloadConcluida = '';

function obterCaminhosFerramentas() {
    const extensao = process.platform === 'win32' ? '.exe' : '';
    const caminhoBase = app.isPackaged
        ? path.join(process.resourcesPath, 'bin')
        : path.join(__dirname, '..', 'bin');

    return {
        pastaBinarios: caminhoBase,
        ytDlp: path.join(caminhoBase, `yt-dlp${extensao}`),
        ffmpeg: path.join(caminhoBase, `ffmpeg${extensao}`),
        ffprobe: path.join(caminhoBase, `ffprobe${extensao}`)
    };
}

function criarJanela() {
    const caminhoIcone = path.join(__dirname, 'assets', 'mptreco.ico');
    const iconeAplicacao = nativeImage.createFromPath(caminhoIcone);

    janelaPrincipal = new BrowserWindow({
        width: 760,
        height: 730,
        minWidth: 660,
        minHeight: 540,
        show: false,
        backgroundColor: '#090909',
        icon: iconeAplicacao,
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false,
            sandbox: true
        }
    });

    if (process.platform === 'win32') {
        janelaPrincipal.setIcon(iconeAplicacao);
        janelaPrincipal.setAppDetails({
            appId: 'com.matheusdagl.mptreco',
            appIconPath: caminhoIcone,
            appIconIndex: 0
        });
    }

    Menu.setApplicationMenu(null);
    janelaPrincipal.loadFile(path.join(__dirname, 'interface', 'index.html'));

    janelaPrincipal.once('ready-to-show', () => {
        janelaPrincipal.show();
    });

    janelaPrincipal.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));

    janelaPrincipal.webContents.on('will-navigate', evento => {
        evento.preventDefault();
    });

    janelaPrincipal.on('closed', () => {
        janelaPrincipal = null;
    });
}

function validarUrl(valor) {
    if (typeof valor !== 'string' || valor.length > 2048) {
        return false;
    }

    try {
        const url = new URL(valor.trim());

        if (!['https:', 'http:'].includes(url.protocol)) {
            return false;
        }

        return Boolean(url.hostname);
    } catch {
        return false;
    }
}

function validarPasta(caminhoPasta) {
    if (typeof caminhoPasta !== 'string' || !path.isAbsolute(caminhoPasta)) {
        return false;
    }

    try {
        const estatisticas = fs.statSync(caminhoPasta);
        fs.accessSync(caminhoPasta, fs.constants.W_OK);
        return estatisticas.isDirectory();
    } catch {
        return false;
    }
}

function obterCaminhoPreferencias() {
    return path.join(app.getPath('userData'), 'preferencias.json');
}

function obterUltimaPasta() {
    try {
        const conteudo = fs.readFileSync(obterCaminhoPreferencias(), 'utf8');
        const preferencias = JSON.parse(conteudo);
        const pasta = preferencias?.ultimaPasta;

        return validarPasta(pasta) ? pasta : '';
    } catch {
        return '';
    }
}

function salvarUltimaPasta(pasta) {
    try {
        fs.writeFileSync(
            obterCaminhoPreferencias(),
            JSON.stringify({ ultimaPasta: pasta }, null, 2),
            'utf8'
        );
    } catch (erro) {
        console.error('Não foi possível salvar a última pasta selecionada.', erro);
    }
}

function validarUrlExterna(valor) {
    if (typeof valor !== 'string') {
        return false;
    }

    try {
        const url = new URL(valor);
        return url.protocol === 'https:' && url.hostname === 'github.com';
    } catch {
        return false;
    }
}

function criarArgumentosDownload({ url, formato, pastaDestino }) {
    const ferramentas = obterCaminhosFerramentas();
    const modeloSaida = path.join(
        pastaDestino,
        '%(title).180B [%(id)s].%(ext)s'
    );

    const argumentos = [
        '--no-playlist',
        '--newline',
        '--no-colors',
        '--progress',
        '--progress-template',
        'PROGRESSO:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s',
        '--print',
        'after_move:ARQUIVO_FINAL:%(filepath)s',
        '--ffmpeg-location',
        ferramentas.pastaBinarios,
        '--output',
        modeloSaida
    ];

    if (process.platform === 'win32') {
        argumentos.push('--windows-filenames');
    }

    if (formato === 'mp3') {
        argumentos.push(
            '--extract-audio',
            '--audio-format',
            'mp3',
            '--audio-quality',
            '0',
            '--embed-metadata'
        );
    } else {
        argumentos.push(
            '--format-sort',
            'vcodec:h264,res,acodec:aac',
            '--format',
            'bv*+ba/b',
            '--merge-output-format',
            'mp4'
        );
    }

    argumentos.push(url);
    return argumentos;
}

function enviarParaTela(canal, dados) {
    if (janelaPrincipal && !janelaPrincipal.isDestroyed()) {
        janelaPrincipal.webContents.send(canal, dados);
    }
}

function interpretarLinhaSaida(linha, aoEncontrarArquivoFinal = null) {
    const texto = linha.trim();

    if (!texto) {
        return;
    }

    if (texto.startsWith('PROGRESSO:')) {
        const conteudo = texto.substring('PROGRESSO:'.length);
        const [percentualTexto = '0%', velocidade = '', tempoRestante = ''] =
            conteudo.split('|');

        const percentual = Number.parseFloat(
            percentualTexto.replace('%', '').replace(',', '.').trim()
        );

        enviarParaTela('download-progresso', {
            percentual: Number.isFinite(percentual)
                ? Math.min(100, Math.max(0, percentual))
                : 0,
            velocidade: velocidade.trim(),
            tempoRestante: tempoRestante.trim()
        });
        return;
    }

    if (texto.startsWith('ARQUIVO_FINAL:')) {
        const caminhoArquivo = texto.substring('ARQUIVO_FINAL:'.length).trim();
        aoEncontrarArquivoFinal?.(caminhoArquivo);

        enviarParaTela('download-status', {
            mensagem: `Arquivo salvo: ${caminhoArquivo}`
        });
        return;
    }

    if (texto.includes('[ExtractAudio]')) {
        enviarParaTela('download-progresso', {
            percentual: 96,
            velocidade: '',
            tempoRestante: ''
        });
        enviarParaTela('download-status', {
            mensagem: 'Convertendo o áudio para MP3...'
        });
        return;
    }

    if (
        texto.includes('[Merger]') ||
        texto.includes('[VideoRemuxer]') ||
        texto.includes('[VideoConvertor]')
    ) {
        enviarParaTela('download-progresso', {
            percentual: 96,
            velocidade: '',
            tempoRestante: ''
        });
        enviarParaTela('download-status', {
            mensagem: 'Processando o arquivo de vídeo...'
        });
        return;
    }

    if (texto.includes('[download] Destination:')) {
        enviarParaTela('download-status', {
            mensagem: 'Download iniciado...'
        });
    }
}

function observarFluxo(
    fluxo,
    coletorErros = null,
    aoEncontrarArquivoFinal = null
) {
    let buffer = '';

    fluxo.setEncoding('utf8');

    fluxo.on('data', trecho => {
        buffer += trecho;
        const linhas = buffer.split(/\r?\n/);
        buffer = linhas.pop() || '';

        for (const linha of linhas) {
            interpretarLinhaSaida(linha, aoEncontrarArquivoFinal);

            if (coletorErros && linha.trim()) {
                coletorErros.push(linha.trim());

                if (coletorErros.length > 20) {
                    coletorErros.shift();
                }
            }
        }
    });

    fluxo.on('end', () => {
        if (buffer.trim()) {
            interpretarLinhaSaida(buffer, aoEncontrarArquivoFinal);

            if (coletorErros) {
                coletorErros.push(buffer.trim());
            }
        }
    });
}

function criarMensagemDownloadConcluido(formato, caminhoArquivo) {
    const tipo = formato === 'mp3' ? 'áudio MP3' : 'vídeo MP4';
    const nomeArquivo = caminhoArquivo ? path.basename(caminhoArquivo) : '';

    return nomeArquivo
        ? `Download do ${tipo} "${nomeArquivo}" concluído.`
        : `Download do ${tipo} concluído.`;
}

function encerrarProcessoDownload() {
    if (!processoDownload || processoDownload.killed) {
        return false;
    }

    downloadCancelado = true;

    if (process.platform === 'win32' && processoDownload.pid) {
        const processoEncerramento = spawn(
            'taskkill',
            ['/pid', String(processoDownload.pid), '/t', '/f'],
            {
                windowsHide: true,
                stdio: 'ignore'
            }
        );

        processoEncerramento.unref();
    } else {
        processoDownload.kill('SIGTERM');
    }

    return true;
}

ipcMain.handle('selecionar-pasta', async () => {
    const resultado = await dialog.showOpenDialog(janelaPrincipal, {
        title: 'Escolha a pasta para salvar o arquivo',
        defaultPath: obterUltimaPasta() || undefined,
        properties: ['openDirectory', 'createDirectory']
    });

    if (resultado.canceled || resultado.filePaths.length === 0) {
        return { cancelado: true };
    }

    const pasta = resultado.filePaths[0];
    salvarUltimaPasta(pasta);

    return {
        cancelado: false,
        pasta
    };
});

ipcMain.handle('obter-ultima-pasta', () => ({
    pasta: obterUltimaPasta()
}));

ipcMain.handle('abrir-link-externo', async (_evento, url) => {
    if (!validarUrlExterna(url)) {
        return { sucesso: false };
    }

    await shell.openExternal(url);
    return { sucesso: true };
});

ipcMain.handle('abrir-local-do-arquivo', async () => {
    if (!validarPasta(ultimaPastaDownloadConcluida)) {
        return {
            sucesso: false,
            mensagem: 'A pasta do arquivo baixado não está mais disponível.'
        };
    }

    const erro = await shell.openPath(ultimaPastaDownloadConcluida);

    if (erro) {
        return {
            sucesso: false,
            mensagem: 'Não foi possível abrir a pasta do arquivo baixado.'
        };
    }

    return { sucesso: true };
});

ipcMain.handle('verificar-ferramentas', () => {
    const ferramentas = obterCaminhosFerramentas();
    const ausentes = Object.entries({
        'yt-dlp': ferramentas.ytDlp,
        FFmpeg: ferramentas.ffmpeg,
        FFprobe: ferramentas.ffprobe
    })
        .filter(([, caminhoArquivo]) => !fs.existsSync(caminhoArquivo))
        .map(([nome]) => nome);

    return {
        pronto: ausentes.length === 0,
        ausentes
    };
});

ipcMain.handle('iniciar-download', async (_evento, dados) => {
    if (processoDownload) {
        return {
            sucesso: false,
            mensagem: 'Já existe um download em andamento.'
        };
    }

    const url = typeof dados?.url === 'string' ? dados.url.trim() : '';
    const formato = dados?.formato;
    const pastaDestino = dados?.pastaDestino;

    if (!validarUrl(url)) {
        return {
            sucesso: false,
            mensagem: 'Informe um link HTTP ou HTTPS válido.'
        };
    }

    if (!['video', 'mp3'].includes(formato)) {
        return {
            sucesso: false,
            mensagem: 'Selecione Vídeo ou MP3.'
        };
    }

    if (!validarPasta(pastaDestino)) {
        return {
            sucesso: false,
            mensagem: 'Selecione uma pasta válida com permissão de gravação.'
        };
    }

    const ferramentas = obterCaminhosFerramentas();

    for (const caminhoFerramenta of [
        ferramentas.ytDlp,
        ferramentas.ffmpeg,
        ferramentas.ffprobe
    ]) {
        if (!fs.existsSync(caminhoFerramenta)) {
            return {
                sucesso: false,
                mensagem:
                    'As ferramentas não estão preparadas. Execute "npm install" ou "npm run preparar".'
            };
        }
    }

    const argumentos = criarArgumentosDownload({
        url,
        formato,
        pastaDestino
    });

    const errosRecentes = [];
    let caminhoArquivoFinal = '';
    downloadCancelado = false;

    try {
        processoDownload = spawn(ferramentas.ytDlp, argumentos, {
            shell: false,
            windowsHide: true,
            stdio: ['ignore', 'pipe', 'pipe']
        });
    } catch (erro) {
        processoDownload = null;
        return {
            sucesso: false,
            mensagem: `Não foi possível iniciar o yt-dlp: ${erro.message}`
        };
    }

    enviarParaTela('download-status', {
        mensagem: 'Fazendo download...'
    });

    observarFluxo(
        processoDownload.stdout,
        null,
        caminhoArquivo => {
            caminhoArquivoFinal = caminhoArquivo;
        }
    );
    observarFluxo(processoDownload.stderr, errosRecentes);

    processoDownload.on('error', erro => {
        enviarParaTela('download-finalizado', {
            sucesso: false,
            mensagem: `Falha ao executar o yt-dlp: ${erro.message}`
        });
        processoDownload = null;
    });

    processoDownload.on('close', codigo => {
        const foiCancelado = downloadCancelado;
        processoDownload = null;
        downloadCancelado = false;

        if (foiCancelado) {
            enviarParaTela('download-finalizado', {
                sucesso: false,
                cancelado: true,
                mensagem: 'Download cancelado.'
            });
            return;
        }

        if (codigo === 0) {
            ultimaPastaDownloadConcluida = pastaDestino;
            enviarParaTela('download-progresso', {
                percentual: 100,
                velocidade: '',
                tempoRestante: ''
            });
            enviarParaTela('download-finalizado', {
                sucesso: true,
                mensagem: criarMensagemDownloadConcluido(
                    formato,
                    caminhoArquivoFinal
                )
            });
            return;
        }

        const detalhe = errosRecentes
            .filter(linha => linha.toLowerCase().includes('error'))
            .slice(-3)
            .join(' ');

        enviarParaTela('download-finalizado', {
            sucesso: false,
            mensagem: detalhe
                ? `O download falhou. ${detalhe}`
                : `O yt-dlp foi encerrado com o código ${codigo}.`
        });
    });

    return {
        sucesso: true,
        mensagem: 'Download iniciado.'
    };
});

ipcMain.handle('cancelar-download', () => {
    const cancelado = encerrarProcessoDownload();

    return {
        sucesso: cancelado,
        mensagem: cancelado
            ? 'Cancelamento solicitado.'
            : 'Não existe download em andamento.'
    };
});

app.whenReady().then(criarJanela);

app.on('window-all-closed', () => {
    encerrarProcessoDownload();

    if (process.platform !== 'darwin') {
        app.quit();
    }
});

app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
        criarJanela();
    }
});
