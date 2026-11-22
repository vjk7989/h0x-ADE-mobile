# HyperOx mobile protocol contract

Every component (relay, core bridge, desktop app, Flutter app) codes against this document.

Decisions by the product owner that shape it:

- Approved phones get a live, full-colour terminal view (`view` / `output`).
- The phone link is on by default; each phone must still be approved individually on the computer.
- SSH host, user and port can be imported from the account (`users/{uid}/sshHosts`); never keys or passwords.


## 3.1 Relay HTTP (`https://relay.pavii.tech`, JSON, TLS only)
| Method + path | Auth | Body → answer |
|---|---|---|
| `POST /v1/link-codes` | `Bearer <Firebase ID token>` | `{}` → `{code:"XXXX-XXXX", expires_in:600}` |
| `POST /v1/machines` | `Bearer <ID token>` **or** body `code` | `{name, os, core, pub, code?}` → `201 {machine, secret}` |
| `PATCH /v1/machines/self` | `Machine <mid>:<secret>` | `{name}` → `204` |
| `DELETE /v1/machines/self` | `Machine <mid>:<secret>` | → `204` |
| `GET /healthz` | none | `200 ok` |

Errors are `{error:{code,message}}` with status 400/401/403/404/409/429 (+`Retry-After`).

## 3.2 Firestore (project `pavii-ai3`; works on the Spark plan)
- `users/{uid}/machines/{mid}`:
  - fields: `name`, `os`, `core`, `pub` (b64url SEC1 P-256 = the machine's `web.key` public key), `fp` (b64url SHA-256(pub)), `createdAt`, `lastSeen`, `online`;
  - only the relay creates it; the owner may update `name` only, and may delete it.
- `users/{uid}/phones/{pid}`:
  - fields: `name` ≤64, `pub` ≤100 (informational; trust is decided at the machine), `fcm` ≤4096, `platform` ∈ {android, ios}, `muted` = up to 100 mids, `addedAt`, `lastSeen`;
  - owner read/write.
- `users/{uid}/sshHosts/{id}`:
  - fields: `name`, `host`, `user`, `port`, `source:"desktop"`, `updatedAt`;
  - owner read/write; never keys or passwords (M-ADR-13).
- `machineSecrets/{mid}` `{uid, hash}` and `linkCodes/{code}` `{uid, expires}`: Admin SDK only; every client is denied.

## 3.3 Relay sockets
- Machine socket:
  - `wss://…/v1/machine`, header `Authorization: Machine <mid>:<secret>`;
  - one per machine; a newer one replaces it, and the old one gets 4409.
- Phone socket:
  - `wss://…/v1/phone?machine=<mid>&phone=<pid>`, header `Authorization: Bearer <ID token>`;
  - the relay checks that the uid owns both docs;
  - its frames are **exactly the web panel's `/ws` protocol**: a text client hello, a text server hello, then only binary sealed frames.
- Heartbeat: a ping every 20 s; a socket idle for 60 s is closed. Max frame 64 KiB.
- Close codes:

| Code | Meaning |
|---|---|
| 4400 | bad frame order |
| 4401 | unauthorized |
| 4403 | not your machine |
| 4404 | machine offline |
| 4408 | machine went away |
| 4409 | replaced |
| 4413 | too big |
| 4429 | rate limited (the reason = retry seconds) |

## 3.4 Relay ↔ machine multiplexing
- Text control frames:
  - relay → machine: `{"t":"open","c":"<b64url 16B>","phone":"<pid>","name":"<phone name>"}` and `{"t":"close","c":…}`;
  - machine → relay: `{"t":"close","c":…}` and `{"t":"push","kind":"needs_you|done|error|finished","agent":"<≤40>","terminal":"<address>"}`.
- Binary frames: `c(16) ‖ k(1: 0x01 hello text, 0x02 sealed) ‖ payload`. The relay maps the phone's text to k=1 and its binary to k=2, and back.
- The relay never opens, stores or logs a payload. It writes `online` and `lastSeen` only: on connect, on disconnect, and every 5 min.

## 3.5 Limits
- Relay:
  - per connection: 100 frames/s, burst 200;
  - 20 sockets per uid;
  - 30 connects/min per IP;
  - 10 links and 10 codes per uid per hour;
  - 20 machines per uid;
  - 60 pushes per machine per minute.
- Core keeps every bridge limit (30 commands/min, notice quiet time, confirmations, lock, audit).

## 3.6 End-to-end channel (ADR-064 crypto unchanged; the machine is the server)
- Keys:
  - S = the existing `web.key`;
  - D = the phone's P-256 device key, kept in Keystore-backed secure storage;
  - an ephemeral key per channel.
- The phone pins `fp` from the machine doc (TOFU, stored locally). A mismatch is a hard error.
- **SAS** (frozen in `cloud_vectors.json`): `u32be(SHA-256("h0x-bridge sas v1" ‖ SHA-256(transcript))[0..4]) mod 1_000_000`, shown as 6 digits with leading zeros. Both sides show it at first approval.

## 3.7 Sealed messages (`{name,data}`, the web panel set plus the cloud additions)
- Phone → machine:
  - `join {phone,label}` (first);
  - `command {cmd,id,…}` with `list|read|send|keys|approve|deny|interrupt|kill|run|lock|confirm`, plus the cloud-only `sessions` and `spaces`;
  - `snapshot`, `ping`;
  - `view {terminal,history}`, `unview {terminal}`.
- Machine → phone:
  - `pending {code}`, `approved {}`, `snapshot`;
  - `reply {id,kind,…}` with the web kinds, plus `sessions {sessions:[{address,name,agent,folder,status,live}]}` and `spaces {spaces:[{name,folder,tabs:[{name,panes:[…]}]}], agents:[{slot,name,command}]}`;
  - `notice {terminal,agent,folder,kind,excerpt}` (redacted);
  - `output {terminal,seq,data(b64)}`, `view_end {terminal}`;
  - `heartbeat`;
  - `error {message}`, then the connection closes.
- Approval: an unknown (phone, D) gets `pending`, and the computer lists it. Approve → identity `{transport:"cloud", user_id:pid}` bound to D. Deny, or 5 min with no answer → `error` + close. Revoke = `bridge unpair <id>`, and the next message gets `error` + close.

## 3.8 Push (FCM, account mode only)
- `notification {title:"<agent> needs you|is done|hit an error|finished", body:"<machine name>"}`.
- `data {m:<mid>, t:<terminal address>, k:<kind>}`, on the Android channel `agents`.
- Never terminal text, a folder, or an excerpt.

## 3.9 Discovery
- Account mode: a Firestore listener on `users/{uid}/machines`. A machine gets there in one of two ways:
  - the desktop links it with the ID token (M3.2);
  - a headless machine runs `bridge cloud link --code` (M4.S4).
- SSH mode: machines are typed in on the phone, or imported from `users/{uid}/sshHosts` (written by the desktop, M3.6). They are stored on the phone.

## 3.10 SSH transport (no cloud)
- **Auth:**
  - dartssh2 with the phone's ed25519 key (private key in secure storage; the public OpenSSH line is shared by the user into `authorized_keys`);
  - or Tailscale SSH (the tailnet authorises; the client offers `none`/no key). Tailscale SSH servers run only on Linux and macOS hosts, so the switch is for those computers only.
  - Windows computer: use Windows OpenSSH Server with the phone's ed25519 key in `authorized_keys` (admin accounts: `C:\ProgramData\sshdministrators_authorized_keys`), reached by MagicDNS name or 100.x address.
  - Host key: TOFU per `host:port`, `SHA256:` fingerprint shown, mismatch = a blocking warning.
- **Session:** an exec channel `h0x-core connect`. It must be on the PATH of a non-interactive SSH login: sh/bash on Unix, cmd.exe or PowerShell on Windows OpenSSH. The login must print nothing to stdout.
- **Protocol:**
  - newline JSON-RPC 2.0 `hello` with `framed:true` (the core's generation is checked);
  - then frames `[channel u32 LE][kind u8][len u32 LE][payload]`: channel 0 = JSON-RPC, attach = its own channel with credit acks (`wire.rs`).
  - Methods used: `terminal.list`, `terminal.read`, `terminal.send`, `terminal.keys`, `terminal.interrupt`, `terminal.run`, `terminal.kill`, `terminal.attach` (observe), `events.subscribe`, `session.list`; `spaces` comes from a second exec, `h0x-core bridge spaces --show --json`.
- **Semantics:**
  - No bridge: no confirmations, redaction, audit or rate limit. An SSH login is already full control (documented in M2.9).
  - The adapter keeps the bridge's approve/deny rule (`blocked`+`permission` only).
  - Kill and run still ask a confirm in the UI (client side).
  - No push: notices arrive only while the app is open.

## 3.11 Dart interface (screens see only this)
```dart
abstract class MachineConnection {
  MachineInfo get machine;                 // id, name, os, mode (cloud|ssh), online
  Stream<ConnState> get state;             // connecting | needsApproval(code) | hostKeyNew(fp) | ready | failed(reason)
  Future<List<Session>> sessions();
  Future<SpacesView> spaces();
  Future<String> read(String terminal, {int lines = 50});
  Future<Reply> send(String terminal, String text);
  Future<Reply> keys(String terminal, List<Key> keys);
  Future<Reply> approve(String terminal);
  Future<Reply> deny(String terminal);
  Future<Reply> interrupt(String terminal);
  Future<Reply> kill(String terminal);
  Future<Reply> run(String folder, String command);
  Future<Reply> confirm(String token);
  Stream<List<int>> view(String terminal, {int history = 5000}); // cancel = unview/detach
  Stream<Notice> notices();
  Future<void> close();
}
// Reply = done | needsConfirm(token, what) | locked | rateLimited(secs) | failed(message) | notPaired
```

