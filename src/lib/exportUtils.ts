import { toast } from "sonner";

/**
 * Exports data to a CSV file.
 * @param data Array of objects to export.
 * @param filename Desired filename (without extension).
 * @param headers Optional array of headers (if not provided, keys of first object are used).
 */
export function exportToCsv(data: any[], filename: string, headers?: string[]) {
    try {
        if (!data || data.length === 0) {
            toast.warning("No data to export");
            return;
        }

        const keys = headers || Object.keys(data[0]);

        // CSV Header
        const csvContent = [
            keys.join(','),
            ...data.map(row =>
                keys.map(key => {
                    const val = row[key];
                    // Handle strings with commas, quotes, or newlines
                    if (typeof val === 'string') {
                        return `"${val.replace(/"/g, '""')}"`;
                    }
                    // Format Date objects or other types if needed
                    return val;
                }).join(',')
            )
        ].join('\n');

        const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
        const link = document.createElement('a');
        const url = URL.createObjectURL(blob);

        link.setAttribute('href', url);
        link.setAttribute('download', `${filename}.csv`);
        link.style.visibility = 'hidden';

        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);

        toast.success("CSV export downloaded");
    } catch (e) {
        console.error("Export failed", e);
        toast.error("Failed to export CSV");
    }
}

/**
 * Exports raw data to a JSON file (Backup).
 * @param data Data object to export.
 * @param filename Desired filename (without extension).
 */
export function exportToJson(data: any, filename: string) {
    try {
        const jsonString = JSON.stringify(data, null, 2);
        const blob = new Blob([jsonString], { type: 'application/json' });
        const url = URL.createObjectURL(blob);

        const link = document.createElement('a');
        link.href = url;
        link.download = `${filename}.json`;

        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);

        toast.success("System backup downloaded");
    } catch (e) {
        console.error(e);
        toast.error("Export failed");
    }
}
