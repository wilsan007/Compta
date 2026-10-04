#!/usr/bin/env python3
"""W9 — ajoute les clés i18n du chaînage de l'absence (fr/en/ar), à l'identique."""
import json
import collections

BASE = 'src/i18n/locales/%s/hr.json'

ADD_TYPES = {
    'fr': {'rtt': 'RTT', 'recovery': 'Récupération', 'parental': 'Congé parental',
           'personal': 'Absence personnelle', 'mission': 'Mission'},
    'en': {'rtt': 'RTT', 'recovery': 'Time off in lieu', 'parental': 'Parental leave',
           'personal': 'Personal absence', 'mission': 'Business trip'},
    'ar': {'rtt': 'رصيد الراحات', 'recovery': 'استرداد ساعات', 'parental': 'إجازة أبوية',
           'personal': 'غياب شخصي', 'mission': 'مهمة'},
}

ABS = {
    'fr': ('Anomalies d\'absence',
           "Les journées qui portent une absence ET un pointage, des heures supplémentaires, du temps projet ou une ligne de frais. Le contrôle nomme, il ne répare pas.",
           'Aucune anomalie sur la période',
           "Le registre d'absence et les saisies concordent.",
           'Salarié', 'Jour', 'Absence', 'Incohérence', 'Détail', 'Du', 'Au', 'Recalculer'),
    'en': ('Absence anomalies',
           'Days that carry an absence AND a time entry, overtime, project time or an expense line. The check names them; it does not fix them.',
           'No anomaly in this period',
           'The absence registry and the entries agree.',
           'Employee', 'Day', 'Absence', 'Conflict', 'Detail', 'From', 'To', 'Refresh'),
    'ar': ('تناقضات الغياب',
           'الأيام التي تحمل غيابًا مع تسجيل حضور أو ساعات إضافية أو وقت مشروع أو مصروف. الفحص يُسمّي ولا يُصلح.',
           'لا تناقضات في هذه الفترة',
           'سجل الغياب والتسجيلات متوافقة.',
           'الموظف', 'اليوم', 'الغياب', 'التناقض', 'التفصيل', 'من', 'إلى', 'تحديث'),
}

# Le journal des arbitrages (263 / TRV-02) : quand deux sources déclarent la
# même journée, la priorité tranche ET laisse une trace.
ARBITRAGES = {
    'fr': {'tab': 'Journées arbitrées', 'empty': 'Aucun arbitrage sur la période',
           'emptyDesc': 'Aucune journée n’a été déclarée par deux sources.',
           'kept': 'Type retenu', 'dropped': 'Type écarté', 'origins': 'Provenances',
           'detectedAt': 'Arbitré le'},
    'en': {'tab': 'Arbitrated days', 'empty': 'No arbitration in this period',
           'emptyDesc': 'No day was declared by two sources.',
           'kept': 'Kept type', 'dropped': 'Dropped type', 'origins': 'Origins',
           'detectedAt': 'Arbitrated on'},
    'ar': {'tab': 'الأيام المُرجّحة', 'empty': 'لا ترجيح في هذه الفترة',
           'emptyDesc': 'لم يُصرّح بأي يوم من مصدرين.',
           'kept': 'النوع المعتمد', 'dropped': 'النوع المستبعد', 'origins': 'المصادر',
           'detectedAt': 'تاريخ الترجيح'},
}

CONFLICT_TYPES = {
    'fr': {'pointage': 'Pointage', 'heures_supplementaires': 'Heures supplémentaires',
           'temps_projet': 'Temps projet', 'temps_facturable': 'Temps facturable',
           'frais': 'Frais'},
    'en': {'pointage': 'Time entry', 'heures_supplementaires': 'Overtime',
           'temps_projet': 'Project time', 'temps_facturable': 'Billable time',
           'frais': 'Expense'},
    'ar': {'pointage': 'تسجيل حضور', 'heures_supplementaires': 'ساعات إضافية',
           'temps_projet': 'وقت المشروع', 'temps_facturable': 'وقت قابل للفوترة',
           'frais': 'مصروف'},
}

KINDS = {
    'fr': {'annual': 'Congé annuel', 'rtt': 'RTT', 'sick': 'Maladie',
           'work_accident': 'Accident du travail', 'maternity': 'Maternité / paternité',
           'unpaid': 'Congé sans solde', 'personal': 'Absence personnelle',
           'mission': 'Mission', 'stoppage': 'Arrêt de travail',
           'unjustified': 'Absence non justifiée'},
    'en': {'annual': 'Annual leave', 'rtt': 'RTT', 'sick': 'Sick leave',
           'work_accident': 'Work accident', 'maternity': 'Maternity / paternity',
           'unpaid': 'Unpaid leave', 'personal': 'Personal absence',
           'mission': 'Business trip', 'stoppage': 'Work stoppage',
           'unjustified': 'Unjustified absence'},
    'ar': {'annual': 'إجازة سنوية', 'rtt': 'رصيد الراحات', 'sick': 'مرض',
           'work_accident': 'حادث عمل', 'maternity': 'أمومة / أبوة',
           'unpaid': 'إجازة بدون راتب', 'personal': 'غياب شخصي',
           'mission': 'مهمة', 'stoppage': 'توقف العمل',
           'unjustified': 'غياب غير مبرر'},
}

KEYS = ['title', 'subtitle', 'empty', 'emptyDesc', 'employee', 'day', 'kind',
        'conflict', 'detail', 'from', 'to', 'refresh']

for lang in ('fr', 'en', 'ar'):
    path = BASE % lang
    with open(path, encoding='utf-8') as fh:
        doc = json.load(fh, object_pairs_hook=collections.OrderedDict)
    doc['leaveRequests'].setdefault('types', {}).update(ADD_TYPES[lang])
    doc['leaveRules'].setdefault('types', {}).update({
        'rtt': ADD_TYPES[lang]['rtt'],
        'recovery': ADD_TYPES[lang]['recovery'],
        'parental': ADD_TYPES[lang]['parental'],
        'personal': ADD_TYPES[lang]['personal'],
        'mission': ADD_TYPES[lang]['mission'],
    })
    block = collections.OrderedDict(zip(KEYS, ABS[lang]))
    block['conflictTypes'] = CONFLICT_TYPES[lang]
    block['kinds'] = KINDS[lang]
    block['tabs'] = collections.OrderedDict([
        ('anomalies', ABS[lang][0]),
        ('arbitrages', ARBITRAGES[lang]['tab']),
    ])
    block['arbitrages'] = ARBITRAGES[lang]
    doc['absenceAnomalies'] = block
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=2)
        fh.write('\n')
    print('ok', path)
