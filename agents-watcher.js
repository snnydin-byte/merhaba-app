#!/usr/bin/env node
'use strict';

/**
 * AGENTS_LOG.md izleyicisi.
 *
 * Sadece "Otomatik: Evet" + "Durum: Beklemede" olan görev bloklarını dener.
 * "Ne yapılmalı" alanının metnini AŞAĞIDAKİ SABİT TABLOYLA birebir eşleştirir
 * (serbest metin yorumlanmaz, keyfi komut çalıştırılmaz). Eşleşme yoksa
 * dokunmadan görevi "Onaylanmamış komut - manuel kontrol gerekli" yapar.
 * "Otomatik: Hayır" olan görevlere hiç dokunmaz.
 *
 * Genişletmek için (yeni tetik ifadesi eklemek için) önce Sinan'a sorulur,
 * sonra hem AGENTS_LOG.md'deki tablo hem de APPROVED_COMMANDS burada
 * birlikte güncellenir.
 */

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const LOG_PATH = path.join(__dirname, 'AGENTS_LOG.md');
const POLL_INTERVAL_MS = 2000;

// AGENTS_LOG.md'deki "Otomatik Onaylı Güvenli Komutlar" tablosunun birebir
// karşılığı. Anahtar = "Ne yapılmalı" alanının trim'lenmiş metni.
//
// "uygulamayı başlat" artık `flutter run`'ı doğrudan gizli/arka planda
// başlatmıyor (Sinan görüp hot-reload yapamıyordu - Görev #2). Bunun yerine
// `agents-watcher.code-workspace` dosyasını yeni bir VS Code penceresinde
// açıyor; o workspace'in kendi tasks.json'ı ("runOptions": {"runOn":
// "folderOpen"}) pencere açılır açılmaz `flutter run`ı görünür, etkileşimli
// bir entegre terminalde otomatik başlatıyor (r/R ile hot-reload yapılabilir).
// Bu davranış SADECE bu özel workspace dosyası üzerinden tetiklenir - Sinan
// projeyi normal şekilde (bu workspace dosyası olmadan) açtığında hiçbir şey
// otomatik çalışmaz.
const APPROVED_COMMANDS = {
  'uygulamayı başlat': {
    cmd: 'code',
    args: ['--new-window', path.join(__dirname, 'agents-watcher.code-workspace')],
    cwd: __dirname,
  },
};

let processing = false;

function log(msg) {
  const ts = new Date().toLocaleString('tr-TR');
  console.log(`[${ts}] ${msg}`);
}

function parseTaskBlocks(content) {
  const lines = content.split(/\r?\n/);
  const blocks = [];
  let current = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const headerMatch = line.match(/^### Görev #(\d+)\s*$/);

    if (headerMatch) {
      if (current) blocks.push(current);
      current = { number: headerMatch[1], startLine: i, endLine: i, fields: {}, fieldLineNo: {} };
      continue;
    }

    if (current) {
      // Yeni bir blok/bölüm başlıyorsa mevcut bloğu kapat.
      if (/^---\s*$/.test(line) || /^_\(başka bekleyen görev yok\)_\s*$/.test(line)) {
        current.endLine = i - 1;
        blocks.push(current);
        current = null;
        continue;
      }

      const fieldMatch = line.match(
        /^- (Durum|Otomatik|Ekleyen|Tarih|Etkilenen dosya\(lar\)|Ne yapılmalı|Neden|Test\/doğrulama|Sonuç\/commit):\s*(.*)$/
      );
      if (fieldMatch) {
        const key = fieldMatch[1];
        current.fields[key] = fieldMatch[2].trim();
        current.fieldLineNo[key] = i;
      } else if (/^\s+\S/.test(line) && Object.keys(current.fieldLineNo).length) {
        // Çok satırlı alanların devamı (girintili satır) - son alana ekle.
        const lastKey = Object.keys(current.fieldLineNo).pop();
        current.fields[lastKey] += ' ' + line.trim();
      }
      current.endLine = i;
    }
  }
  if (current) blocks.push(current);
  return blocks;
}

function updateLogFields(lines, block, updates) {
  for (const [key, value] of Object.entries(updates)) {
    const lineNo = block.fieldLineNo[key];
    if (lineNo === undefined) continue;
    const indentMatch = lines[lineNo].match(/^(\s*)- /);
    const prefix = indentMatch ? indentMatch[1] : '';
    lines[lineNo] = `${prefix}- ${key}: ${value}`;
  }
}

function quoteArgIfNeeded(arg) {
  return /\s/.test(arg) ? `"${arg}"` : arg;
}

function runApprovedCommand(commandDef) {
  const fullCommand = [commandDef.cmd, ...commandDef.args.map(quoteArgIfNeeded)].join(' ');
  log(`Komut tetikleniyor: ${fullCommand}`);
  // Tüm komut tek bir sabit string olarak shell'e veriliyor (args ayrı
  // geçilmiyor) - Node'un "shell:true + args dizisi" kombinasyonuna dair
  // deprecation uyarısını (DEP0190) tetiklemeden Windows'taki flutter.bat
  // gibi shell script'lerini çalıştırabilmek için.
  const child = spawn(fullCommand, [], {
    cwd: commandDef.cwd,
    detached: true,
    stdio: 'ignore',
    shell: process.platform === 'win32',
  });
  child.unref();
  return { pid: child.pid, fullCommand };
}

function processFile() {
  if (processing) return;
  processing = true;
  try {
    const content = fs.readFileSync(LOG_PATH, 'utf8');
    const lines = content.split(/\r?\n/);
    const blocks = parseTaskBlocks(content);
    let changed = false;

    for (const block of blocks) {
      const durum = block.fields['Durum'];
      const otomatik = block.fields['Otomatik'];

      if (durum !== 'Beklemede') continue;
      // "Otomatik: Hayır" veya karışık/açıklamalı ifadeler (ör. Görev #1'in
      // kendisi) kesinlikle atlanır - sadece saf "Evet" işlenir.
      if (otomatik !== 'Evet') continue;

      const neYapilmali = (block.fields['Ne yapılmalı'] || '').trim();
      const approved = APPROVED_COMMANDS[neYapilmali.toLowerCase()];

      if (approved) {
        const { pid, fullCommand } = runApprovedCommand(approved);
        const now = new Date().toLocaleString('tr-TR');
        updateLogFields(lines, block, {
          Durum: 'Tamamlandı',
          'Sonuç/commit': `${now} - agents-watcher.js tarafından otomatik çalıştırıldı (\`${fullCommand}\`, pid ${pid}).`,
        });
        log(`Görev #${block.number} tamamlandı olarak işaretlendi.`);
        changed = true;
      } else {
        updateLogFields(lines, block, {
          Durum: 'Onaylanmamış komut - manuel kontrol gerekli',
        });
        log(`Görev #${block.number}: "Ne yapılmalı" tabloyla eşleşmedi, manuel kontrol gerekli olarak işaretlendi.`);
        changed = true;
      }
    }

    if (changed) {
      fs.writeFileSync(LOG_PATH, lines.join('\n'));
    }
  } catch (err) {
    log(`Hata: ${err.message}`);
  } finally {
    processing = false;
  }
}

log(`AGENTS_LOG.md izleniyor: ${LOG_PATH}`);
log(`Onaylı komutlar: ${Object.keys(APPROVED_COMMANDS).map((k) => `"${k}"`).join(', ')}`);
processFile();
fs.watchFile(LOG_PATH, { interval: POLL_INTERVAL_MS }, () => processFile());

process.on('SIGINT', () => {
  log('Durduruluyor (Ctrl+C).');
  process.exit(0);
});
