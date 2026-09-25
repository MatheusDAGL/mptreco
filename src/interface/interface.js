const formularioDownload = document.getElementById('formulario-download');
const campoUrl = document.getElementById('url-conteudo');
const campoPasta = document.getElementById('pasta-destino');
const botaoSelecionarPasta = document.getElementById('botao-selecionar-pasta');
const botaoBaixar = document.getElementById('botao-baixar');
const botaoCancelar = document.getElementById('botao-cancelar');
const barraProgresso = document.getElementById('barra-progresso');
const trilhoProgresso = document.querySelector('.trilho-progresso');
const textoPercentual = document.getElementById('texto-percentual');
const textoStatus = document.getElementById('texto-status');
const textoVelocidade = document.getElementById('texto-velocidade');
const textoTempoRestante = document.getElementById('texto-tempo-restante');
const mensagem = document.getElementById('mensagem');
const versaoAplicacao = document.getElementById('versao-aplicacao');
const botaoAtualizacao = document.getElementById('botao-atualizacao');

let downloadEmAndamento = false;

function mostrarEstadoAtualizacao(estado) {
    const versao = estado?.versao;
    const status = estado?.status;

    botaoAtualizacao.hidden = !versao || status === 'oculto';
    botaoAtualizacao.disabled = status !== 'disponivel' && status !== 'erro';

    if (status === 'disponivel') {
        botaoAtualizacao.textContent = `Nova versão ${versao} disponível. Instalar agora?`;
    } else if (status === 'baixando') {
        botaoAtualizacao.textContent = `Baixando atualização ${versao}: ${estado.percentual || 0}%`;
    } else if (status === 'instalando') {
        botaoAtualizacao.textContent = 'Atualização pronta. Instalando e reiniciando...';
    } else if (status === 'erro') {
        botaoAtualizacao.textContent = 'Falha ao atualizar. Clique para tentar novamente.';
    }
}

botaoAtualizacao.addEventListener('click', async () => {
    botaoAtualizacao.disabled = true;
    try {
        const resultado = await window.apiMPTreco.instalarAtualizacao();

        if (!resultado.sucesso) {
            mostrarMensagem(resultado.mensagem, 'erro');
            mostrarEstadoAtualizacao(await window.apiMPTreco.obterEstadoAtualizacao());
        }
    } catch {
        mostrarMensagem('Não foi possível iniciar a atualização. Tente novamente.', 'erro');
        botaoAtualizacao.disabled = false;
    }
});

window.apiMPTreco.aoAtualizarEstadoAtualizacao(mostrarEstadoAtualizacao);

document.addEventListener('click', evento => {
    const link = evento.target.closest('a[href]');

    if (!link) {
        return;
    }

    evento.preventDefault();
    window.apiMPTreco.abrirLinkExterno(link.href);
});

campoUrl.addEventListener('contextmenu', evento => {
    evento.preventDefault();
    campoUrl.focus();
    window.apiMPTreco.mostrarMenuEdicao();
});

function mostrarMensagem(texto, tipo = 'informacao') {
    mensagem.textContent = texto;
    mensagem.className = `mensagem ${tipo}`;
    mensagem.hidden = false;
}

function mostrarMensagemConclusao(texto) {
    mensagem.textContent = '';
    mensagem.append(document.createTextNode(`${texto} `));

    const botaoAbrirLocal = document.createElement('button');
    botaoAbrirLocal.type = 'button';
    botaoAbrirLocal.className = 'botao-link-mensagem';
    botaoAbrirLocal.textContent = 'Ver na pasta';
    botaoAbrirLocal.addEventListener('click', async () => {
        botaoAbrirLocal.disabled = true;

        try {
            const resultado = await window.apiMPTreco.abrirLocalDoArquivo();

            if (!resultado.sucesso) {
                mostrarMensagem(resultado.mensagem, 'erro');
            }
        } catch {
            mostrarMensagem(
                'NÃ£o foi possÃ­vel abrir o local do arquivo.',
                'erro'
            );
        } finally {
            if (botaoAbrirLocal.isConnected) {
                botaoAbrirLocal.disabled = false;
            }
        }
    });

    mensagem.append(botaoAbrirLocal);
    mensagem.className = 'mensagem sucesso';
    mensagem.hidden = false;
}

function ocultarMensagem() {
    mensagem.textContent = '';
    mensagem.className = 'mensagem';
    mensagem.hidden = true;
}

function alterarEstadoDownload(emAndamento) {
    downloadEmAndamento = emAndamento;
    botaoBaixar.disabled = emAndamento;
    botaoCancelar.disabled = !emAndamento;
    botaoSelecionarPasta.disabled = emAndamento;
    campoUrl.disabled = emAndamento;

    document.querySelectorAll('input[name="formato"]').forEach(campo => {
        campo.disabled = emAndamento;
    });
}

function atualizarProgresso({
    percentual = 0,
    velocidade = '',
    tempoRestante = ''
}) {
    const percentualSeguro = Math.min(
        100,
        Math.max(0, Number(percentual) || 0)
    );

    barraProgresso.style.width = `${percentualSeguro}%`;
    trilhoProgresso.setAttribute(
        'aria-valuenow',
        String(Math.round(percentualSeguro))
    );
    textoPercentual.textContent = `${Math.round(percentualSeguro)}%`;

    textoVelocidade.textContent = velocidade
        ? `Velocidade: ${velocidade}`
        : '';

    textoTempoRestante.textContent = tempoRestante
        ? `Tempo restante: ${tempoRestante}`
        : '';
}

function redefinirProgresso() {
    atualizarProgresso({
        percentual: 0,
        velocidade: '',
        tempoRestante: ''
    });
    textoStatus.textContent = 'Pronto para iniciar.';
}

function obterFormatoSelecionado() {
    const campoSelecionado = document.querySelector(
        'input[name="formato"]:checked'
    );

    return campoSelecionado?.value || '';
}

function validarFormulario() {
    if (!campoUrl.value.trim()) {
        mostrarMensagem('Informe o link do conteúdo.', 'erro');
        campoUrl.focus();
        return false;
    }

    if (!campoPasta.value.trim()) {
        mostrarMensagem('Escolha a pasta de destino.', 'erro');
        botaoSelecionarPasta.focus();
        return false;
    }

    return true;
}

botaoSelecionarPasta.addEventListener('click', async () => {
    ocultarMensagem();

    const resultado = await window.apiMPTreco.selecionarPasta();

    if (!resultado.cancelado) {
        campoPasta.value = resultado.pasta;
    }
});

formularioDownload.addEventListener('submit', async evento => {
    evento.preventDefault();
    ocultarMensagem();

    if (!validarFormulario()) {
        return;
    }

    redefinirProgresso();
    alterarEstadoDownload(true);
    textoStatus.textContent = 'Preparando o download...';

    const resultado = await window.apiMPTreco.iniciarDownload({
        url: campoUrl.value.trim(),
        formato: obterFormatoSelecionado(),
        pastaDestino: campoPasta.value.trim()
    });

    if (!resultado.sucesso) {
        alterarEstadoDownload(false);
        textoStatus.textContent = 'Não foi possível iniciar.';
        mostrarMensagem(resultado.mensagem, 'erro');
    }
});

botaoCancelar.addEventListener('click', async () => {
    if (!downloadEmAndamento) {
        return;
    }

    botaoCancelar.disabled = true;
    textoStatus.textContent = 'Cancelando...';

    const resultado = await window.apiMPTreco.cancelarDownload();

    if (!resultado.sucesso) {
        botaoCancelar.disabled = false;
        mostrarMensagem(resultado.mensagem, 'erro');
    }
});

window.apiMPTreco.aoAtualizarProgresso(dados => {
    atualizarProgresso(dados);
});

window.apiMPTreco.aoAtualizarStatus(dados => {
    if (dados?.mensagem) {
        textoStatus.textContent = dados.mensagem;
    }
});

window.apiMPTreco.aoFinalizarDownload(resultado => {
    alterarEstadoDownload(false);

    if (resultado.sucesso) {
        textoStatus.textContent = resultado.mensagem;
        atualizarProgresso({ percentual: 100 });
        mostrarMensagemConclusao(resultado.mensagem);
        return;
    }

    if (resultado.cancelado) {
        textoStatus.textContent = 'Cancelado.';
        mostrarMensagem(resultado.mensagem, 'informacao');
        return;
    }

    textoStatus.textContent = 'Falha no download.';
    mostrarMensagem(resultado.mensagem, 'erro');
});

async function inicializarAplicacao() {
    const [resultadoFerramentas, resultadoPasta, versao, atualizacao] = await Promise.all([
        window.apiMPTreco.verificarFerramentas(),
        window.apiMPTreco.obterUltimaPasta(),
        window.apiMPTreco.obterVersaoAplicacao(),
        window.apiMPTreco.obterEstadoAtualizacao()
    ]);

    versaoAplicacao.textContent = `Versão ${versao}`;
    mostrarEstadoAtualizacao(atualizacao);

    if (resultadoPasta.pasta) {
        campoPasta.value = resultadoPasta.pasta;
    }

    if (!resultadoFerramentas.pronto) {
        mostrarMensagem(
            `Ferramentas ausentes: ${resultadoFerramentas.ausentes.join(', ')}. Execute "npm install" ou "npm run preparar".`,
            'erro'
        );
    }
}

inicializarAplicacao();
