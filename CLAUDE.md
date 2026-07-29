# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Merhaba is a Flutter app (Android/iOS/web/desktop) for random video chat, friends, and messaging,
backed by a Node.js/Socket.IO signaling server (`signaling_server/`) deployed on Render. Two AI
coding tools work in this repo concurrently — see `AGENTS_LOG.md` for the coordination protocol
(both tools must read/update it before touching shared files like `signaling_server/server.js`).

## Commands

Flutter app (run from repo root):
- `flutter analyze` — typecheck/lint
- `flutter test` — run all tests
- `flutter test test/auth_service_test.dart` — run a single test file
- `flutter run` — run the app (pick device interactively, or `-d chrome` / `-d windows`)
- `flutter pub get` — install/sync dependencies after editing `pubspec.yaml`

Signaling server (run from `signaling_server/`):
- `npm install` — install dependencies
- `npm start` — runs `bootstrapFirestoreSync.js` then `server.js`
- No automated test/lint config exists for the server — changes are verified with ad-hoc manual/E2E checks, not a test suite.

## Architecture

### Flutter client (`lib/`)

- `main.dart` — app entry point. Initializes Firebase/Crashlytics (non-fatal if unconfigured — see
  inline comments), fires off `PushNotificationService().init()` without awaiting so it doesn't
  block the splash screen, and reconnects sockets on resume only after a long (>8s) backgrounding
  to avoid disrupting active calls or causing false "disconnected" flicker.
- `services/` — one singleton service per concern, all using the `factory X() => instance` pattern
  (a private static `instance` backing a public factory constructor), e.g. `AuthService()`,
  `MessagingService()`, `CallService()`. Call the factory constructor from anywhere to get the same
  instance; do not instantiate with `X._internal()`-style constructors directly. Key services:
  `auth_service.dart` (session/token), `webrtc_service.dart` (1:1 WebRTC via `flutter_webrtc`),
  `call_service.dart` / `group_call_service.dart` (call signaling over Socket.IO, LiveKit for group
  calls), `messaging_service.dart` (chat socket), `discover_service.dart` (swipe/match feature),
  `live_room_service.dart`, `friends_service.dart`, `gamification_service.dart` (XP/levels/leaderboard),
  `push_notification_service.dart`.
- `screens/` — one file per screen, matched 1:1 with a feature area (call, group call, discover,
  friends, groups, live rooms, stories, achievements, leaderboard, settings, etc). Screens talk to
  the corresponding singleton service rather than holding their own network/socket state.
- `theme/app_theme.dart` — central theme; text scale is applied globally via
  `utils/text_scale_notifier.dart` and a `MediaQuery`/`TextScaler` wrapper in `main.dart`'s
  `MaterialApp.builder`, not per-screen.
- `data/` — static content tables (icebreakers, stickers).

### Signaling server (`signaling_server/`)

Single-file Express + Socket.IO server (`server.js`, ~3800 lines) handling both realtime signaling
(socket events for calls/chat/presence) and REST endpoints (`/auth/*`, `/discover/*`, `/profile*`,
`/friends*`, `/groups*`, `/stories*`, `/live-rooms`, `/achievements`, `/leaderboard`, `/admin/*`,
`/translate`, `/turn-credentials`, etc). Most REST routes are gated by a `requireAuth` middleware
(JWT-based, see `jsonwebtoken` dependency). Persistence is split across per-domain store modules
(`userStore.js`, `messageStore.js`, `groupStore.js`, `groupMessageStore.js`, `discoverStore.js`,
`storyStore.js`, `liveRoomStore.js`, `reportStore.js`, `scheduledMessageStore.js`) plus
`firestoreSync.js`/`bootstrapFirestoreSync.js` for Firestore syncing, `photoStorage.js`/
`chatMediaStorage.js`/`liveRoomMediaAdapter.js` for media (Cloudinary), and
`pushNotificationService.js` / `translationService.js` for external integrations. Group video calls
route through LiveKit (`livekit-server-sdk`); 1:1 calls use direct WebRTC signaling over sockets.

## Health Stack

- typecheck: flutter analyze
- lint: flutter analyze
- test: flutter test
- gbrain: gbrain doctor --json
- note: signaling_server/ (Node.js) has no automated test/lint config — not scored, ad-hoc E2E scripts only

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec
- Firestore data/rules work → invoke firebase-firestore or firebase-security-rules-auditor
- Flutter widget test needed → invoke flutter-add-widget-test
- Flutter integration test needed → invoke flutter-add-integration-test
- Flutter layout bug → invoke flutter-fix-layout-issues
- Flutter responsive layout → invoke flutter-build-responsive-layout
- Flutter navigation/routing → invoke flutter-setup-declarative-routing
- Flutter architecture cleanup → invoke flutter-apply-architecture-best-practices

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
