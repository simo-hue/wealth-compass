const fs = require('fs');

const filePath = 'Sources/Shared/Resources/Localizable.xcstrings';
const rawData = fs.readFileSync(filePath, 'utf8');
const catalog = JSON.parse(rawData);

const allAppleRegions = [
  'en', 'fr', 'de', 'it', 'ja', 'ko', 'pt-BR', 'pt-PT', 'ru', 'es', 'es-419', 
  'tr', 'ar', 'ca', 'hr', 'cs', 'da', 'nl', 'fi', 'el', 'he', 'hi', 'hu', 
  'id', 'ms', 'no', 'pl', 'ro', 'sk', 'sv', 'th', 'uk', 'vi', 'zh-Hans', 'zh-Hant'
];

for (const key of Object.keys(catalog.strings)) {
  if (!catalog.strings[key].localizations) {
    catalog.strings[key].localizations = {};
  }
  
  for (const lang of allAppleRegions) {
    // Keep 'en' as is or whatever is already translated
    if (!catalog.strings[key].localizations[lang] && lang !== 'en') {
      catalog.strings[key].localizations[lang] = {
        stringUnit: {
          state: "needs_review",
          value: key.replace(/%@/g, "%@") 
        }
      };
    }
  }
}

fs.writeFileSync(filePath, JSON.stringify(catalog, null, 2), 'utf8');
console.log("Added all Apple supported languages to Localizable.xcstrings as 'needs_review'.");
