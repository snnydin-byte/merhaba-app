@echo off
cd /d "%~dp0"
title AGENTS_LOG.md izleyici
echo AGENTS_LOG.md izleyici baslatiliyor. Durdurmak icin bu pencereyi kapat ya da Ctrl+C.
node agents-watcher.js
pause
