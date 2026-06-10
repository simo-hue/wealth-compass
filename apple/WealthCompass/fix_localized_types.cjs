const fs = require('fs');
const path = require('path');

const walkSync = (dir, filelist = []) => {
    fs.readdirSync(dir).forEach(file => {
        const dirFile = path.join(dir, file);
        if (fs.statSync(dirFile).isDirectory()) {
            filelist = walkSync(dirFile, filelist);
        } else if (dirFile.endsWith('.swift')) {
            filelist.push(dirFile);
        }
    });
    return filelist;
};

const files = walkSync('/Users/simo/Developer/wealth-compass-1/apple/WealthCompass/Sources');

let totalReplaced = 0;

files.forEach(file => {
    let content = fs.readFileSync(file, 'utf8');
    let original = content;

    // We want to replace String(localized: ...) with LocalizedStringKey(...)
    // ONLY for title: and value: arguments in specific components.
    
    // It's easier to just replace `title: String(localized: ` with `title: LocalizedStringKey(`
    // and then fix SettingsSection and SettingsRow back to String if needed.
    
    // A better approach: replace `title: String(localized: ` with `title: LocalizedStringKey(`
    // and `value: String(localized:` with `value: LocalizedStringKey(`.
    content = content.replace(/title:\s*String\(localized:/g, 'title: LocalizedStringKey(');
    content = content.replace(/value:\s*String\(localized:/g, 'value: LocalizedStringKey(');
    content = content.replace(/subtitle:\s*String\(localized:/g, 'subtitle: LocalizedStringKey(');
    
    // Now, we know SettingsSection, SettingsRow, categoryGroup, credentialRow take `String`.
    // Let's fix them back.
    // We can just revert it for SettingsSection and SettingsRow.
    content = content.replace(/SettingsSection\(title:\s*LocalizedStringKey\(/g, 'SettingsSection(title: String(localized: ');
    content = content.replace(/SettingsRow\(title:\s*LocalizedStringKey\(/g, 'SettingsRow(title: String(localized: ');
    content = content.replace(/categoryGroup\([^)]*title:\s*LocalizedStringKey\(/g, match => match.replace('LocalizedStringKey', 'String(localized:'));
    content = content.replace(/credentialRow\(\s*title:\s*LocalizedStringKey\(/g, 'credentialRow(\n                    title: String(localized: ');
    
    // Also `performanceCard(title:`
    content = content.replace(/performanceCard\(title:\s*LocalizedStringKey\(/g, 'performanceCard(title: String(localized: ');

    // Also MacCashFlowAlert.message(title: message:)
    content = content.replace(/\.message\(title:\s*LocalizedStringKey\(/g, '.message(title: String(localized: ');
    content = content.replace(/message:\s*LocalizedStringKey\(/g, 'message: String(localized: ');
    
    // Fix EmptyState because it takes LocalizedStringKey, wait, let's make sure EmptyState takes LocalizedStringKey.
    // In DesignSystem.swift, EmptyState(title: LocalizedStringKey ...)

    if (content !== original) {
        fs.writeFileSync(file, content);
        totalReplaced++;
        console.log(`Updated ${file}`);
    }
});

console.log(`Done! Modified ${totalReplaced} files.`);
