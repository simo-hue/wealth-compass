const fs = require('fs');

const translations = {
  "Add": { "it": "Aggiungi", "de": "Hinzufügen", "es": "Añadir", "zh-Hans": "添加", "ar": "إضافة" },
  "Add Crypto": { "it": "Aggiungi Cripto", "de": "Krypto hinzufügen", "es": "Añadir Cripto", "zh-Hans": "添加加密货币", "ar": "إضافة عملة مشفرة" },
  "Add Investment": { "it": "Aggiungi Investimento", "de": "Investition hinzufügen", "es": "Añadir Inversión", "zh-Hans": "添加投资", "ar": "إضافة استثمار" },
  "Add Transaction": { "it": "Aggiungi Transazione", "de": "Transaktion hinzufügen", "es": "Añadir Transacción", "zh-Hans": "添加交易", "ar": "إضافة معاملة" },
  "Cancel": { "it": "Annulla", "de": "Abbrechen", "es": "Cancelar", "zh-Hans": "取消", "ar": "إلغاء" },
  "Save": { "it": "Salva", "de": "Speichern", "es": "Guardar", "zh-Hans": "保存", "ar": "حفظ" },
  "Edit": { "it": "Modifica", "de": "Bearbeiten", "es": "Editar", "zh-Hans": "编辑", "ar": "تعديل" },
  "Delete": { "it": "Elimina", "de": "Löschen", "es": "Eliminar", "zh-Hans": "删除", "ar": "حذف" },
  "Dashboard": { "it": "Dashboard", "de": "Dashboard", "es": "Panel", "zh-Hans": "仪表板", "ar": "لوحة القيادة" },
  "Cash Flow": { "it": "Flusso di Cassa", "de": "Cashflow", "es": "Flujo de Caja", "zh-Hans": "现金流", "ar": "التدفق النقدي" },
  "Investments": { "it": "Investimenti", "de": "Investitionen", "es": "Inversiones", "zh-Hans": "投资", "ar": "الاستثمارات" },
  "Crypto": { "it": "Cripto", "de": "Krypto", "es": "Cripto", "zh-Hans": "加密货币", "ar": "عملات مشفرة" },
  "Settings": { "it": "Impostazioni", "de": "Einstellungen", "es": "Ajustes", "zh-Hans": "设置", "ar": "الإعدادات" },
  "Transactions": { "it": "Transazioni", "de": "Transaktionen", "es": "Transacciones", "zh-Hans": "交易", "ar": "المعاملات" },
  "Net Worth": { "it": "Patrimonio Netto", "de": "Reinvermögen", "es": "Patrimonio Neto", "zh-Hans": "净资产", "ar": "صافي الثروة" },
  "NET WORTH": { "it": "PATRIMONIO NETTO", "de": "REINVERMÖGEN", "es": "PATRIMONIO NETTO", "zh-Hans": "净资产", "ar": "صافي الثروة" },
  "ASSETS": { "it": "ATTIVITÀ", "de": "VERMÖGENSWERTE", "es": "ACTIVOS", "zh-Hans": "资产", "ar": "الأصول" },
  "EXPENSES": { "it": "SPESE", "de": "AUSGABEN", "es": "GASTOS", "zh-Hans": "支出", "ar": "النفقات" },
  "TOTAL": { "it": "TOTALE", "de": "GESAMT", "es": "TOTAL", "zh-Hans": "总计", "ar": "المجموع" },
  "Amount": { "it": "Importo", "de": "Betrag", "es": "Importe", "zh-Hans": "金额", "ar": "المبلغ" },
  "Amount (%@)": { "it": "Importo (%@)", "de": "Betrag (%@)", "es": "Importe (%@)", "zh-Hans": "金额 (%@)", "ar": "المبلغ (%@)" },
  "Category": { "it": "Categoria", "de": "Kategorie", "es": "Categoría", "zh-Hans": "类别", "ar": "فئة" },
  "Date": { "it": "Data", "de": "Datum", "es": "Fecha", "zh-Hans": "日期", "ar": "تاريخ" },
  "Description": { "it": "Descrizione", "de": "Beschreibung", "es": "Descripción", "zh-Hans": "描述", "ar": "وصف" },
  "Name": { "it": "Nome", "de": "Name", "es": "Nombre", "zh-Hans": "名称", "ar": "اسم" },
  "Value": { "it": "Valore", "de": "Wert", "es": "Valor", "zh-Hans": "价值", "ar": "قيمة" },
  "Quantity": { "it": "Quantità", "de": "Menge", "es": "Cantidad", "zh-Hans": "数量", "ar": "كمية" },
  "Current Price": { "it": "Prezzo Attuale", "de": "Aktueller Preis", "es": "Precio Actual", "zh-Hans": "当前价格", "ar": "السعر الحالي" },
  "Average Buy Price": { "it": "Prezzo d'Acquisto Medio", "de": "Durchschnittlicher Kaufpreis", "es": "Precio Medio de Compra", "zh-Hans": "平均买入价", "ar": "متوسط سعر الشراء" },
  "Currency": { "it": "Valuta", "de": "Währung", "es": "Divisa", "zh-Hans": "货币", "ar": "عملة" },
  "Base Currency": { "it": "Valuta di Base", "de": "Basiswährung", "es": "Divisa Base", "zh-Hans": "基础货币", "ar": "العملة الأساسية" },
  "Type": { "it": "Tipo", "de": "Typ", "es": "Tipo", "zh-Hans": "类型", "ar": "نوع" },
  "Status": { "it": "Stato", "de": "Status", "es": "Estado", "zh-Hans": "状态", "ar": "حالة" },
  "Position": { "it": "Posizione", "de": "Position", "es": "Posición", "zh-Hans": "头寸", "ar": "مركز" },
  "Symbol": { "it": "Simbolo", "de": "Symbol", "es": "Símbolo", "zh-Hans": "符号", "ar": "رمز" },
  "CoinGecko ID": { "it": "ID CoinGecko", "de": "CoinGecko-ID", "es": "ID CoinGecko", "zh-Hans": "CoinGecko ID", "ar": "معرف CoinGecko" },
  "ISIN / ID": { "it": "ISIN / ID", "de": "ISIN / ID", "es": "ISIN / ID", "zh-Hans": "ISIN / ID", "ar": "ISIN / المعرف" },
  "Geography": { "it": "Geografia", "de": "Geographie", "es": "Geografía", "zh-Hans": "地理", "ar": "جغرافيا" },
  "Sector": { "it": "Settore", "de": "Sektor", "es": "Sector", "zh-Hans": "行业", "ar": "قطاع" },
  "Details": { "it": "Dettagli", "de": "Details", "es": "Detalles", "zh-Hans": "详情", "ar": "تفاصيل" },
  "OK": { "it": "OK", "de": "OK", "es": "Aceptar", "zh-Hans": "确定", "ar": "حسناً" },
  "Yes": { "it": "Sì", "de": "Ja", "es": "Sí", "zh-Hans": "是", "ar": "نعم" },
  "View All": { "it": "Vedi Tutti", "de": "Alle ansehen", "es": "Ver Todos", "zh-Hans": "查看全部", "ar": "عرض الكل" },
  "Search": { "it": "Cerca", "de": "Suchen", "es": "Buscar", "zh-Hans": "搜索", "ar": "بحث" },
  "Wealth Compass": { "it": "Wealth Compass", "de": "Wealth Compass", "es": "Wealth Compass", "zh-Hans": "Wealth Compass", "ar": "Wealth Compass" },
  "Recent Transactions": { "it": "Transazioni Recenti", "de": "Letzte Transaktionen", "es": "Transacciones Recientes", "zh-Hans": "最近交易", "ar": "المعاملات الأخيرة" },
  "Top Holdings": { "it": "Posizioni Principali", "de": "Top-Positionen", "es": "Principales Activos", "zh-Hans": "主要持仓", "ar": "أهم الممتلكات" },
  "Data": { "it": "Dati", "de": "Daten", "es": "Datos", "zh-Hans": "数据", "ar": "بيانات" },
  "iCloud Sync": { "it": "Sincronizzazione iCloud", "de": "iCloud-Synchronisierung", "es": "Sincronización iCloud", "zh-Hans": "iCloud 同步", "ar": "مزامنة iCloud" },
  "Force Sync iCloud": { "it": "Forza Sincronizzazione iCloud", "de": "iCloud-Synchronisierung erzwingen", "es": "Forzar Sincronización iCloud", "zh-Hans": "强制 iCloud 同步", "ar": "فرض مزامنة iCloud" },
  "Storage": { "it": "Archiviazione", "de": "Speicher", "es": "Almacenamiento", "zh-Hans": "存储", "ar": "تخزين" },
  "Local Only": { "it": "Solo Locale", "de": "Nur lokal", "es": "Solo Local", "zh-Hans": "仅本地", "ar": "محلي فقط" },
  "Export JSON...": { "it": "Esporta JSON...", "de": "JSON exportieren...", "es": "Exportar JSON...", "zh-Hans": "导出 JSON...", "ar": "تصدير JSON..." },
  "Import JSON...": { "it": "Importa JSON...", "de": "JSON importieren...", "es": "Importar JSON...", "zh-Hans": "导入 JSON...", "ar": "استيراد JSON..." },
  "Import JSON Backup": { "it": "Importa Backup JSON", "de": "JSON-Backup importieren", "es": "Importar Copia JSON", "zh-Hans": "导入 JSON 备份", "ar": "استيراد نسخة JSON" },
  "Prepare Backup": { "it": "Prepara Backup", "de": "Backup vorbereiten", "es": "Preparar Copia", "zh-Hans": "准备备份", "ar": "إعداد نسخة احتياطية" },
  "Share Backup": { "it": "Condividi Backup", "de": "Backup teilen", "es": "Compartir Copia", "zh-Hans": "分享备份", "ar": "مشاركة النسخة" },
  "Delete All Local Data...": { "it": "Elimina Tutti i Dati Locali...", "de": "Alle lokalen Daten löschen...", "es": "Eliminar Todos los Datos Locales...", "zh-Hans": "删除所有本地数据...", "ar": "حذف جميع البيانات المحلية..." },
  "Delete All Data": { "it": "Elimina Tutti i Dati", "de": "Alle Daten löschen", "es": "Eliminar Todos los Datos", "zh-Hans": "删除所有数据", "ar": "حذف جميع البيانات" },
  "Security": { "it": "Sicurezza", "de": "Sicherheit", "es": "Seguridad", "zh-Hans": "安全", "ar": "أمان" },
  "Privacy": { "it": "Privacy", "de": "Datenschutz", "es": "Privacidad", "zh-Hans": "隐私", "ar": "خصوصية" },
  "Privacy Mode": { "it": "Modalità Privacy", "de": "Datenschutzmodus", "es": "Modo Privacidad", "zh-Hans": "隐私模式", "ar": "وضع الخصوصية" },
  "Privacy on": { "it": "Privacy attiva", "de": "Datenschutz ein", "es": "Privacidad activada", "zh-Hans": "隐私开启", "ar": "الخصوصية مفعلة" },
  "Unlock": { "it": "Sblocca", "de": "Entsperren", "es": "Desbloquear", "zh-Hans": "解锁", "ar": "إلغاء القفل" },
  "Unlock with %@": { "it": "Sblocca con %@", "de": "Mit %@ entsperren", "es": "Desbloquear con %@", "zh-Hans": "使用 %@ 解锁", "ar": "إلغاء القفل باستخدام %@" },
  "Exchange Rates": { "it": "Tassi di Cambio", "de": "Wechselkurse", "es": "Tipos de Cambio", "zh-Hans": "汇率", "ar": "أسعار الصرف" },
  "Refresh Exchange Rates": { "it": "Aggiorna Tassi", "de": "Wechselkurse aktualisieren", "es": "Actualizar Tipos", "zh-Hans": "刷新汇率", "ar": "تحديث أسعار الصرف" },
  "Market Data": { "it": "Dati di Mercato", "de": "Marktdaten", "es": "Datos de Mercado", "zh-Hans": "市场数据", "ar": "بيانات السوق" },
  "Refresh Market Data": { "it": "Aggiorna Mercato", "de": "Marktdaten aktualisieren", "es": "Actualizar Mercado", "zh-Hans": "刷新市场数据", "ar": "تحديث بيانات السوق" },
  "Last Updated": { "it": "Ultimo Aggiornamento", "de": "Zuletzt aktualisiert", "es": "Última Actualización", "zh-Hans": "最后更新", "ar": "آخر تحديث" },
  "Updated %@": { "it": "Aggiornato %@", "de": "Aktualisiert %@", "es": "Actualizado %@", "zh-Hans": "已更新 %@", "ar": "تم التحديث %@" },
  "Snapshots": { "it": "Istantanee", "de": "Schnappschüsse", "es": "Instantáneas", "zh-Hans": "快照", "ar": "لقطات" },
  "Refresh Data": { "it": "Aggiorna Dati", "de": "Daten aktualisieren", "es": "Actualizar Datos", "zh-Hans": "刷新数据", "ar": "تحديث البيانات" }
};

const filePath = 'Sources/Shared/Resources/Localizable.xcstrings';
const rawData = fs.readFileSync(filePath, 'utf8');
const catalog = JSON.parse(rawData);

const languages = ['it', 'de', 'es', 'zh-Hans', 'ar'];

for (const key of Object.keys(catalog.strings)) {
  if (!catalog.strings[key].localizations) {
    catalog.strings[key].localizations = {};
  }
  
  if (translations[key]) {
    for (const lang of languages) {
      if (translations[key][lang]) {
        catalog.strings[key].localizations[lang] = {
          stringUnit: {
            state: "translated",
            value: translations[key][lang]
          }
        };
      }
    }
  } else {
    // For missing translations, just put a placeholder or fallback.
    // In a real scenario we could hit an API.
    for (const lang of languages) {
      if (!catalog.strings[key].localizations[lang]) {
        // Leave it blank or just copy the key for testing
        catalog.strings[key].localizations[lang] = {
          stringUnit: {
            state: "needs_review",
            value: key.replace(/%@/g, "%@") 
          }
        };
      }
    }
  }
}

fs.writeFileSync(filePath, JSON.stringify(catalog, null, 2), 'utf8');
console.log("Translations successfully added to Localizable.xcstrings");
