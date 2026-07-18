@echo off
setlocal
chcp 65001 >nul
title Instalando MPTreco

rem Sempre executa a partir da pasta onde este arquivo foi salvo.
cd /d "%~dp0" || (
    echo.
    echo Não foi possível acessar a pasta do projeto.
    echo.
    pause
    exit /b 1
)

if not exist "package.json" (
    echo.
    echo O arquivo package.json não foi encontrado nesta pasta.
    echo.
    pause
    exit /b 1
)

where node >nul 2>nul
if errorlevel 1 (
    echo.
    echo Node.js não foi encontrado.
    echo Instale o Node.js 20 ou superior e execute este arquivo novamente.
    echo.
    pause
    exit /b 1
)

where npm >nul 2>nul
if errorlevel 1 (
    echo.
    echo O npm não foi encontrado.
    echo Reinstale o Node.js incluindo o npm.
    echo.
    pause
    exit /b 1
)

echo.
echo Instalando dependências e preparando yt-dlp e FFmpeg...
call npm install

if errorlevel 1 (
    echo.
    echo A instalação falhou. Verifique sua conexão e as mensagens acima.
    echo.
    pause
    exit /b 1
)

echo.
echo Iniciando a aplicação...
call npm start

if errorlevel 1 (
    echo.
    echo A aplicação foi encerrada com erro.
    echo.
    pause
)
