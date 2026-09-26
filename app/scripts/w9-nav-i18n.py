#!/usr/bin/env python3
"""W9 — clé de navigation de l'écran « Anomalies d'absence » (fr/en/ar)."""
import json
import collections

LABELS = {
    'fr': "Anomalies d'absence",
    'en': 'Absence anomalies',
    'ar': 'تناقضات الغياب',
}

for lang, label in LABELS.items():
    path = 'src/i18n/locales/%s/nav.json' % lang
    with open(path, encoding='utf-8') as fh:
        doc = json.load(fh, object_pairs_hook=collections.OrderedDict)
    items = doc['items']
    rebuilt = collections.OrderedDict()
    for key, value in items.items():
        rebuilt[key] = value
        if key == 'leavePlanning':
            rebuilt['absenceAnomalies'] = label
    if 'absenceAnomalies' not in rebuilt:
        rebuilt['absenceAnomalies'] = label
    doc['items'] = rebuilt
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=2)
        fh.write('\n')
    print('ok', path)
