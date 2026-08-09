from pathlib import Path

root = Path(__file__).resolve().parents[2]
chat = (root / 'lib/screens/chat_screen.dart').read_text()
group = (root / 'lib/screens/group_chat_screen.dart').read_text()
guard = (root / 'lib/utils/async_operation_guard.dart').read_text()

required = [
    'class AsyncOperationGuard',
    '_attachmentGuard.cancelCurrent()',
    '_sendGuard.cancelCurrent()',
    '_cancelPendingComposerOperations()',
    '_attachmentGuard.isActive(operationGeneration)',
    '_sendGuard.isActive(sendGeneration)',
    '_audioRecorder.cancel()',
]
for token in required:
    assert token in (guard + chat), f'missing {token}'

assert chat.count('Future<void> _cancelPendingComposerOperations()') == 1
assert 'if (_accessRevoked || !mounted) return;' in group
assert '_controller.clear();' in group and '_replyingTo = null;' in group
print('flutter-v70-async-composer-cancellation: başarılı')
