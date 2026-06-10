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

    content = content.replace(/value:\s*LocalizedStringKey\(/g, 'value: String(localized: ');

    if (content !== original) {
        fs.writeFileSync(file, content);
        totalReplaced++;
        console.log(`Updated ${file}`);
    }
});

console.log(`Done! Modified ${totalReplaced} files.`);
