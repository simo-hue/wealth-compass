const fs = require('fs');

const docPath = '../../DOCUMENTATION.md';
const date = new Date().toLocaleString();
const newEntry = `
- [${date}]: Internationalization (i18n) via String Catalogs
  - *Details*: Implemented a scalable localization strategy for macOS and iOS apps using Xcode's String Catalogs (.xcstrings). The app now automatically detects the device language and gracefully falls back to English if the language is unsupported.
  - *Tech Notes*:
    - Created \`apple/WealthCompass/Sources/Shared/Resources/Localizable.xcstrings\`.
    - Updated \`WealthCompass.xcodeproj\` to enable Base Internationalization.
    - Added language regions: \`it\`, \`de\`, \`es\`, \`zh-Hans\`, \`ar\`.
    - Extracted and automatically translated all strings.
`;

if (fs.existsSync(docPath)) {
  fs.appendFileSync(docPath, newEntry, 'utf8');
} else {
  fs.writeFileSync(docPath, newEntry, 'utf8');
}
console.log("Root DOCUMENTATION.md updated.");
