@echo off
setlocal
chcp 65001 >nul
title MPTreco

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

if not exist "node_modules\electron" (
    echo.
    echo As dependências ainda não foram instaladas.
    echo Execute primeiro o arquivo INSTALAR_E_INICIAR.bat.
    echo.
    pause
    exit /b 1
)

call npm start

if errorlevel 1 (
    echo.
    echo A aplicação foi encerrada com erro.
    echo.
    pause
)
