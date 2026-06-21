#!/usr/bin/env node
/**
 * Fills Localizable.xcstrings using Google Translate (unofficial gtx client).
 * No npm dependencies required.
 */
const fs = require('fs');
const https = require('https');

const catalogPath = 'Sources/Shared/Resources/Localizable.xcstrings';
const TARGET_LANGS = process.argv.includes('--all-langs')
  ? ['ar', 'ca', 'cs', 'da', 'de', 'el', 'es', 'es-419', 'fi', 'fr', 'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'ko', 'ms', 'nb', 'nl', 'pl', 'pt-BR', 'pt-PT', 'ro', 'ru', 'sk', 'sv', 'th', 'tr', 'uk', 'vi', 'zh-Hans', 'zh-Hant']
  : ['es', 'it', 'de', 'fr', 'zh-Hans', 'ar'];
const DELAY_MS = 120;
const MAX_KEYS = process.argv.includes('--all') ? Infinity : 600;

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

function translate(text, toLang) {
  return new Promise((resolve, reject) => {
    const tl = toLang === 'zh-Hans' ? 'zh-CN' : toLang;
    const q = encodeURIComponent(text);
    const url = `https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=${tl}&dt=t&q=${q}`;
    https
      .get(url, (res) => {
        let body = '';
        res.on('data', (chunk) => (body += chunk));
        res.on('end', () => {
          try {
            const parsed = JSON.parse(body);
            const translated = parsed?.[0]?.map((part) => part[0]).join('') ?? text;
            resolve(translated);
          } catch (error) {
            reject(error);
          }
        });
      })
      .on('error', reject);
  });
}

function needsTranslation(key, entry, lang) {
  const loc = entry?.localizations?.[lang]?.stringUnit;
  if (!loc) return true;
  const value = (loc.value ?? '').trim();
  if (!value) return true;
  if (value === key) return true;
  return false;
}

function protectPlaceholders(text) {
  const tokens = [];
  const protectedText = text.replace(/%(\d+\$)?[@lldlf]+/g, (match) => {
    const token = `__PH${tokens.length}__`;
    tokens.push(match);
    return token;
  });
  return { protectedText, tokens };
}

function restorePlaceholders(text, tokens) {
  let result = text;
  tokens.forEach((token, index) => {
    result = result.replace(`__PH${index}__`, token);
    result = result.replace(`__ ph${index}__`, token);
    result = result.replace(new RegExp(`__\\s*PH${index}\\s*__`, 'gi'), token);
  });
  return result;
}

async function run() {
  const catalog = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
  const keys = Object.keys(catalog.strings).filter((key) => key.trim().length > 0);
  let updated = 0;

  for (const key of keys) {
    if (updated >= MAX_KEYS) break;
    const entry = catalog.strings[key];
    if (!entry.localizations) entry.localizations = {};

    for (const lang of TARGET_LANGS) {
      if (updated >= MAX_KEYS) break;
      if (!needsTranslation(key, entry, lang)) continue;

      const { protectedText, tokens } = protectPlaceholders(key);
      try {
        const raw = await translate(protectedText, lang);
        const value = restorePlaceholders(raw, tokens);
        entry.localizations[lang] = {
          stringUnit: { state: 'translated', value },
        };
        updated++;
        if (updated % 25 === 0) {
          console.log(`Translated ${updated}… latest [${lang}] ${key.slice(0, 50)}`);
          fs.writeFileSync(catalogPath, JSON.stringify(catalog, null, 2));
        }
        await delay(DELAY_MS);
      } catch (error) {
        console.warn(`Skip [${lang}] "${key.slice(0, 40)}": ${error.message}`);
      }
    }
  }

  fs.writeFileSync(catalogPath, JSON.stringify(catalog, null, 2));
  console.log(`Done. Wrote ${updated} localization entries.`);
}

run().catch((error) => {
  console.error(error);
  process.exit(1);
});
