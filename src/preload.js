const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('apiMPTreco', {
    selecionarPasta: () => ipcRenderer.invoke('selecionar-pasta'),
    obterUltimaPasta: () => ipcRenderer.invoke('obter-ultima-pasta'),
    obterVersaoAplicacao: () => ipcRenderer.invoke('obter-versao-aplicacao'),
    obterEstadoAtualizacao: () => ipcRenderer.invoke('obter-estado-atualizacao'),
    instalarAtualizacao: () => ipcRenderer.invoke('instalar-atualizacao'),
    abrirLinkExterno: url => ipcRenderer.invoke('abrir-link-externo', url),
    abrirLocalDoArquivo: () => ipcRenderer.invoke('abrir-local-do-arquivo'),
    mostrarMenuEdicao: () => ipcRenderer.send('mostrar-menu-edicao'),
    verificarFerramentas: () => ipcRenderer.invoke('verificar-ferramentas'),
    iniciarDownload: dados => ipcRenderer.invoke('iniciar-download', dados),
    cancelarDownload: () => ipcRenderer.invoke('cancelar-download'),

    aoAtualizarEstadoAtualizacao: callback => {
        const ouvinte = (_evento, dados) => callback(dados);
        ipcRenderer.on('estado-atualizacao', ouvinte);
        return () => ipcRenderer.removeListener('estado-atualizacao', ouvinte);
    },

    aoAtualizarProgresso: callback => {
        const ouvinte = (_evento, dados) => callback(dados);
        ipcRenderer.on('download-progresso', ouvinte);
        return () => ipcRenderer.removeListener('download-progresso', ouvinte);
    },

    aoAtualizarStatus: callback => {
        const ouvinte = (_evento, dados) => callback(dados);
        ipcRenderer.on('download-status', ouvinte);
        return () => ipcRenderer.removeListener('download-status', ouvinte);
    },

    aoFinalizarDownload: callback => {
        const ouvinte = (_evento, dados) => callback(dados);
        ipcRenderer.on('download-finalizado', ouvinte);
        return () => ipcRenderer.removeListener('download-finalizado', ouvinte);
    }
});
