const fs = require('fs');
const path = require('path');

const metadataDir = path.join(__dirname, 'fastlane', 'metadata');
const locales = fs.readdirSync(metadataDir).filter(f => fs.statSync(path.join(metadataDir, f)).isDirectory());

const limits = {
  'name.txt': 30,
  'subtitle.txt': 30,
  'promotional_text.txt': 170,
  'keywords.txt': 100
};

for (const locale of locales) {
  for (const [file, maxLen] of Object.entries(limits)) {
    const filePath = path.join(metadataDir, locale, file);
    if (fs.existsSync(filePath)) {
      let content = fs.readFileSync(filePath, 'utf8').trim();
      if (content.length > maxLen) {
        console.log(`Truncating ${locale}/${file} from ${content.length} to ${maxLen} chars.`);
        // Truncate and add ellipsis if it's not keywords
        if (file === 'keywords.txt') {
          // for keywords, just cut at last comma within limit
          let truncated = content.substring(0, maxLen);
          let lastComma = truncated.lastIndexOf(',');
          if (lastComma > 0) {
            truncated = truncated.substring(0, lastComma);
          }
          fs.writeFileSync(filePath, truncated);
        } else {
          // for text, cut and add ..
          let truncated = content.substring(0, maxLen - 2).trim() + '..';
          fs.writeFileSync(filePath, truncated);
        }
      }
    }
  }
}
console.log("Finished enforcing App Store character limits!");
