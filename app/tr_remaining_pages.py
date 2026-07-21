#!/usr/bin/env python3
"""Add missing i18n keys for remaining pages: AuditLog, Currencies, DataExport,
BIReporting, BudgetTracking, FinancialDashboard, Import, Workspace."""
import json
import os

LOCALES = os.path.join(os.path.dirname(__file__), 'src', 'i18n', 'locales')

TRANSLATIONS = {
    # ── settings.json: auditLog extensions ──
    'settings.auditLog.breadcrumb': {'fr': 'Système', 'en': 'System', 'ar': 'النظام'},
    'settings.auditLog.breadcrumb2': {'fr': "Journal d'audit", 'en': 'Audit log', 'ar': 'سجل التدقيق'},
    'settings.auditLog.subtitle2': {'fr': "Traçabilité des actions utilisateur", 'en': 'User action traceability', 'ar': 'تتبع إجراءات المستخدم'},
    'settings.auditLog.allEntities': {'fr': 'Toutes les entités', 'en': 'All entities', 'ar': 'جميع الكيانات'},
    'settings.auditLog.allActions': {'fr': 'Toutes les actions', 'en': 'All actions', 'ar': 'جميع الإجراءات'},
    'settings.auditLog.number': {'fr': 'N°', 'en': 'No.', 'ar': 'رقم'},
    'settings.auditLog.description': {'fr': 'Description', 'en': 'Description', 'ar': 'الوصف'},
    'settings.auditLog.noEntries': {'fr': 'Aucune entrée', 'en': 'No entries', 'ar': 'لا توجد إدخالات'},
    'settings.auditLog.noEntriesDescription': {"fr": "Le journal d'audit est vide.", 'en': 'The audit log is empty.', 'ar': 'سجل التدقيق فارغ.'},
    'settings.auditLog.system': {'fr': 'Système', 'en': 'System', 'ar': 'النظام'},
    'settings.auditLog.search': {'fr': 'Rechercher...', 'en': 'Search...', 'ar': 'بحث...'},
    'settings.auditLog.entityTypes.invoice': {'fr': 'Factures', 'en': 'Invoices', 'ar': 'الفواتير'},
    'settings.auditLog.entityTypes.purchase_invoice': {'fr': "Factures d'achat", 'en': 'Purchase invoices', 'ar': 'فواتير الشراء'},
    'settings.auditLog.entityTypes.journal_entry': {'fr': 'Écritures', 'en': 'Journal entries', 'ar': 'القيود'},
    'settings.auditLog.entityTypes.customer': {'fr': 'Clients', 'en': 'Customers', 'ar': 'العملاء'},
    'settings.auditLog.entityTypes.supplier': {'fr': 'Fournisseurs', 'en': 'Suppliers', 'ar': 'الموردون'},
    'settings.auditLog.entityTypes.employee': {'fr': 'Employés', 'en': 'Employees', 'ar': 'الموظفون'},
    'settings.auditLog.entityTypes.pay_run': {'fr': 'Campagnes de paie', 'en': 'Pay runs', 'ar': 'حملات الرواتب'},
    'settings.auditLog.entityTypes.fixed_asset': {'fr': 'Immobilisations', 'en': 'Fixed assets', 'ar': 'الأصول الثابتة'},
    'settings.auditLog.entityTypes.bank_transaction': {'fr': 'Transactions bancaires', 'en': 'Bank transactions', 'ar': 'المعاملات البنكية'},
    'settings.auditLog.actions.create': {'fr': 'Création', 'en': 'Create', 'ar': 'إنشاء'},
    'settings.auditLog.actions.update': {'fr': 'Modification', 'en': 'Update', 'ar': 'تعديل'},
    'settings.auditLog.actions.delete': {'fr': 'Suppression', 'en': 'Delete', 'ar': 'حذف'},
    'settings.auditLog.actions.login': {'fr': 'Connexion', 'en': 'Login', 'ar': 'تسجيل الدخول'},
    'settings.auditLog.actions.logout': {'fr': 'Déconnexion', 'en': 'Logout', 'ar': 'تسجيل الخروج'},
    'settings.auditLog.actions.transfer': {'fr': 'Transfert', 'en': 'Transfer', 'ar': 'تحويل'},
    'settings.auditLog.actions.validate': {'fr': 'Validation', 'en': 'Validate', 'ar': 'اعتماد'},
    'settings.auditLog.actions.close': {'fr': 'Clôture', 'en': 'Close', 'ar': 'إغلاق'},
    'settings.auditLog.actions.export': {'fr': 'Export', 'en': 'Export', 'ar': 'تصدير'},

    # ── settings.json: currencies extensions ──
    'settings.currencies.breadcrumb': {'fr': 'Paramètres', 'en': 'Settings', 'ar': 'الإعدادات'},
    'settings.currencies.breadcrumb2': {'fr': 'Devises', 'en': 'Currencies', 'ar': 'العملات'},
    'settings.currencies.subtitle2': {'fr': 'Gérez les devises et taux de change', 'en': 'Manage currencies and exchange rates', 'ar': 'إدارة العملات وأسعار الصرف'},
    'settings.currencies.deleteConfirm': {'fr': 'Supprimer cette devise ?', 'en': 'Delete this currency?', 'ar': 'حذف هذه العملة؟'},
    'settings.currencies.setBase': {'fr': 'Définir comme base', 'en': 'Set as base', 'ar': 'تعيين كعملة أساسية'},
    'settings.currencies.actions': {'fr': 'Actions', 'en': 'Actions', 'ar': 'إجراءات'},
    'settings.currencies.base': {'fr': 'Base', 'en': 'Base', 'ar': 'أساسية'},
    'settings.currencies.codeLabel': {'fr': 'Code (3 lettres)', 'en': 'Code (3 letters)', 'ar': 'الرمز (3 أحرف)'},
    'settings.currencies.symbolLabel': {'fr': 'Symbole', 'en': 'Symbol', 'ar': 'الرمز'},
    'settings.currencies.nameLabel': {'fr': 'Nom', 'en': 'Name', 'ar': 'الاسم'},
    'settings.currencies.rateLabel': {'fr': 'Taux de change', 'en': 'Exchange rate', 'ar': 'سعر الصرف'},
    'settings.currencies.codePlaceholder': {'fr': 'EUR', 'en': 'EUR', 'ar': 'EUR'},
    'settings.currencies.symbolPlaceholder': {'fr': '€', 'en': '€', 'ar': '€'},
    'settings.currencies.namePlaceholder': {'fr': 'Euro', 'en': 'Euro', 'ar': 'يورو'},
    'settings.currencies.cancel': {'fr': 'Annuler', 'en': 'Cancel', 'ar': 'إلغاء'},
    'settings.currencies.createBtn': {'fr': 'Créer', 'en': 'Create', 'ar': 'إنشاء'},
    'settings.currencies.noCurrenciesAdd': {'fr': 'Ajoutez votre première devise.', 'en': 'Add your first currency.', 'ar': 'أضف عملتك الأولى.'},
    'settings.currencies.loadError': {'fr': 'Erreur lors du chargement', 'en': 'Error loading data', 'ar': 'خطأ في تحميل البيانات'},

    # ── settings.json: dataExport extensions ──
    'settings.dataExport.breadcrumb': {'fr': 'Paramètres', 'en': 'Settings', 'ar': 'الإعدادات'},
    'settings.dataExport.breadcrumb2': {'fr': 'Export des données', 'en': 'Data export', 'ar': 'تصدير البيانات'},
    'settings.dataExport.titleFull': {'fr': 'Export complet des données', 'en': 'Full data export', 'ar': 'تصدير كامل للبيانات'},
    'settings.dataExport.subtitleFull': {'fr': 'Récupérez toutes vos données — souveraineté garantie', 'en': 'Retrieve all your data — sovereignty guaranteed', 'ar': 'استرجع جميع بياناتك — السيادة مضمونة'},
    'settings.dataExport.startExport': {'fr': "Lancer l'export", 'en': 'Start export', 'ar': 'بدء التصدير'},
    'settings.dataExport.exporting': {'fr': 'Export en cours...', 'en': 'Exporting...', 'ar': 'جاري التصدير...'},
    'settings.dataExport.sovereignty': {'fr': 'Souveraineté de vos données', 'en': 'Data sovereignty', 'ar': 'سيادة البيانات'},
    'settings.dataExport.sovereigntyDesc': {'fr': "Cet outil récupère <strong>toutes</strong> les données stockées sur Supabase et vous permet de les télécharger au format SQL (importable dans PostgreSQL) ou CSV (importable dans Excel). Vous pouvez faire cet export quand vous voulez, y compris après la fin de votre abonnement.", 'en': 'This tool retrieves <strong>all</strong> data stored on Supabase and lets you download it in SQL format (importable to PostgreSQL) or CSV (importable to Excel). You can do this export anytime, even after your subscription ends.', 'ar': 'هذه الأداة تسترجع <strong>جميع</strong> البيانات المخزنة على Supabase وتتيح لك تنزيلها بصيغة SQL (قابلة للاستيراد في PostgreSQL) أو CSV (قابلة للاستيراد في Excel). يمكنك إجراء هذا التصدير في أي وقت، حتى بعد انتهاء اشتراكك.'},
    'settings.dataExport.retrievingData': {'fr': 'Récupération des données en cours...', 'en': 'Retrieving data...', 'ar': 'جاري استرجاع البيانات...'},
    'settings.dataExport.retrievingDesc': {'fr': "Cette opération peut prendre 30-60 secondes selon le volume.", 'en': 'This operation may take 30-60 seconds depending on volume.', 'ar': 'قد تستغرق هذه العملية 30-60 ثانية حسب حجم البيانات.'},
    'settings.dataExport.exportDone': {'fr': 'Export terminé', 'en': 'Export complete', 'ar': 'اكتمل التصدير'},
    'settings.dataExport.exportDoneDesc': {'fr': '{{rows}} lignes sur {{tables}} tables', 'en': '{{rows}} rows across {{tables}} tables', 'ar': '{{rows}} صف في {{tables}} جدول'},
    'settings.dataExport.exportDate': {'fr': "Date d'export", 'en': 'Export date', 'ar': 'تاريخ التصدير'},
    'settings.dataExport.downloadSql': {'fr': 'Télécharger SQL', 'en': 'Download SQL', 'ar': 'تنزيل SQL'},
    'settings.dataExport.downloadCsv': {'fr': 'Télécharger CSV global', 'en': 'Download CSV (all)', 'ar': 'تنزيل CSV (الكل)'},
    'settings.dataExport.downloadJson': {'fr': 'Télécharger JSON', 'en': 'Download JSON', 'ar': 'تنزيل JSON'},
    'settings.dataExport.tablesWithData': {'fr': 'Tables avec données ({{count}})', 'en': 'Tables with data ({{count}})', 'ar': 'جداول بالبيانات ({{count}})'},
    'settings.dataExport.emptyTables': {'fr': 'Tables vides ({{count}})', 'en': 'Empty tables ({{count}})', 'ar': 'جداول فارغة ({{count}})'},
    'settings.dataExport.table': {'fr': 'Table', 'en': 'Table', 'ar': 'الجدول'},
    'settings.dataExport.rows': {'fr': 'Lignes', 'en': 'Rows', 'ar': 'الصفوف'},
    'settings.dataExport.columns': {'fr': 'Colonnes', 'en': 'Columns', 'ar': 'الأعمدة'},
    'settings.dataExport.estimatedSize': {'fr': 'Taille estimée', 'en': 'Estimated size', 'ar': 'الحجم المقدر'},
    'settings.dataExport.action': {'fr': 'Action', 'en': 'Action', 'ar': 'إجراء'},
    'settings.dataExport.noExport': {'fr': "Aucun export effectué", 'en': 'No export performed', 'ar': 'لم يتم أي تصدير'},
    'settings.dataExport.noExportDesc': {"fr": "Cliquez sur « Lancer l'export » pour récupérer toutes vos données depuis Supabase.", 'en': 'Click "Start export" to retrieve all your data from Supabase.', 'ar': 'انقر على "بدء التصدير" لاسترجاع جميع بياناتك من Supabase.'},
    'settings.dataExport.mirrorTitle': {'fr': 'Serveur miroir local', 'en': 'Local mirror server', 'ar': 'خادم النسخ المحلي'},
    'settings.dataExport.mirrorDesc': {'fr': "Installez un programme sur un ordinateur de votre entreprise pour répliquer automatiquement toutes vos données.", 'en': 'Install a program on a computer in your company to automatically replicate all your data.', 'ar': 'قم بتثبيت برنامج على كمبيوتر في شركتك لنسخ جميع بياناتك تلقائياً.'},
    'settings.dataExport.checkingStatus': {'fr': 'Vérification du statut...', 'en': 'Checking status...', 'ar': 'جاري التحقق من الحالة...'},
    'settings.dataExport.mirrorActive': {'fr': 'Serveur miroir actif et vérifié', 'en': 'Mirror server active and verified', 'ar': 'خادم النسخ نشط وموثق'},
    'settings.dataExport.machine': {'fr': 'Machine', 'en': 'Machine', 'ar': 'الجهاز'},
    'settings.dataExport.verifiedOn': {'fr': 'Vérifié le', 'en': 'Verified on', 'ar': 'موثق في'},
    'settings.dataExport.refresh': {'fr': 'Actualiser', 'en': 'Refresh', 'ar': 'تحديث'},
    'settings.dataExport.tablesSynced': {'fr': 'tables synchronisées', 'en': 'tables synced', 'ar': 'جداول متزامنة'},
    'settings.dataExport.totalRows': {'fr': 'lignes au total', 'en': 'total rows', 'ar': 'إجمالي الصفوف'},
    'settings.dataExport.tablesWithDataShort': {'fr': 'tables avec données', 'en': 'tables with data', 'ar': 'جداول بالبيانات'},
    'settings.dataExport.installPending': {'fr': 'Installation en cours...', 'en': 'Installation in progress...', 'ar': 'جاري التثبيت...'},
    'settings.dataExport.installPendingDesc': {'fr': "En attente de la première synchronisation depuis le serveur local. Le statut se met à jour automatiquement.", 'en': 'Waiting for first synchronization from the local server. Status updates automatically.', 'ar': 'في انتظار أول مزامنة من الخادم المحلي. يتم تحديث الحالة تلقائياً.'},
    'settings.dataExport.installFailed': {'fr': "Échec de l'installation", 'en': 'Installation failed', 'ar': 'فشل التثبيت'},
    'settings.dataExport.installFailedDesc': {'fr': 'La vérification a échoué. Réinstallez le serveur miroir.', 'en': 'Verification failed. Reinstall the mirror server.', 'ar': 'فشل التحقق. أعد تثبيت خادم النسخ.'},
    'settings.dataExport.reinstallMac': {'fr': 'Réinstaller sur Mac', 'en': 'Reinstall on Mac', 'ar': 'إعادة التثبيت على Mac'},
    'settings.dataExport.reinstallWindows': {'fr': 'Réinstaller sur Windows', 'en': 'Reinstall on Windows', 'ar': 'إعادة التثبيت على Windows'},
    'settings.dataExport.chooseSystem': {'fr': "Choisissez votre système et téléchargez le programme d'installation. Exécutez-le sur l'ordinateur qui servira de serveur miroir. Un seul serveur miroir par entreprise est autorisé.", 'en': 'Choose your system and download the installer. Run it on the computer that will serve as mirror server. Only one mirror server per company is allowed.', 'ar': 'اختر نظامك وحمّل برنامج التثبيت. قم بتشغيله على الكمبيوتر الذي سيكون خادم النسخ. يُسمح بخادم نسخ واحد فقط لكل شركة.'},
    'settings.dataExport.installMac': {'fr': 'Installer sur Mac', 'en': 'Install on Mac', 'ar': 'تثبيت على Mac'},
    'settings.dataExport.installWindows': {'fr': 'Installer sur Windows', 'en': 'Install on Windows', 'ar': 'تثبيت على Windows'},
    'settings.dataExport.noTenant': {'fr': 'Aucune entreprise associée à votre compte', 'en': 'No company associated with your account', 'ar': 'لا توجد شركة مرتبطة بحسابك'},
    'settings.dataExport.downloadTitle': {'fr': 'Téléchargement', 'en': 'Download', 'ar': 'تنزيل'},
    'settings.dataExport.sqlDownloaded': {'fr': 'Fichier SQL téléchargé', 'en': 'SQL file downloaded', 'ar': 'تم تنزيل ملف SQL'},
    'settings.dataExport.csvDownloaded': {'fr': 'Fichier CSV global téléchargé', 'en': 'CSV file downloaded', 'ar': 'تم تنزيل ملف CSV'},
    'settings.dataExport.jsonDownloaded': {'fr': 'Fichier JSON téléchargé', 'en': 'JSON file downloaded', 'ar': 'تم تنزيل ملف JSON'},
    'settings.dataExport.installerDownloaded': {'fr': 'Installer téléchargé', 'en': 'Installer downloaded', 'ar': 'تم تنزيل المثبت'},
    'settings.dataExport.exportError': {'fr': 'Erreur export', 'en': 'Export error', 'ar': 'خطأ في التصدير'},
    'settings.dataExport.rowsRetrieved': {'fr': '{{rows}} lignes récupérées sur {{tables}} tables', 'en': '{{rows}} rows retrieved across {{tables}} tables', 'ar': 'تم استرجاع {{rows}} صف من {{tables}} جدول'},

    # ── settings.json: import extensions ──
    'settings.import.breadcrumb': {'fr': 'Paramètres', 'en': 'Settings', 'ar': 'الإعدادات'},
    'settings.import.breadcrumb2': {'fr': 'Import de données', 'en': 'Data import', 'ar': 'استيراد البيانات'},
    'settings.import.subtitleFull': {'fr': 'Importez vos données existantes depuis Excel ou CSV, module par module', 'en': 'Import your existing data from Excel or CSV, module by module', 'ar': 'استورد بياناتك الحالية من Excel أو CSV، وحدة بوحدة'},
    'settings.import.permissionDenied': {'fr': "Seuls les administrateurs et comptables peuvent importer des données.", 'en': 'Only administrators and accountants can import data.', 'ar': 'يمكن للمسؤولين والمحاسبين فقط استيراد البيانات.'},
    'settings.import.recommendedOrder': {'fr': "Ordre d'import recommandé.", 'en': 'Recommended import order.', 'ar': 'ترتيب الاستيراد الموصى به.'},
    'settings.import.recommendedOrderDesc': {'fr': "Importez dans l'ordre affiché : le plan comptable d'abord, puis les tiers (clients/fournisseurs), puis les produits. Les factures et écritures s'appuient sur ces référentiels.", 'en': 'Import in the displayed order: chart of accounts first, then third parties (customers/suppliers), then products. Invoices and entries depend on these references.', 'ar': 'استورد بالترتيب المعروض: دليل الحسابات أولاً، ثم الأطراف (العملاء/الموردين)، ثم المنتجات. الفواتير والقيود تعتمد على هذه المراجع.'},
    'settings.import.step': {'fr': 'Étape', 'en': 'Step', 'ar': 'خطوة'},
    'settings.import.importBtn': {'fr': 'Importer', 'en': 'Import', 'ar': 'استيراد'},
    'settings.import.templateBtn': {'fr': 'Modèle Excel', 'en': 'Excel template', 'ar': 'قالب Excel'},
    'settings.import.importModule': {'fr': 'Importer : {{label}}', 'en': 'Import: {{label}}', 'ar': 'استيراد: {{label}}'},
    'settings.import.uploadDesc': {'fr': 'Téléchargez le modèle, remplissez-le, puis chargez votre fichier (.xlsx ou .csv).', 'en': 'Download the template, fill it in, then upload your file (.xlsx or .csv).', 'ar': 'حمّل القالب، املأه، ثم ارفع ملفك (.xlsx أو .csv).'},
    'settings.import.clickToChoose': {'fr': 'Cliquez pour choisir un fichier', 'en': 'Click to choose a file', 'ar': 'انقر لاختيار ملف'},
    'settings.import.acceptedFormats': {'fr': 'Formats acceptés : .xlsx, .xls, .csv', 'en': 'Accepted formats: .xlsx, .xls, .csv', 'ar': 'الصيغ المقبولة: .xlsx, .xls, .csv'},
    'settings.import.back': {'fr': 'Retour', 'en': 'Back', 'ar': 'رجوع'},
    'settings.import.downloadTemplate': {'fr': 'Télécharger le modèle', 'en': 'Download template', 'ar': 'تنزيل القالب'},
    'settings.import.autoDetection': {'fr': 'Détection automatique', 'en': 'Automatic detection', 'ar': 'الكشف التلقائي'},
    'settings.import.fieldsMapped': {'fr': '{{mapped}}/{{total}} champs mappés automatiquement.', 'en': '{{mapped}}/{{total}} fields auto-mapped.', 'ar': '{{mapped}}/{{total}} حقل تم تعيينه تلقائياً.'},
    'settings.import.fieldsToMap': {'fr': '{{count}} champ(s) à associer manuellement.', 'en': '{{count}} field(s) to map manually.', 'ar': '{{count}} حقل للتعيين يدوياً.'},
    'settings.import.unassignedColumns': {'fr': '{{count}} colonne(s) non assignée(s).', 'en': '{{count}} unassigned column(s).', 'ar': '{{count}} عمود غير معين.'},
    'settings.import.aiAnalysis': {'fr': 'Analyse IA...', 'en': 'AI analysis...', 'ar': 'تحليل الذكاء الاصطناعي...'},
    'settings.import.aiDetection': {'fr': 'Auto-détection IA', 'en': 'AI auto-detection', 'ar': 'كشف الذكاء الاصطناعي'},
    'settings.import.hide': {'fr': 'Masquer', 'en': 'Hide', 'ar': 'إخفاء'},
    'settings.import.preview': {'fr': 'Aperçu', 'en': 'Preview', 'ar': 'معاينة'},
    'settings.import.previewRows': {'fr': 'Aperçu des 5 premières lignes', 'en': 'Preview of first 5 rows', 'ar': 'معاينة أول 5 صفوف'},
    'settings.import.unassigned': {'fr': 'non assignée', 'en': 'unassigned', 'ar': 'غير معين'},
    'settings.import.unrecognizedColumns': {'fr': 'Colonnes non reconnues :', 'en': 'Unrecognized columns:', 'ar': 'أعمدة غير معروفة:'},
    'settings.import.unrecognizedDesc': {'fr': "Ces colonnes de votre fichier n'ont été associées à aucun champ. Si elles contiennent des données utiles, associez-les manuellement ci-dessous.", 'en': 'These columns from your file were not matched to any field. If they contain useful data, map them manually below.', 'ar': 'لم يتم ربط هذه الأعمدة من ملفك بأي حقل. إذا كانت تحتوي على بيانات مفيدة، اربطها يدوياً أدناه.'},
    'settings.import.columnMapping': {'fr': 'Correspondance des colonnes — {{count}} ligne(s)', 'en': 'Column mapping — {{count}} row(s)', 'ar': 'تعيين الأعمدة — {{count}} صف'},
    'settings.import.mappingDesc': {'fr': "Vérifiez l'auto-détection et ajustez si nécessaire. Les champs marqués * sont obligatoires.", 'en': 'Review the auto-detection and adjust if needed. Fields marked * are required.', 'ar': 'راجع الكشف التلقائي وعدّل إذا لزم الأمر. الحقول المميزة بـ * إلزامية.'},
    'settings.import.ignore': {'fr': '— Ignorer —', 'en': '— Ignore —', 'ar': '— تجاهل —'},
    'settings.import.notDetected': {'fr': 'non détecté', 'en': 'not detected', 'ar': 'غير مكتشف'},
    'settings.import.importRows': {'fr': 'Importer {{count}} ligne(s)', 'en': 'Import {{count}} row(s)', 'ar': 'استيراد {{count}} صف'},
    'settings.import.importDone': {'fr': 'Import terminé', 'en': 'Import complete', 'ar': 'اكتمل الاستيراد'},
    'settings.import.importResult': {'fr': '{{inserted}} ligne(s) importée(s), {{failed}} en échec.', 'en': '{{inserted}} row(s) imported, {{failed}} failed.', 'ar': 'تم استيراد {{inserted}} صف، فشل {{failed}}.'},
    'settings.import.errorsLabel': {'fr': 'Erreurs ({{count}}) :', 'en': 'Errors ({{count}}):', 'ar': 'أخطاء ({{count}}):'},
    'settings.import.importAnother': {'fr': 'Importer un autre module', 'en': 'Import another module', 'ar': 'استيراد وحدة أخرى'},
    'settings.import.emptyFile': {'fr': 'Fichier vide', 'en': 'Empty file', 'ar': 'ملف فارغ'},
    'settings.import.emptyFileDesc': {'fr': 'Aucune ligne détectée dans le fichier.', 'en': 'No rows detected in the file.', 'ar': 'لم يتم اكتشاف صفوف في الملف.'},
    'settings.import.columnsDetected': {'fr': 'Colonnes détectées', 'en': 'Columns detected', 'ar': 'تم اكتشاف الأعمدة'},
    'settings.import.partialMapping': {'fr': 'Mapping partiel', 'en': 'Partial mapping', 'ar': 'تعيين جزئي'},
    'settings.import.manualMappingRequired': {'fr': 'Mapping manuel requis', 'en': 'Manual mapping required', 'ar': 'التعيين اليدوي مطلوب'},
    'settings.import.readError': {'fr': 'Erreur de lecture', 'en': 'Read error', 'ar': 'خطأ في القراءة'},
    'settings.import.importSuccess': {'fr': 'Import terminé', 'en': 'Import complete', 'ar': 'اكتمل الاستيراد'},
    'settings.import.aiUnavailable': {'fr': 'IA indisponible', 'en': 'AI unavailable', 'ar': 'الذكاء الاصطناعي غير متاح'},
    'settings.import.aiUnavailableDesc': {"fr": "Le service d'auto-détection IA n'est pas accessible. Associez les colonnes manuellement.", 'en': 'The AI auto-detection service is not accessible. Map columns manually.', 'ar': 'خدمة الكشف بالذكاء الاصطناعي غير متاحة. اربط الأعمدة يدوياً.'},
    'settings.import.aiDone': {'fr': 'Détection IA terminée', 'en': 'AI detection complete', 'ar': 'اكتمل الكشف بالذكاء الاصطناعي'},
    'settings.import.aiError': {'fr': 'Erreur IA', 'en': 'AI error', 'ar': 'خطأ الذكاء الاصطناعي'},

    # ── accounting.json: bi section ──
    'accounting.bi.breadcrumb': {'fr': 'Reporting', 'en': 'Reporting', 'ar': 'التقارير'},
    'accounting.bi.breadcrumb2': {'fr': 'BI Reporting', 'en': 'BI Reporting', 'ar': 'تقارير ذكاء الأعمال'},
    'accounting.bi.title': {'fr': 'BI Reporting', 'en': 'BI Reporting', 'ar': 'تقارير ذكاء الأعمال'},
    'accounting.bi.subtitle': {'fr': 'Rapports personnalisés et export', 'en': 'Custom reports and export', 'ar': 'تقارير مخصصة وتصدير'},
    'accounting.bi.exportCsv': {'fr': 'Export CSV', 'en': 'Export CSV', 'ar': 'تصدير CSV'},
    'accounting.bi.revenue': {'fr': "Chiffre d'affaires", 'en': 'Revenue', 'ar': 'الإيرادات'},
    'accounting.bi.expenses': {'fr': 'Dépenses', 'en': 'Expenses', 'ar': 'المصاريف'},
    'accounting.bi.grossMargin': {'fr': 'Marge brute', 'en': 'Gross margin', 'ar': 'الهامش الإجمالي'},
    'accounting.bi.detailedData': {'fr': 'Données détaillées', 'en': 'Detailed data', 'ar': 'البيانات التفصيلية'},
    'accounting.bi.indicator': {'fr': 'Indicateur', 'en': 'Indicator', 'ar': 'المؤشر'},
    'accounting.bi.value': {'fr': 'Valeur', 'en': 'Value', 'ar': 'القيمة'},
    'accounting.bi.customers': {'fr': 'Clients', 'en': 'Customers', 'ar': 'العملاء'},
    'accounting.bi.suppliers': {'fr': 'Fournisseurs', 'en': 'Suppliers', 'ar': 'الموردون'},
    'accounting.bi.products': {'fr': 'Produits', 'en': 'Products', 'ar': 'المنتجات'},
    'accounting.bi.customerInvoices': {'fr': 'Factures clients', 'en': 'Customer invoices', 'ar': 'فواتير العملاء'},
    'accounting.bi.supplierInvoices': {'fr': 'Factures fournisseurs', 'en': 'Supplier invoices', 'ar': 'فواتير الموردين'},
    'accounting.bi.journalEntries': {'fr': 'Écritures comptables', 'en': 'Journal entries', 'ar': 'القيود المحاسبية'},
    'accounting.bi.bankBalance': {'fr': 'Solde bancaire total', 'en': 'Total bank balance', 'ar': 'إجمالي الرصيد البنكي'},
    'accounting.bi.reportTypes.summary': {'fr': 'Synthèse générale', 'en': 'General summary', 'ar': 'ملخص عام'},
    'accounting.bi.reportTypes.sales': {'fr': 'Ventes', 'en': 'Sales', 'ar': 'المبيعات'},
    'accounting.bi.reportTypes.purchases': {'fr': 'Achats', 'en': 'Purchases', 'ar': 'المشتريات'},
    'accounting.bi.reportTypes.financial': {'fr': 'Financier', 'en': 'Financial', 'ar': 'مالي'},
    'accounting.bi.noData': {'fr': 'Aucune donnée', 'en': 'No data', 'ar': 'لا توجد بيانات'},
    'accounting.bi.noDataDesc': {'fr': 'Les données ne sont pas disponibles.', 'en': 'Data is not available.', 'ar': 'البيانات غير متاحة.'},

    # ── accounting.json: budgets extensions ──
    'accounting.budgets.breadcrumb': {'fr': 'Reporting', 'en': 'Reporting', 'ar': 'التقارير'},
    'accounting.budgets.breadcrumb2': {'fr': 'Suivi budgétaire', 'en': 'Budget tracking', 'ar': 'تتبع الميزانية'},
    'accounting.budgets.titleTracking': {'fr': 'Suivi budgétaire', 'en': 'Budget tracking', 'ar': 'تتبع الميزانية'},
    'accounting.budgets.subtitleTracking': {'fr': 'Réalisé vs budget — analyse des écarts', 'en': 'Actual vs budget — variance analysis', 'ar': 'الفعلي مقابل الميزانية — تحليل الانحرافات'},
    'accounting.budgets.allFiscalYears': {'fr': 'Tous les exercices', 'en': 'All fiscal years', 'ar': 'جميع السنوات المالية'},
    'accounting.budgets.exportCsv': {'fr': 'Export CSV', 'en': 'Export CSV', 'ar': 'تصدير CSV'},
    'accounting.budgets.noBudget': {'fr': 'Aucun budget', 'en': 'No budget', 'ar': 'لا توجد ميزانية'},
    'accounting.budgets.noBudgetDesc': {'fr': "Aucun budget n'a été défini pour cet exercice.", 'en': 'No budget has been defined for this fiscal year.', 'ar': 'لم يتم تحديد ميزانية لهذه السنة المالية.'},
    'accounting.budgets.account': {'fr': 'Compte', 'en': 'Account', 'ar': 'الحساب'},
    'accounting.budgets.label': {'fr': 'Libellé', 'en': 'Label', 'ar': 'الوصف'},
    'accounting.budgets.budget': {'fr': 'Budget', 'en': 'Budget', 'ar': 'الميزانية'},
    'accounting.budgets.realized': {'fr': 'Réalisé', 'en': 'Actual', 'ar': 'المحقق'},
    'accounting.budgets.committed': {'fr': 'Engagé', 'en': 'Committed', 'ar': 'الملتزم'},
    'accounting.budgets.available': {'fr': 'Disponible', 'en': 'Available', 'ar': 'المتاح'},
    'accounting.budgets.variance': {'fr': 'Écart', 'en': 'Variance', 'ar': 'الانحراف'},
    'accounting.budgets.variancePct': {'fr': 'Écart %', 'en': 'Variance %', 'ar': 'الانحراف %'},
    'accounting.budgets.status': {'fr': 'Statut', 'en': 'Status', 'ar': 'الحالة'},
    'accounting.budgets.withinBudget': {'fr': 'Dans le budget', 'en': 'Within budget', 'ar': 'ضمن الميزانية'},
    'accounting.budgets.overrun': {'fr': 'Dépassement', 'en': 'Overrun', 'ar': 'تجاوز'},

    # ── accounting.json: financialDashboard section ──
    'accounting.financialDashboard.breadcrumb': {'fr': 'Reporting', 'en': 'Reporting', 'ar': 'التقارير'},
    'accounting.financialDashboard.breadcrumb2': {'fr': 'Tableau de bord financier', 'en': 'Financial dashboard', 'ar': 'لوحة المؤشرات المالية'},
    'accounting.financialDashboard.title': {'fr': 'Tableau de bord financier', 'en': 'Financial dashboard', 'ar': 'لوحة المؤشرات المالية'},
    'accounting.financialDashboard.subtitle': {'fr': 'KPIs financiers en temps réel', 'en': 'Real-time financial KPIs', 'ar': 'مؤشرات مالية في الوقت الفعلي'},
    'accounting.financialDashboard.revenue': {'fr': "Chiffre d'affaires", 'en': 'Revenue', 'ar': 'الإيرادات'},
    'accounting.financialDashboard.expenses': {'fr': 'Dépenses', 'en': 'Expenses', 'ar': 'المصاريف'},
    'accounting.financialDashboard.netMargin': {'fr': 'Marge nette', 'en': 'Net margin', 'ar': 'صافي الهامش'},
    'accounting.financialDashboard.cashPosition': {'fr': 'Position trésorerie', 'en': 'Cash position', 'ar': 'الوضع النقدي'},
    'accounting.financialDashboard.accountingIndicators': {'fr': 'Indicateurs comptables', 'en': 'Accounting indicators', 'ar': 'المؤشرات المحاسبية'},
    'accounting.financialDashboard.indicator': {'fr': 'Indicateur', 'en': 'Indicator', 'ar': 'المؤشر'},
    'accounting.financialDashboard.value': {'fr': 'Valeur', 'en': 'Value', 'ar': 'القيمة'},
    'accounting.financialDashboard.pendingEntries': {'fr': 'Écritures en attente', 'en': 'Pending entries', 'ar': 'قيود معلقة'},
    'accounting.financialDashboard.totalEntries': {'fr': 'Total écritures', 'en': 'Total entries', 'ar': 'إجمالي القيود'},
    'accounting.financialDashboard.paidCustomerInvoices': {'fr': 'Factures clients payées', 'en': 'Paid customer invoices', 'ar': 'فواتير العملاء المدفوعة'},
    'accounting.financialDashboard.paidSupplierInvoices': {'fr': 'Factures fournisseurs payées', 'en': 'Paid supplier invoices', 'ar': 'فواتير الموردين المدفوعة'},
    'accounting.financialDashboard.quickAccess': {'fr': 'Accès rapides', 'en': 'Quick access', 'ar': 'وصول سريع'},
    'accounting.financialDashboard.generalLedger': {'fr': 'Grand-livre', 'en': 'General ledger', 'ar': 'الدفتر العام'},
    'accounting.financialDashboard.trialBalance': {'fr': 'Balance', 'en': 'Trial balance', 'ar': 'ميزان المراجعة'},
    'accounting.financialDashboard.budgetTracking': {'fr': 'Suivi budgétaire', 'en': 'Budget tracking', 'ar': 'تتبع الميزانية'},
    'accounting.financialDashboard.treasury': {'fr': 'Trésorerie', 'en': 'Treasury', 'ar': 'الخزينة'},
    'accounting.financialDashboard.noData': {'fr': 'Aucune donnée', 'en': 'No data', 'ar': 'لا توجد بيانات'},
    'accounting.financialDashboard.noDataDesc': {'fr': 'Les données financières ne sont pas disponibles.', 'en': 'Financial data is not available.', 'ar': 'البيانات المالية غير متاحة.'},

    # ── common.json: workspace section ──
    'common.workspace.breadcrumb': {'fr': 'Tableaux de bord', 'en': 'Dashboards', 'ar': 'لوحات التحكم'},
    'common.workspace.breadcrumb2': {'fr': 'Mon espace', 'en': 'My workspace', 'ar': 'مساحتي'},
    'common.workspace.title': {'fr': 'Mon espace de travail', 'en': 'My workspace', 'ar': 'مساحة عملي'},
    'common.workspace.subtitle': {'fr': 'Personnalisez votre tableau de bord avec des widgets', 'en': 'Customize your dashboard with widgets', 'ar': 'خصص لوحة التحكم بالعناصر'},
    'common.workspace.configure': {'fr': 'Configurer', 'en': 'Configure', 'ar': 'تكوين'},
    'common.workspace.reset': {'fr': 'Réinitialiser', 'en': 'Reset', 'ar': 'إعادة تعيين'},
    'common.workspace.availableWidgets': {'fr': 'Widgets disponibles', 'en': 'Available widgets', 'ar': 'العناصر المتاحة'},
    'common.workspace.noWidgets': {'fr': 'Aucun widget affiché. Cliquez sur "Configurer" pour ajouter des widgets.', 'en': 'No widgets displayed. Click "Configure" to add widgets.', 'ar': 'لا توجد عناصر معروضة. انقر على "تكوين" لإضافة عناصر.'},
    'common.workspace.loadError': {'fr': 'Erreur', 'en': 'Error', 'ar': 'خطأ'},
    'common.workspace.loadErrorDesc': {"fr": "Erreur lors du chargement de l'espace de travail", 'en': 'Error loading workspace', 'ar': 'خطأ في تحميل مساحة العمل'},
    'common.workspace.widgets.salesSummary': {'fr': 'Ventes — Résumé', 'en': 'Sales — Summary', 'ar': 'المبيعات — ملخص'},
    'common.workspace.widgets.purchasesSummary': {'fr': 'Achats — Résumé', 'en': 'Purchases — Summary', 'ar': 'المشتريات — ملخص'},
    'common.workspace.widgets.bankSummary': {'fr': 'Trésorerie', 'en': 'Treasury', 'ar': 'الخزينة'},
    'common.workspace.widgets.recentInvoices': {'fr': 'Factures récentes', 'en': 'Recent invoices', 'ar': 'الفواتير الأخيرة'},
    'common.workspace.widgets.lowStock': {'fr': 'Stock bas', 'en': 'Low stock', 'ar': 'مخزون منخفض'},
    'common.workspace.widgets.employees': {'fr': 'Employés', 'en': 'Employees', 'ar': 'الموظفون'},
    'common.workspace.widgets.activeProjects': {'fr': 'Projets actifs', 'en': 'Active projects', 'ar': 'المشاريع النشطة'},
    'common.workspace.widgets.recentQuotes': {'fr': 'Devis récents', 'en': 'Recent quotes', 'ar': 'عروض الأسعار الأخيرة'},
    'common.workspace.totalBilled': {'fr': 'Total facturé', 'en': 'Total billed', 'ar': 'إجمالي الفواتير'},
    'common.workspace.collected': {'fr': 'Encaissé', 'en': 'Collected', 'ar': 'المحصّل'},
    'common.workspace.pending': {'fr': 'En attente', 'en': 'Pending', 'ar': 'معلق'},
    'common.workspace.invoices': {'fr': 'Factures', 'en': 'Invoices', 'ar': 'الفواتير'},
    'common.workspace.totalPurchases': {'fr': 'Total achats', 'en': 'Total purchases', 'ar': 'إجمالي المشتريات'},
    'common.workspace.paid': {'fr': 'Payé', 'en': 'Paid', 'ar': 'مدفوع'},
    'common.workspace.toPay': {'fr': 'À payer', 'en': 'To pay', 'ar': 'للدفع'},
    'common.workspace.purchaseInvoices': {'fr': "Factures d'achat", 'en': 'Purchase invoices', 'ar': 'فواتير الشراء'},
    'common.workspace.totalBalance': {'fr': 'Solde total', 'en': 'Total balance', 'ar': 'إجمالي الرصيد'},
    'common.workspace.transactions': {'fr': 'Transactions', 'en': 'Transactions', 'ar': 'المعاملات'},
    'common.workspace.number': {'fr': 'Numéro', 'en': 'Number', 'ar': 'الرقم'},
    'common.workspace.customer': {'fr': 'Client', 'en': 'Customer', 'ar': 'العميل'},
    'common.workspace.amount': {'fr': 'Montant', 'en': 'Amount', 'ar': 'المبلغ'},
    'common.workspace.status': {'fr': 'Statut', 'en': 'Status', 'ar': 'الحالة'},
    'common.workspace.noInvoices': {'fr': 'Aucune facture', 'en': 'No invoices', 'ar': 'لا توجد فواتير'},
    'common.workspace.product': {'fr': 'Produit', 'en': 'Product', 'ar': 'المنتج'},
    'common.workspace.stock': {'fr': 'Stock', 'en': 'Stock', 'ar': 'المخزون'},
    'common.workspace.threshold': {'fr': 'Seuil', 'en': 'Threshold', 'ar': 'الحد'},
    'common.workspace.noLowStock': {'fr': 'Aucun stock bas', 'en': 'No low stock', 'ar': 'لا يوجد مخزون منخفض'},
    'common.workspace.totalEmployees': {'fr': 'Total employés', 'en': 'Total employees', 'ar': 'إجمالي الموظفين'},
    'common.workspace.active': {'fr': 'Actifs', 'en': 'Active', 'ar': 'نشط'},
    'common.workspace.onLeave': {'fr': 'En congé', 'en': 'On leave', 'ar': 'في إجازة'},
    'common.workspace.payroll': {'fr': 'Masse salariale', 'en': 'Payroll', 'ar': 'كتلة الرواتب'},
    'common.workspace.project': {'fr': 'Projet', 'en': 'Project', 'ar': 'المشروع'},
    'common.workspace.budget': {'fr': 'Budget', 'en': 'Budget', 'ar': 'الميزانية'},
    'common.workspace.profitability': {'fr': 'Rentabilité', 'en': 'Profitability', 'ar': 'الربحية'},
    'common.workspace.noActiveProjects': {'fr': 'Aucun projet actif', 'en': 'No active projects', 'ar': 'لا توجد مشاريع نشطة'},
    'common.workspace.noQuotes': {'fr': 'Aucun devis', 'en': 'No quotes', 'ar': 'لا توجد عروض'},
}


def set_nested(d, path, value):
    keys = path.split('.')
    for k in keys[:-1]:
        if k not in d or not isinstance(d[k], dict):
            d[k] = {}
        d = d[k]
    d[keys[-1]] = value


def main():
    for lang in ['fr', 'en', 'ar']:
        for ns_file, ns_name in [('settings', 'settings'), ('accounting', 'accounting'), ('common', 'common')]:
            fpath = os.path.join(LOCALES, lang, f'{ns_file}.json')
            with open(fpath, 'r', encoding='utf-8') as f:
                data = json.load(f)

            changed = False
            for full_key, translations in TRANSLATIONS.items():
                parts = full_key.split('.', 1)
                namespace, key_path = parts[0], parts[1]
                if namespace != ns_name:
                    continue
                if lang not in translations:
                    continue
                # Check if key already exists
                existing = data
                found = True
                for k in key_path.split('.'):
                    if k not in existing or not isinstance(existing[k], dict):
                        found = False
                        break
                    existing = existing[k]
                if found:
                    continue
                set_nested(data, key_path, translations[lang])
                changed = True

            if changed:
                with open(fpath, 'w', encoding='utf-8') as f:
                    json.dump(data, f, ensure_ascii=False, indent=2)
                print(f'{lang}/{ns_file}.json: updated')

    print('Done!')


if __name__ == '__main__':
    main()
