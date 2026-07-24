@echo off
setlocal
title Gerar instalador do MPTreco

cd /d "%~dp0"
if errorlevel 1 goto :erro_pasta

if not exist "package.json" goto :erro_package

where node >nul 2>nul
if errorlevel 1 goto :erro_node

where npm >nul 2>nul
if errorlevel 1 goto :erro_npm

if not exist "node_modules\electron-builder" goto :erro_dependencias

echo.
echo Gerando o instalador do MPTreco...
call npm run dist

if errorlevel 1 goto :erro_build

echo.
echo Instalador gerado com sucesso na pasta dist.
echo.
pause
exit /b 0

:erro_pasta
echo.
echo Nao foi possivel acessar a pasta do projeto.
goto :falha

:erro_package
echo.
echo O arquivo package.json nao foi encontrado nesta pasta.
goto :falha

:erro_node
echo.
echo Node.js nao foi encontrado.
echo Instale o Node.js 20 ou superior e execute este arquivo novamente.
goto :falha

:erro_npm
echo.
echo O npm nao foi encontrado.
echo Reinstale o Node.js incluindo o npm.
goto :falha

:erro_dependencias
echo.
echo As dependencias ainda nao foram instaladas.
echo Execute primeiro o arquivo INSTALAR_E_INICIAR.bat.
goto :falha

:erro_build
echo.
echo A geracao do instalador falhou. Verifique as mensagens acima.

:falha
echo.
pause
exit /b 1
