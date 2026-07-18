const fs = require('node:fs');
const path = require('node:path');
const https = require('node:https');

const caminhoRaiz = path.resolve(__dirname, '..');
const caminhoBinarios = path.join(caminhoRaiz, 'bin');

function obterConfiguracaoYtDlp() {
    const plataforma = process.platform;
    const arquitetura = process.arch;

    if (plataforma === 'win32') {
        return {
            nomeArquivo: 'yt-dlp.exe',
            url: 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
        };
    }

    if (plataforma === 'darwin') {
        return {
            nomeArquivo: 'yt-dlp',
            url: 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos'
        };
    }

    if (plataforma === 'linux' && arquitetura === 'arm64') {
        return {
            nomeArquivo: 'yt-dlp',
            url: 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_aarch64'
        };
    }

    if (plataforma === 'linux') {
        return {
            nomeArquivo: 'yt-dlp',
            url: 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux'
        };
    }

    throw new Error(`Plataforma não suportada automaticamente: ${plataforma}/${arquitetura}`);
}

function baixarArquivo(url, caminhoDestino, quantidadeRedirecionamentos = 0) {
    return new Promise((resolver, rejeitar) => {
        if (quantidadeRedirecionamentos > 10) {
            rejeitar(new Error('Quantidade máxima de redirecionamentos excedida.'));
            return;
        }

        const arquivoTemporario = `${caminhoDestino}.download`;
        const arquivo = fs.createWriteStream(arquivoTemporario);

        const requisicao = https.get(
            url,
            {
                headers: {
                    'User-Agent': 'MPTreco/1.0'
                }
            },
            resposta => {
                const codigo = resposta.statusCode || 0;

                if ([301, 302, 303, 307, 308].includes(codigo) && resposta.headers.location) {
                    arquivo.close();
                    fs.rmSync(arquivoTemporario, { force: true });

                    const proximaUrl = new URL(resposta.headers.location, url).toString();
                    baixarArquivo(
                        proximaUrl,
                        caminhoDestino,
                        quantidadeRedirecionamentos + 1
                    ).then(resolver).catch(rejeitar);
                    return;
                }

                if (codigo < 200 || codigo >= 300) {
                    arquivo.close();
                    fs.rmSync(arquivoTemporario, { force: true });
                    rejeitar(new Error(`Falha no download: HTTP ${codigo}`));
                    return;
                }

                resposta.pipe(arquivo);

                arquivo.on('finish', () => {
                    arquivo.close(() => {
                        fs.renameSync(arquivoTemporario, caminhoDestino);
                        resolver();
                    });
                });
            }
        );

        requisicao.setTimeout(120000, () => {
            requisicao.destroy(new Error('Tempo limite excedido ao baixar o yt-dlp.'));
        });

        requisicao.on('error', erro => {
            arquivo.close();
            fs.rmSync(arquivoTemporario, { force: true });
            rejeitar(erro);
        });
    });
}

function copiarBinario(caminhoOrigem, caminhoDestino) {
    if (!caminhoOrigem || !fs.existsSync(caminhoOrigem)) {
        throw new Error(`Binário não encontrado: ${caminhoOrigem || 'caminho vazio'}`);
    }

    fs.copyFileSync(caminhoOrigem, caminhoDestino);

    if (process.platform !== 'win32') {
        fs.chmodSync(caminhoDestino, 0o755);
    }
}

async function prepararFerramentas() {
    fs.mkdirSync(caminhoBinarios, { recursive: true });

    const configuracaoYtDlp = obterConfiguracaoYtDlp();
    const caminhoYtDlp = path.join(caminhoBinarios, configuracaoYtDlp.nomeArquivo);

    console.log('Baixando a versão oficial mais recente do yt-dlp...');
    await baixarArquivo(configuracaoYtDlp.url, caminhoYtDlp);

    if (process.platform !== 'win32') {
        fs.chmodSync(caminhoYtDlp, 0o755);
    }

    const caminhoFfmpegOrigem = require('ffmpeg-static');
    const caminhoFfprobeOrigem = require('ffprobe-static').path;

    const extensao = process.platform === 'win32' ? '.exe' : '';
    const caminhoFfmpegDestino = path.join(caminhoBinarios, `ffmpeg${extensao}`);
    const caminhoFfprobeDestino = path.join(caminhoBinarios, `ffprobe${extensao}`);

    console.log('Preparando FFmpeg e FFprobe...');
    copiarBinario(caminhoFfmpegOrigem, caminhoFfmpegDestino);
    copiarBinario(caminhoFfprobeOrigem, caminhoFfprobeDestino);

    console.log(`Ferramentas preparadas em: ${caminhoBinarios}`);
}

prepararFerramentas().catch(erro => {
    console.error('');
    console.error('Não foi possível preparar as ferramentas.');
    console.error(erro.message);
    console.error('');
    process.exitCode = 1;
});
