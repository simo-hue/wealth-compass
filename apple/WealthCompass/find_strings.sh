#!/bin/bash
find Sources -name "*.swift" -type f | while read file; do
  # Find lines with quotes but exclude common SwiftUI localization patterns
  grep -n '"' "$file" \
    | grep -v 'String(localized:' \
    | grep -v 'Text("' \
    | grep -v 'Label("' \
    | grep -v 'Button("' \
    | grep -v 'Picker("' \
    | grep -v 'navigationTitle("' \
    | grep -v 'Section("' \
    | grep -v 'Alert(title: Text("' \
    | grep -v 'Image(systemName: "' \
    | grep -v 'systemImage: "' \
    | grep -v 'UserDefaults' \
    | grep -v 'DateFormatter' \
    | grep -v 'NSPredicate' \
    | grep -v 'id: \\.self' \
    | grep -v 'Notification.Name' \
    | grep -v 'fatalError' \
    | grep -v 'print(' \
    | grep -v 'Logger' \
    | grep -v 'identifier:' \
    | grep -v 'wc_mobile' \
    | awk -v fname="$file" '{print fname ":" $0}'
done
