const fs = require('fs');

const docPath = 'DOCUMENTATION.md';
const date = new Date().toLocaleString();
const newEntry = `
- [${date}]: Internationalization (i18n) via String Catalogs
  - *Details*: Implemented a scalable localization strategy for macOS and iOS apps using Xcode's String Catalogs (.xcstrings). The app now automatically detects the device language and gracefully falls back to English if the language is unsupported.
  - *Tech Notes*:
    - Created \`Sources/Shared/Resources/Localizable.xcstrings\`.
    - Updated \`WealthCompass.xcodeproj\` to enable Base Internationalization.
    - Added language regions: \`it\` (Italian), \`de\` (German), \`es\` (Spanish), \`zh-Hans\` (Simplified Chinese), \`ar\` (Arabic).
    - Extracted all English strings automatically via Xcode build system (\`builtin-BuildStringCatalog\`).
    - Bulk translated all keys for the 5 target languages and populated the JSON catalog.
`;

if (fs.existsSync(docPath)) {
  fs.appendFileSync(docPath, newEntry, 'utf8');
} else {
  fs.writeFileSync(docPath, newEntry, 'utf8');
}
console.log("DOCUMENTATION.md updated.");
