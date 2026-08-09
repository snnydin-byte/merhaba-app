from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / 'lib'
HELPER = LIB / 'utils' / 'session_transient_ui.dart'

assert HELPER.exists(), 'session_transient_ui.dart eksik'
helper = HELPER.read_text(encoding='utf-8')
for symbol in ('showSessionDialog', 'showSessionModalBottomSheet', 'showSessionSnackBar'):
    assert symbol in helper, f'{symbol} merkezi yardımcıda yok'
assert 'SessionUiLock().allowsTransientUi' in helper

allowed_direct = {
    LIB / 'widgets' / 'session_end_progress_dialog.dart',
    HELPER,
}
violations = []
for folder in (LIB / 'screens', LIB / 'widgets'):
    for path in folder.rglob('*.dart'):
        if path in allowed_direct:
            continue
        text = path.read_text(encoding='utf-8')
        for pattern in ('showDialog<', 'showDialog(', 'showModalBottomSheet<', 'showModalBottomSheet('):
            if pattern in text:
                violations.append(f'{path.relative_to(ROOT)}: {pattern}')
        if 'ScaffoldMessenger.of(context).showSnackBar' in text:
            violations.append(f'{path.relative_to(ROOT)}: direct showSnackBar')
        if 'ScaffoldMessenger.maybeOf(context)?.showSnackBar' in text:
            violations.append(f'{path.relative_to(ROOT)}: direct nullable showSnackBar')

assert not violations, 'Kilit dışı geçici UI çağrıları:\n' + '\n'.join(violations)
print('flutter-v79-transient-ui-lock: başarılı')
