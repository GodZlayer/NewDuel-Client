@echo off
setlocal

rem Testa o render 3D da tela de selecao de personagem (char select) sem
rem precisar de servidor. Usa o "debug_cmd.txt" ja embutido no cliente
rem (Gunz\main.cpp: ZDebugProcessCommandFile) -- o jogo le esse arquivo a
rem cada ~500ms e, ao ver "simcharselect", monta 1 personagem falso local
rem (ZDebugSimCharSelect) e entra em GUNZ_CHARSELECTION pelo caminho real
rem de codigo (mesmo render/widgets de sempre), sem round-trip de rede.

cd /d "%~dp0"

echo Iniciando Gunz.exe...
start "" "%~dp0Gunz.exe"

echo Aguardando o cliente carregar (tela de login)...
timeout /t 7 /nobreak >nul

echo Enviando comando "simcharselect"...
echo simcharselect> debug_cmd.txt

echo.
echo Pronto. Em ate ~1s o jogo deve pular direto pra char select
echo com um personagem de teste, sem precisar logar em nenhum servidor.
echo.
echo Comandos extras (com o jogo aberto, rode a partir daqui):
echo   echo screenshot^> debug_cmd.txt          (salva screenshot real do backbuffer)
echo   echo simcharselect^> debug_cmd.txt        (repete/re-entra em char select)
echo.
echo Screenshot vai parar em: %%USERPROFILE%%\Documents\Open GunZ\Screenshots
echo Log deste run: %%USERPROFILE%%\Documents\Open GunZ\Logs\mlog_*.txt
echo.
pause
