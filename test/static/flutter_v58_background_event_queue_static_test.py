from pathlib import Path

root = Path(__file__).resolve().parents[2]
checks = {
    'queue service': root / 'lib/services/foreground_event_queue.dart',
    'main lifecycle': root / 'lib/main.dart',
    'call ui': root / 'lib/services/call_ui_controller.dart',
    'call service': root / 'lib/services/call_service.dart',
    'group call': root / 'lib/services/group_call_service.dart',
    'live room': root / 'lib/services/live_room_service.dart',
}
for name, path in checks.items():
    assert path.exists(), f'{name} missing: {path}'

assert 'ForegroundEventQueue().setForeground(false)' in checks['main lifecycle'].read_text()
assert 'ForegroundEventQueue().setForeground(true)' in checks['main lifecycle'].read_text()
assert 'incoming-call:$fromSocketId' in checks['call ui'].read_text()
assert 'isIncomingInvitePending' in checks['call service'].read_text()
assert 'group-match-joined:' in checks['group call'].read_text()
assert 'live-room-friend-request:' in checks['live room'].read_text()
print('flutter-v58-background-event-queue: successful')
