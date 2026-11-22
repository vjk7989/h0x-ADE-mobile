# HyperOx mobile — design (passes I and II)

- **M0.2a (pass I):** tokens, plus Sign in, Machines and Add machine. Approved by the user on 2026-11-18.
- **M0.2b (pass II):** Inbox, Agent, Spaces, To-do and Settings (with the theme picker), plus the terminal, key bar, navigation, account-only, To-do and theme sections in `tokens.md` §13–17. Status: **waiting for G-DESIGN**.

Pass II adds a fifth navigation destination, **To-do**. The pass I boards were re-rendered with the five-item bar; nothing else in them changed.

Open the SVGs in a browser (Chrome or Edge). They contain the fonts (Geist and JetBrains Mono subsets, both OFL), so they look the same everywhere. The PNGs in `previews/` are 1:1 renders of the same files. The To-do board also contains a Patrick Hand subset (OFL), the desktop To-do font.

| File | What | Preview |
|---|---|---|
| [`tokens.md`](tokens.md) | Colours for all five themes, contrast ratios, type scale (100–200 %), spacing, radii, motion, terminal palette, touch targets, screen-reader and focus rules | — |
| [`screens/sign-in.svg`](screens/sign-in.svg) | Sign in: 9 frames | [`previews/sign-in.png`](previews/sign-in.png) |
| [`screens/machines.svg`](screens/machines.svg) | Machines: 11 frames | [`previews/machines.png`](previews/machines.png) |
| [`screens/add-machine.svg`](screens/add-machine.svg) | Add machine: 11 frames | [`previews/add-machine.png`](previews/add-machine.png) |
| [`screens/inbox.svg`](screens/inbox.svg) | Inbox: 12 frames | [`previews/inbox.png`](previews/inbox.png) |
| [`screens/agent.svg`](screens/agent.svg) | Agent (terminal, key bar, compose): 11 frames | [`previews/agent.png`](previews/agent.png) |
| [`screens/spaces.svg`](screens/spaces.svg) | Spaces: 11 frames | [`previews/spaces.png`](previews/spaces.png) |
| [`screens/todo.svg`](screens/todo.svg) | To-do: 14 frames | [`previews/todo.png`](previews/todo.png) |
| [`screens/settings.svg`](screens/settings.svg) | Settings and theme picker: 12 frames | [`previews/settings.png`](previews/settings.png) |

Each board's first row is: phone 360 × 800 light (`paper`), phone dark (`darkmatter`), and tablet / foldable 840 × 900 two-pane. The rows below hold the states. Each frame has a numbered label above it and a behaviour note under it.

## Frames and states

### Pass I


| Screen | Frames | Empty | Loading | Error | Offline | Approval code | 200 % text |
|---|---|---|---|---|---|---|---|
| Sign in | default light / dark, tablet, waiting for Google, sign-in cancelled, offline, email (keyboard open), biometric unlock, 200 % | n/a (no data) | 04 | 05 | 06 | n/a (approval happens per machine) | 09 |
| Machines | list light / dark, tablet (rail + list + detail), empty, syncing, relay unreachable, offline, approval sheet, host key changed, row actions, 200 % | 04 | 05 | 06 | 07 | 08 | 11 |
| Add machine | same account light, SSH dark, tablet, Tailscale SSH on, validation, connecting, first host key, permission denied, offline, approval after link, import from account | (link code is the empty state) | 06 | 05, 08 | 09 | 10 | (type rules in tokens §5) |

The requirements from `plan-mobile.md` and `plan-mobile-tasks.md`, and where each one is drawn:

- **Two modes, chosen per machine.** `[account]` machines are reached through the relay and are end-to-end encrypted. `[ssh]` machines are reached directly, over SSH or Tailscale SSH. The screens show only the mode tag; everything else is the same (§3.11 `MachineInfo.mode`).
- **"Continue without an account (SSH only)".** It is on every sign-in frame and goes to Add machine › SSH with no account.
- **Same account.**
  - A signed-in desktop appears by itself (the "Listening" state).
  - A headless machine uses a link code with the `h0x-core bridge cloud link --code` command.
  - The computer must have Settings › Remote › Allow my phone to connect switched on.
- **SSH.**
  - Fields: host / IP / Tailscale name, user, and port.
  - A "Use Tailscale SSH (no key)" switch. It works for Linux and macOS computers only; Tailscale SSH has no Windows server. For a Windows computer, leave it off, install the Windows OpenSSH Server, add this phone's key to `authorized_keys` (admin accounts: `C:\ProgramData\sshdministrators_authorized_keys`), and use the MagicDNS name or 100.x address as the host.
  - This phone's public key, with Copy and Share.
  - "Import from your account" brings in host / user / port shared by the desktop. A host that is also an account machine is never merged automatically.
- **Phone link with per-phone approval.**
  - A 6-digit code on the phone that matches the computer.
  - On a headless machine, the prompt is in its terminal.
  - Cancel, plus a 5-minute expiry.
- **Host keys.**
  - Trust on first use, showing the fingerprint and the command to check it.
  - On a change, the row is blocked and a review sheet opens with "Don't connect" as the primary action.
- **Connection states** follow `ConnState`: `connecting` → `needsApproval(code)` / `hostKeyNew(fp)` → `ready` / `failed(reason)`.


### Pass II

| Screen | Frames | Empty | Loading | Error | Offline | Approval / confirm | 200 % text | SSH-only build |
|---|---|---|---|---|---|---|---|---|
| Inbox | list light / dark; tablet (rail + inbox + agent); empty; syncing; all offline; pending approval with mixed modes; search; swipe; one machine failed; SSH-only; 200 % | 04 | 05 | 10 | 06 | 07 | 12 | 11 |
| Agent | permission prompt (keyboard closed); keyboard open with Ctrl one-shot; tablet (rail + inbox sidebar + terminal); interrupt confirm; attaching; question (no Approve); finished; reconnecting; copy selection; locked / rate limited; 200 % | n/a | 05 | 10 | 08 | 01 (Approve / Deny), 04 (Interrupt) | 11 | identical (no account-only controls) |
| Spaces | map light / dark; tablet (big map with live previews); start-an-agent slots; run confirm; no spaces; space without tabs + finished pane; core too old; loading; offline; 200 % | 06 | 09 | 08 | 10 | 05 | 11 | identical (the picker lists SSH machines) |
| To-do | list light / dark; tablet (lists + tasks); list switcher; which computer; inline edit with keyboard; drag reorder; delete with undo; empty; all done; loading; offline (read-only); unreadable list; 200 % | 09 | 11 | 13 | 12 | 08 (undo) | 14 | identical |
| Settings | top light / dark; tablet (categories + phones); scrolled (phones, SSH key, known hosts); SSH-only; regenerate-key confirm; remove-this-phone confirm; theme picker System (light), Dark (dark) and tablet; notifications blocked by Android; 200 % | n/a | n/a | 11 | n/a | 06, 07 | 12 | 05 |

How each pass II requirement is drawn:

- **Agent screen:**
  - The live terminal is drawn in full colour, using the theme file palette.
  - It is shown with the keyboard closed and open. The key bar is always the last row, with Esc, Tab, Ctrl, Alt, the arrows and Enter pinned; Ctrl and Alt are sticky (one-shot or locked).
  - The compose row has Paste and Send. Dictation uses the keyboard's own mic.
  - Approve / Deny appear only for permission prompts. Interrupt always asks to confirm first.
  - Tablet layout: sidebar inbox plus terminal.
- **Spaces:** desktop spaces → tabs → split map, drawn to scale. Tap a pane to open it. "Start an agent" uses slots 1–9 and the shared confirm dialog.
- **Settings:**
  - Account; theme; notifications per machine; "Phones linked to this account"; "SSH key of this phone" (Copy, Share, Regenerate with confirm); known hosts (Forget); Sign out.
  - **Theme section and a full-screen theme picker:** all 15 desktop themes, each row with a live mini preview, a tick on the current one, and a System / Light / Dark switch. Phone and tablet.
- **To-do:**
  - The desktop's lists from a chosen computer: a list switcher in `lists.md` order, tick circles, folded steps, Add task / Add step, inline edit, delete with an undo snackbar, drag to reorder, and "N of M done".
  - Empty, loading, offline and error states, plus a "which computer" picker. Phone and tablet. Same look and rules as the desktop panel.
  - The sample tasks are neutral, not the user's lists.
- **SSH-first build.** Every account-only control is its own block and is marked "Account only" in the element table below. Inbox and Settings have an explicit SSH-only frame (tokens §15).


## Design decisions

### Pass I

1. **The same visual language as the desktop.**
   - Geist and JetBrains Mono, Lucide icons, and duotone icon tiles.
   - CLI bracket tags (`[account]`, `[ssh]`, `[needs you]`), mono metadata, and the dot-matrix mark.
   - The sign-in screen is the desktop's glass + falling-code screen, re-laid for a phone: brand on top, actions in the thumb zone at the bottom.
2. **Themes come from the desktop files.** No new palette. Mobile adds five derived roles (`screen`, `card`, `outline`, `well`, `ok`), each with a stated rule and a contrast check (tokens §2–3).
3. **One machine list, grouped by mode.** It is not two separate screens; the user should not care how a machine is reached. State is always a word plus a colour.
4. **The safe action is primary** on security prompts: "Don't connect", Cancel, and the approval code must match. A risky action ("Trust new key…") is outlined in red and asks again.
5. **Errors say what happened and what to do,** in the developer's own terms: the host and status code, `Permission denied (publickey)`, and the one-liner to fix it.
6. **Offline never leaves dead buttons.** Account features disable with a reason; SSH keeps working on the LAN or Tailscale.
7. **Tablet and foldable** use a navigation rail and list + detail (Machines), bento + form (Sign in), and modes + form (Add machine).
8. **No glass or blur on working screens.** Glass appears only on sign-in, and it is faked with layers, to protect the 60 fps budget.


### Pass II
1. **The terminal stays the desktop's terminal.** It uses the same palette, and it has its own zoom, so 200 % UI text never reflows agent output. The phone observes the desktop's PTY size instead of resizing it.
2. **The key bar never hides Enter.** The other keys are ordered by how often agents need them: Esc, Tab, Ctrl and the up/down arrows come first. The bar scrolls instead of shrinking its targets below 48 dp.
3. **Approvals happen where the eye already is.** Inline Deny / Approve appear in Inbox rows and a pinned prompt card in the agent. A question never offers Approve.
4. **The split map is to scale.** On a tablet each pane shows a live preview. At 200 % the map turns into a list, because a scaled map would be unreadable.
5. **To-do is a port, not a redesign.** It keeps the same Markdown files, handwriting font, progress line, Completed fold, 6 s undo and move rules as the desktop, with touch gestures (swipe, long-press drag) and TalkBack actions in place of hover and keys.
6. **Theme choice equals the desktop's.** All 15 themes and the same System / Light / Dark model, each previewed in its own colours.


## Interactive elements

Every tappable element on every board, with the label TalkBack reads, its smallest touch target, whether it is account-only (hidden in the SSH-first build), and the frames it appears in. The generator asserts that every target is at least 48 × 48 dp; all 331 unique elements pass.

### sign-in

| Label (screen reader) | Role | Min target (dp) | Account only | Frames |
|---|---|---|---|---|
| Continue with Google | button | 296 × 52 | yes | default, tablet, error, offline, text-200 |
| Continue with GitHub | button | 296 × 52 | yes | default, tablet, loading, error, offline, text-200 |
| Continue with email | button | 296 × 52 | yes | default, tablet, loading, error, offline |
| Continue without an account (SSH only) | button | 296 × 64 |  | default, tablet, loading, error, offline |
| Terms of service | link | 64 × 48 | yes | default, tablet, loading, error, offline |
| Privacy policy | link | 70 × 48 | yes | default, tablet, loading, error, offline |
| Cancel Google sign-in | button | 88 × 52 | yes | loading |
| Back | button | 48 × 48 | yes | email |
| Email | text field | 328 × 48 | yes | email |
| Send sign-in link | button | 328 × 52 | yes | email |
| Open pavii.tech/login | button | 328 × 52 | yes | email |
| Unlock with fingerprint | button | 80 × 80 | yes | unlock |
| Use PIN | button | 140 × 52 | yes | unlock |
| Sign out | button | 140 × 52 | yes | unlock |

### machines

| Label (screen reader) | Role | Min target (dp) | Account only | Frames |
|---|---|---|---|---|
| More options | button | 48 × 48 |  | default, empty, loading, error, offline, approval, hostkey, actions, text-200 |
| Search machines | button | 48 × 48 |  | default, tablet, loading, error, offline, approval, hostkey, actions, text-200 |
| studio-pc, Windows, account, 1 agent needs you | button | 328 × 72 | yes | default, tablet, approval, hostkey, actions |
| h0x-gcp, Linux, account, online | button | 328 × 72 | yes | default, tablet, approval, hostkey, actions |
| macbook, macOS, account, offline | button | 328 × 72 | yes | default, tablet, approval, hostkey, actions |
| devbox, Linux, SSH, online | button | 328 × 72 |  | default, tablet, loading, error, offline, approval, hostkey, actions |
| raspi, Linux, SSH, host key changed, blocked | button | 328 × 72 |  | default, tablet, loading, error, offline, approval, hostkey, actions |
| Review host key change for raspi | button | 304 × 48 |  | default, tablet, loading, error, offline, approval, hostkey, actions |
| Add machine | button | 48 × 48 |  | default, tablet, loading, error, offline |
| Inbox, 1 needs you | tab | 72 × 80 |  | default, loading, error, offline, approval, hostkey, actions, text-200 |
| Machines | tab | 72 × 64 |  | default, tablet, empty, loading, error, offline, approval, hostkey, actions, text-200 |
| Spaces | tab | 72 × 64 |  | default, tablet, empty, loading, error, offline, approval, hostkey, actions, text-200 |
| To-do | tab | 72 × 64 |  | default, tablet, empty, loading, error, offline, approval, hostkey, actions, text-200 |
| Settings | tab | 72 × 64 |  | default, tablet, empty, loading, error, offline, approval, hostkey, actions, text-200 |
| Inbox | tab | 72 × 64 |  | tablet, empty |
| Rename h0x-gcp | button | 48 × 48 | yes | tablet |
| More options for h0x-gcp | button | 48 × 48 | yes | tablet |
| Open claude in ~/acme-web, needs you | button | 352 × 56 |  | tablet |
| Open codex in ~/api-server, working | button | 352 × 56 |  | tablet |
| Open opencode in ~/mobile-app, idle | button | 352 × 56 |  | tablet |
| Open inbox of h0x-gcp | button | 170 × 52 | yes | tablet |
| Open spaces of h0x-gcp | button | 170 × 52 | yes | tablet |
| Remove h0x-gcp from this phone | button | 240 × 48 | yes | tablet |
| Add machine: Same account | button | 328 × 88 | yes | empty |
| Add machine: SSH | button | 328 × 88 |  | empty |
| Loading account machines | progress | 328 × 216 |  | loading |
| Retry now | button | 91 × 48 |  | error |
| studio-pc, Windows, account, last known state | button | 328 × 72 | yes | error, offline |
| h0x-gcp, Linux, account, last known state | button | 328 × 72 | yes | error, offline |
| macbook, macOS, account, last known state | button | 328 × 72 | yes | error, offline |
| Approval code 4 8 2 9 1 3 | text | 312 × 60 | yes | approval |
| Cancel | button | 312 × 52 |  | approval |
| Don't connect | button | 312 × 52 |  | hostkey |
| Trust new key… | button | 312 × 52 |  | hostkey |
| Open sessions | menu item | 360 × 56 |  | actions |
| Rename | menu item | 360 × 56 |  | actions |
| Copy address | menu item | 360 × 56 |  | actions |
| Show host key | menu item | 360 × 56 |  | actions |
| Remove from this phone | menu item | 360 × 56 |  | actions |
| studio-pc | button | 328 × 200 |  | text-200 |
| h0x-gcp | button | 328 × 200 | yes | text-200 |

### add-machine

| Label (screen reader) | Role | Min target (dp) | Account only | Frames |
|---|---|---|---|---|
| Back | button | 48 × 48 |  | same-account, ssh, tablet, ssh-tailscale, ssh-invalid, connecting, first-hostkey, error-denied, offline, approval, import |
| Same account mode, selected | tab | 160 × 48 | yes | same-account, offline, approval |
| SSH mode | tab | 160 × 48 |  | same-account, offline, approval |
| Link code 7 K Q 4 M P | text | 296 × 64 | yes | same-account, offline |
| New code | button | 110 × 48 | yes | same-account, offline |
| Copy link command | button | 48 × 48 | yes | same-account, offline |
| Same account mode | tab | 160 × 48 | yes | ssh, tablet, ssh-tailscale, ssh-invalid, connecting, first-hostkey, error-denied, import |
| SSH mode, selected | tab | 160 × 48 |  | ssh, tablet, ssh-tailscale, ssh-invalid, connecting, first-hostkey, error-denied, import |
| Import SSH hosts from your account | button | 328 × 64 | yes | ssh, ssh-tailscale, ssh-invalid, first-hostkey, import |
| Host, IP or Tailscale name | text field | 328 × 48 |  | ssh, tablet, ssh-tailscale, ssh-invalid, first-hostkey, import |
| User | text field | 212 × 48 |  | ssh, tablet, ssh-tailscale, ssh-invalid, first-hostkey, import |
| Port | text field | 104 × 48 |  | ssh, tablet, ssh-tailscale, ssh-invalid, first-hostkey, import |
| Use Tailscale SSH, no key, off (Linux and macOS computers only) | switch | 328 × 56 |  | ssh, tablet, ssh-invalid, first-hostkey, import |
| This phone's public key, ed25519, fingerprint SHA256 4mQe | text | 296 × 54 |  | ssh, tablet, ssh-invalid, first-hostkey, import |
| Copy public key | button | 142 × 48 |  | ssh, tablet, ssh-invalid, first-hostkey, import |
| Share public key | button | 142 × 48 |  | ssh, tablet, ssh-invalid, first-hostkey, import |
| Connect | button | 160 × 52 |  | ssh, tablet, ssh-tailscale, ssh-invalid, first-hostkey, import |
| Use devbox details | button | 64 × 48 | yes | tablet |
| Use h0x-gcp details | button | 64 × 48 | yes | tablet |
| Use raspi details | button | 64 × 48 | yes | tablet |
| Name (optional) | text field | 400 × 48 |  | tablet |
| Cancel | button | 120 × 48 |  | tablet, connecting, first-hostkey, approval |
| Use Tailscale SSH, no key, on | switch | 328 × 56 |  | ssh-tailscale |
| Host key fingerprint SHA256 4mQe0rT7… | text | 312 × 60 |  | first-hostkey |
| Copy check command | button | 48 × 48 |  | first-hostkey |
| Trust and connect | button | 312 × 52 |  | first-hostkey |
| Copy command with key | button | 48 × 48 |  | error-denied |
| Use Tailscale SSH instead | button | 260 × 48 |  | error-denied |
| Edit details | button | 156 × 52 |  | error-denied |
| Try again | button | 156 × 52 |  | error-denied |
| Switch to SSH | button | 118 × 48 |  | offline |
| Approval code 4 8 2 9 1 3 | text | 296 × 60 |  | approval |
| devbox, dev@devbox.tail3a1f.ts.net:22, selected | checkbox | 328 × 60 |  | import |
| h0x-gcp, ubuntu@34.93.12.8:22, not selected | checkbox | 328 × 72 |  | import |
| raspi, pi@192.168.1.42:22, selected | checkbox | 328 × 60 |  | import |
| Import 2 hosts | button | 312 × 52 |  | import |

### inbox

| Label (screen reader) | Role | Min target (dp) | Account only | Frames |
|---|---|---|---|---|
| More: mark all read, sort | button | 48 × 48 |  | list, tablet, empty, loading, offline, approval, search, swipe, error, ssh-only, text-200 |
| Search agents, folders, machines | search field | 280 × 48 |  | list, tablet, loading, offline, approval, search, swipe, error, ssh-only, text-200 |
| claude in ~/acme-web on studio-pc, needs you: Allow edit to README.md?, unread, pinned | button | 328 × 84 |  | list, tablet, approval, search, swipe, error |
| Deny claude: Allow edit to README.md? | button | 121 × 48 |  | list, approval, search, swipe, error, text-200 |
| Approve claude: Allow edit to README.md? | button | 121 × 48 |  | list, approval, search, swipe, error, text-200 |
| codex in ~/infra on devbox, needs you: Which region: eu-west-1 or us-east-1?, unread | button | 328 × 84 |  | list, tablet, approval, swipe, ssh-only |
| opencode in ~/api-server on h0x-gcp, working: Running tests (34/120)… | button | 328 × 84 |  | list, tablet, approval, error |
| claude in ~/mobile-app on devbox, working: Editing lib/router.dart | button | 328 × 84 |  | list, tablet, approval, search, ssh-only |
| codex in ~/acme-web on studio-pc, done: Done: 3 files changed, tests pass, unread | button | 328 × 84 |  | list, tablet, error |
| Inbox, 2 needs you | tab | 72 × 80 |  | list, approval, swipe, error, text-200 |
| Machines | tab | 72 × 64 |  | list, tablet, empty, loading, offline, approval, search, swipe, error, ssh-only, text-200 |
| Spaces | tab | 72 × 64 |  | list, tablet, empty, loading, offline, approval, search, swipe, error, ssh-only, text-200 |
| To-do | tab | 72 × 64 |  | list, tablet, empty, loading, offline, approval, search, swipe, error, ssh-only, text-200 |
| Settings | tab | 72 × 64 |  | list, tablet, empty, loading, offline, approval, search, swipe, error, ssh-only, text-200 |
| Inbox | tab | 72 × 64 |  | tablet, empty, loading, offline, search |
| gemini in ~/docs on h0x-gcp, idle: Waiting for input | button | 328 × 84 |  | tablet |
| Interrupt codex | button | 48 × 48 |  | tablet |
| More: copy all, pin, close terminal | button | 48 × 48 |  | tablet |
| Paste into compose | button | 48 × 48 |  | tablet |
| Message codex | text field | 283 × 48 |  | tablet |
| Send, disabled until there is text | button | 48 × 48 |  | tablet |
| Key Escape | key | 48 × 48 |  | tablet |
| Key Tab | key | 48 × 48 |  | tablet |
| Key Ctrl | key | 48 × 48 |  | tablet |
| Key Alt | key | 48 × 48 |  | tablet |
| Key Arrow up | key | 48 × 48 |  | tablet |
| Key Arrow down | key | 48 × 48 |  | tablet |
| Key Enter | key | 64 × 48 |  | tablet |
| Add machine | button | 200 × 52 |  | empty |
| Loading agents | progress | 328 × 264 |  | loading |
| Open Machines | button | 125 × 48 |  | offline |
| claude in ~/acme-web on studio-pc, offline: Allow edit to README.md?, pinned | button | 328 × 84 |  | offline |
| codex in ~/infra on devbox, offline: Which region: eu-west-1 or us-east-1? | button | 328 × 84 |  | offline |
| opencode in ~/api-server on h0x-gcp, offline: Running tests (34/120)… | button | 328 × 84 |  | offline |
| Approve this phone on studio-pc, code 4 8 2 9 1 3, waiting | button | 328 × 76 | yes | approval |
| Clear search | button | 48 × 48 |  | search |
| Pin: opencode in ~/api-server | button | 76 × 88 |  | swipe |
| Mark read: opencode in ~/api-server | button | 76 × 88 |  | swipe |
| opencode in ~/api-server on h0x-gcp, working (swiped, actions shown) | button | 176 × 88 |  | swipe |
| Retry devbox | button | 111 × 48 |  | error |
| Inbox, 1 needs you | tab | 72 × 80 |  | ssh-only |
| claude in ~/acme-web on studio-pc, needs you | button | 328 × 240 |  | text-200 |

### agent

| Label (screen reader) | Role | Min target (dp) | Account only | Frames |
|---|---|---|---|---|
| Back to inbox | button | 48 × 48 |  | prompt, keyboard, interrupt, attach, question, finished, reconnect, select, locked, text-200 |
| Interrupt claude | button | 48 × 48 |  | prompt, keyboard, tablet, interrupt, attach, finished, reconnect, select, locked, text-200 |
| More: copy all, pin, close terminal | button | 48 × 48 |  | prompt, keyboard, tablet, interrupt, attach, question, finished, reconnect, select, locked, text-200 |
| Deny claude | button | 148 × 48 |  | prompt, tablet, interrupt, locked, text-200 |
| Approve claude | button | 148 × 48 |  | prompt, tablet, interrupt, locked, text-200 |
| Paste into compose | button | 48 × 48 |  | prompt, keyboard, tablet, interrupt, attach, question, reconnect, select, locked |
| Message claude | text field | 244 × 48 |  | prompt, keyboard, tablet, interrupt, attach, reconnect, select, locked |
| Send, disabled until there is text | button | 48 × 48 |  | prompt, tablet, interrupt, attach, reconnect, select, locked |
| Key Escape | key | 48 × 48 |  | prompt, keyboard, tablet, interrupt, attach, question, reconnect, select, locked |
| Key Tab | key | 48 × 48 |  | prompt, keyboard, tablet, interrupt, attach, question, reconnect, select, locked, text-200 |
| Key Ctrl | key | 48 × 48 |  | prompt, tablet, interrupt, attach, question, reconnect, select, locked, text-200 |
| Key Alt | key | 48 × 48 |  | prompt, keyboard, tablet, interrupt, attach, question, reconnect, select, locked |
| Key Arrow up | key | 48 × 48 |  | prompt, keyboard, tablet, interrupt, attach, question, reconnect, select, locked |
| Key Arrow down | key | 48 × 48 |  | prompt, keyboard, tablet, interrupt, attach, question, reconnect, select, locked |
| Key Enter | key | 64 × 48 |  | prompt, keyboard, tablet, interrupt, attach, question, reconnect, select, locked, text-200 |
| Send | button | 48 × 48 |  | keyboard, question |
| Key Ctrl, on for next key | key | 48 × 48 |  | keyboard |
| Inbox | tab | 80 × 64 |  | tablet |
| Machines | tab | 80 × 64 |  | tablet |
| Spaces | tab | 80 × 64 |  | tablet |
| To-do | tab | 80 × 64 |  | tablet |
| Settings | tab | 80 × 64 |  | tablet |
| Search agents, folders, machines | button | 48 × 48 |  | tablet |
| claude in ~/acme-web on studio-pc, needs you: Allow edit to README.md?, unread, pinned | button | 284 × 72 |  | tablet |
| codex in ~/infra on devbox, needs you: Which region: eu-west-1 or us-east-1?, unread | button | 284 × 72 |  | tablet |
| opencode in ~/api-server on h0x-gcp, working: Running tests (34/120)… | button | 284 × 72 |  | tablet |
| claude in ~/mobile-app on devbox, working: Editing lib/router.dart | button | 284 × 72 |  | tablet |
| codex in ~/acme-web on studio-pc, done: Done: 3 files changed, tests pass, unread | button | 284 × 72 |  | tablet |
| Key Arrow left | key | 48 × 48 |  | tablet |
| Key Arrow right | key | 48 × 48 |  | tablet |
| Interrupt | button | 92 × 48 |  | interrupt |
| Cancel | button | 79 × 48 |  | interrupt |
| Interrupt codex | button | 48 × 48 |  | question |
| Message codex | text field | 244 × 48 |  | question |
| Close terminal | button | 156 × 52 |  | finished |
| Try now | button | 76 × 48 |  | reconnect |
| Copy selection | button | 80 × 48 |  | select |
| Copy all terminal text | button | 80 × 48 |  | select |
| Share terminal text | button | 80 × 48 |  | select |
| Key Esc | key | 76 × 72 |  | text-200 |

### spaces

| Label (screen reader) | Role | Min target (dp) | Account only | Frames |
|---|---|---|---|---|
| Machine: studio-pc, online. Change machine | button | 288 × 48 |  | list, tablet, slots, confirm, notabs, old-core, loading, text-200 |
| Start an agent in acme-web | button | 112 × 48 |  | list, slots, confirm, notabs, offline, text-200 |
| Open claude (claude --continue), needs you | button | 174 × 104 |  | list, slots, confirm, offline |
| Open shell (pwsh), idle | button | 126 × 104 |  | list, slots, confirm, offline |
| Open tests (npm test -- --watch), working | button | 304 × 104 |  | list, slots, confirm, offline |
| Start an agent in api-server | button | 112 × 48 |  | list, tablet, slots, confirm, offline |
| Open codex (codex), working | button | 165 × 68 |  | list, tablet, slots, confirm, offline |
| Open shell (bash), idle | button | 165 × 56 |  | list, tablet, slots, confirm, offline |
| Open logs (tail -f app.log), working | button | 135 × 128 |  | list, tablet, slots, confirm, offline |
| Inbox, 2 needs you | tab | 72 × 80 |  | list, slots, confirm, notabs, offline, text-200 |
| Machines | tab | 72 × 64 |  | list, tablet, slots, confirm, empty, notabs, old-core, loading, offline, text-200 |
| Spaces | tab | 72 × 64 |  | list, tablet, slots, confirm, empty, notabs, old-core, loading, offline, text-200 |
| To-do | tab | 72 × 64 |  | list, tablet, slots, confirm, empty, notabs, old-core, loading, offline, text-200 |
| Settings | tab | 72 × 64 |  | list, tablet, slots, confirm, empty, notabs, old-core, loading, offline, text-200 |
| Inbox | tab | 72 × 64 |  | tablet, empty, old-core, loading |
| Tab 1 agent of acme-web | button | 296 × 52 |  | tablet |
| Tab 2 tests of acme-web | button | 296 × 52 |  | tablet |
| Tab 1 dev of api-server | button | 296 × 52 |  | tablet |
| Where: acme-web, new tab. Change | button | 328 × 48 |  | slots |
| Slot 1: start Claude Code (claude) | menu item | 328 × 56 |  | slots |
| Slot 2: start Codex (codex) | menu item | 328 × 56 |  | slots |
| Slot 3: start OpenCode (opencode) | menu item | 328 × 56 |  | slots |
| Slot 4: start Gemini (gemini) | menu item | 328 × 56 |  | slots |
| Start | button | 66 × 48 |  | confirm |
| Cancel | button | 79 × 48 |  | confirm |
| Machine: h0x-gcp, online. Change machine | button | 328 × 48 |  | empty |
| Start an agent | button | 200 × 52 |  | empty |
| Start an agent in scratch | button | 112 × 48 |  | notabs |
| Open claude (claude --continue), exited | button | 174 × 104 |  | notabs |
| Open shell (pwsh), exited | button | 126 × 104 |  | notabs |
| Open Inbox | button | 99 × 48 |  | old-core |
| Loading spaces | progress | 328 × 452 |  | loading |
| Machine: studio-pc, offline. Change machine | button | 328 × 48 |  | offline |
| Open claude | button | 296 × 100 |  | text-200 |
| Open shell | button | 296 × 100 |  | text-200 |

### todo

| Label (screen reader) | Role | Min target (dp) | Account only | Frames |
|---|---|---|---|---|
| List: Release 0.2, 5 open. Switch list | button | 167 × 56 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, delete-undo, offline, error, text-200 |
| List actions: new, rename, delete | button | 48 × 48 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, delete-undo, empty, all-done, offline, error |
| Computer: studio-pc. Change computer | button | 48 × 48 |  | list, list-switcher, computer-picker, edit-inline, reorder, delete-undo, empty, all-done, offline, error |
| 3 of 8 done | progress | 328 × 48 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, delete-undo, offline, error |
| Add a task | text field | 328 × 52 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, delete-undo, empty, all-done, offline, error, text-200 |
| Mark Write release notes done | checkbox | 48 × 48 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, delete-undo, offline, error, text-200 |
| Hide steps of Write release notes | button | 48 × 48 |  | list, tablet, list-switcher, computer-picker, offline, error |
| Task Write release notes, 1 of 3 steps done. Double-tap to edit | button | 232 × 52 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, delete-undo, offline, error |
| Mark step Draft the changelog not done | checkbox | 48 × 48 |  | list, tablet, list-switcher, computer-picker, offline, error |
| Step Draft the changelog, done | button | 248 × 48 |  | list, tablet, list-switcher, computer-picker, offline, error |
| Mark step Add screenshots done | checkbox | 48 × 48 |  | list, tablet, list-switcher, computer-picker, offline, error |
| Step Add screenshots | button | 248 × 48 |  | list, tablet, list-switcher, computer-picker, offline, error |
| Mark step Proofread done | checkbox | 48 × 48 |  | list, tablet, list-switcher, computer-picker, offline, error |
| Step Proofread | button | 248 × 48 |  | list, tablet, list-switcher, computer-picker, offline, error |
| Add step to Write release notes | button | 288 × 48 |  | list, tablet, list-switcher, computer-picker |
| Mark Update the app icon done | checkbox | 48 × 48 |  | list, tablet, list-switcher, computer-picker, reorder, delete-undo, offline, error, text-200 |
| Show steps of Update the app icon | button | 48 × 48 |  | list, tablet, list-switcher, computer-picker, reorder, delete-undo, offline, error |
| Task Update the app icon. Double-tap to edit | button | 232 × 52 |  | list, tablet, list-switcher, computer-picker, reorder, delete-undo, offline, error |
| Mark Test on a small phone done | checkbox | 48 × 48 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, delete-undo, offline, error |
| Show steps of Test on a small phone | button | 48 × 48 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, delete-undo, offline, error |
| Task Test on a small phone, 0 of 2 steps done. Double-tap to edit | button | 232 × 52 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, delete-undo, offline, error |
| Mark Book a design review done | checkbox | 48 × 48 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, offline, error |
| Show steps of Book a design review | button | 48 × 48 |  | list, tablet, list-switcher, computer-picker, edit-inline, offline, error |
| Task Book a design review. Double-tap to edit | button | 216 × 52 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, offline, error |
| Mark Reply to beta testers done | checkbox | 48 × 48 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, delete-undo, offline, error |
| Show steps of Reply to beta testers | button | 48 × 48 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, delete-undo, offline, error |
| Task Reply to beta testers. Double-tap to edit | button | 232 × 52 |  | list, tablet, list-switcher, computer-picker, edit-inline, reorder, delete-undo, offline, error |
| Completed, 3 tasks. Show | button | 328 × 48 |  | list |
| Inbox, 2 needs you | tab | 72 × 80 |  | list, list-switcher, computer-picker, reorder, delete-undo, empty, all-done, loading, offline, error, text-200 |
| Machines | tab | 72 × 64 |  | list, tablet, list-switcher, computer-picker, reorder, delete-undo, empty, all-done, loading, offline, error, text-200 |
| Spaces | tab | 72 × 64 |  | list, tablet, list-switcher, computer-picker, reorder, delete-undo, empty, all-done, loading, offline, error, text-200 |
| To-do | tab | 72 × 64 |  | list, tablet, list-switcher, computer-picker, reorder, delete-undo, empty, all-done, loading, offline, error, text-200 |
| Settings | tab | 72 × 64 |  | list, tablet, list-switcher, computer-picker, reorder, delete-undo, empty, all-done, loading, offline, error, text-200 |
| Inbox | tab | 80 × 64 |  | tablet |
| Machine: studio-pc, online. Change machine | button | 268 × 48 |  | tablet |
| List Release 0.2, 5 open | tab | 276 × 52 |  | tablet |
| List Home, 2 open | tab | 276 × 52 |  | tablet, list-switcher |
| List Reading, 4 open | tab | 276 × 52 |  | tablet, list-switcher |
| New list | button | 276 × 52 |  | tablet, list-switcher |
| Completed, 3 tasks. Hide | button | 428 × 48 |  | tablet |
| Mark Fix the login timeout not done | checkbox | 48 × 48 |  | tablet |
| Mark Bump version to 0.2.0 not done | checkbox | 48 × 48 |  | tablet |
| List Release 0.2, 5 open, current | radio | 328 × 52 |  | list-switcher |
| Rename list | menu item | 328 × 52 |  | list-switcher |
| Delete list… | menu item | 328 × 52 |  | list-switcher |
| studio-pc, account, online, 3 lists, current | radio | 328 × 64 |  | computer-picker |
| devbox, ssh, online, 1 list | radio | 328 × 64 |  | computer-picker |
| h0x-gcp, account, offline, last synced 9:12 | radio | 328 × 64 |  | computer-picker |
| Show steps of Write release notes | button | 48 × 48 |  | edit-inline, reorder, delete-undo |
| Edit task title | text field | 268 × 48 |  | edit-inline |
| Save task title | button | 88 × 48 |  | edit-inline |
| Delete task Test on a small phone | button | 96 × 52 |  | delete-undo |
| Undo delete | button | 60 × 48 |  | delete-undo |
| List: Reading, 0 open. Switch list | button | 130 × 56 |  | empty |
| List: Home, 0 open. Switch list | button | 106 × 56 |  | all-done |
| 2 of 2 done | progress | 328 × 48 |  | all-done |
| Completed, 2 tasks. Hide | button | 328 × 48 |  | all-done |
| Mark Water the plants not done | checkbox | 48 × 48 |  | all-done |
| Mark Call the plumber not done | checkbox | 48 × 48 |  | all-done |
| Loading the list | progress | 328 × 292 |  | loading |
| Task Write release notes | button | 220 × 128 |  | text-200 |
| Task Update the app icon | button | 220 × 128 |  | text-200 |

### settings

| Label (screen reader) | Role | Min target (dp) | Account only | Frames |
|---|---|---|---|---|
| Account: dev@example.com, signed in with Google | button | 328 × 72 | yes | top, top-dark, remove-confirm, notifications-off |
| Theme: System, Paper when light, Darkmatter when dark | button | 328 × 64 |  | top, top-dark, ssh-only, remove-confirm, notifications-off, text-200 |
| Unlock with fingerprint, on | switch | 328 × 64 |  | top, top-dark, ssh-only, remove-confirm, notifications-off, text-200 |
| Notifications from studio-pc, on | switch | 328 × 64 | yes | top, top-dark, remove-confirm |
| Notifications from h0x-gcp, off | switch | 328 × 64 | yes | top, top-dark, remove-confirm, notifications-off |
| Notifications from devbox, on | switch | 328 × 64 |  | top, top-dark, ssh-only, remove-confirm |
| Inbox, 2 needs you | tab | 72 × 80 |  | top, top-dark, lower, regen-confirm, remove-confirm, notifications-off, text-200 |
| Machines | tab | 72 × 64 |  | top, top-dark, tablet, lower, ssh-only, regen-confirm, remove-confirm, theme-picker-tablet, notifications-off, text-200 |
| Spaces | tab | 72 × 64 |  | top, top-dark, tablet, lower, ssh-only, regen-confirm, remove-confirm, theme-picker-tablet, notifications-off, text-200 |
| To-do | tab | 72 × 64 |  | top, top-dark, tablet, lower, ssh-only, regen-confirm, remove-confirm, theme-picker-tablet, notifications-off, text-200 |
| Settings | tab | 72 × 64 |  | top, top-dark, tablet, lower, ssh-only, regen-confirm, remove-confirm, theme-picker-tablet, notifications-off, text-200 |
| Inbox | tab | 80 × 64 |  | tablet, theme-picker-tablet |
| Account settings | tab | 296 × 52 | yes | tablet |
| Appearance settings | tab | 296 × 52 |  | tablet |
| Security settings | tab | 296 × 52 |  | tablet |
| Notifications settings | tab | 296 × 52 |  | tablet |
| Phones settings | tab | 296 × 52 | yes | tablet |
| SSH key settings | tab | 296 × 52 |  | tablet |
| Known hosts settings | tab | 296 × 52 |  | tablet |
| About settings | tab | 296 × 52 |  | tablet |
| Remove this phone (signs out) | button | 48 × 48 | yes | tablet, lower, regen-confirm |
| Remove Galaxy Tab S9 | button | 48 × 48 | yes | tablet, lower, regen-confirm |
| dev@example.com | button | 376 × 64 | yes | tablet |
| Sign out | button | 376 × 56 | yes | tablet |
| This phone's public key, ed25519, fingerprint SHA256 4mQe | text | 296 × 54 |  | lower, ssh-only, regen-confirm |
| Copy public key | button | 142 × 48 |  | lower, ssh-only, regen-confirm |
| Share public key | button | 142 × 48 |  | lower, ssh-only, regen-confirm |
| Regenerate key (asks first) | button | 180 × 48 |  | lower, ssh-only, regen-confirm |
| Forget host key of devbox | button | 48 × 48 |  | lower, regen-confirm |
| Forget host key of raspi | button | 48 × 48 |  | lower, regen-confirm |
| Inbox, 1 needs you | tab | 72 × 80 |  | ssh-only |
| Regenerate | button | 110 × 48 |  | regen-confirm |
| Cancel | button | 79 × 48 |  | regen-confirm, remove-confirm |
| Remove and sign out | button | 173 × 48 |  | remove-confirm |
| Back | button | 48 × 48 |  | theme-picker, theme-picker-dark, theme-picker-tablet |
| Appearance: System, selected | tab | 107 × 48 |  | theme-picker |
| Appearance: Light | tab | 107 × 48 |  | theme-picker, theme-picker-dark, theme-picker-tablet |
| Appearance: Dark | tab | 107 × 48 |  | theme-picker |
| Theme Paper, light, selected | radio | 328 × 72 |  | theme-picker |
| Theme Neo Brutalism, light | radio | 328 × 72 |  | theme-picker |
| Theme Soft Pop, light | radio | 328 × 72 |  | theme-picker |
| Theme Graphite, dark | radio | 328 × 72 |  | theme-picker, theme-picker-dark, theme-picker-tablet |
| Theme Ink, dark | radio | 328 × 72 |  | theme-picker, theme-picker-dark, theme-picker-tablet |
| Theme Moss, dark | radio | 328 × 72 |  | theme-picker, theme-picker-dark, theme-picker-tablet |
| Theme Amber Minimal, dark | radio | 328 × 72 |  | theme-picker, theme-picker-dark, theme-picker-tablet |
| Theme Atom One Dark, dark | radio | 328 × 72 |  | theme-picker, theme-picker-dark, theme-picker-tablet |
| Theme Candyland, dark | radio | 328 × 72 |  | theme-picker, theme-picker-dark, theme-picker-tablet |
| Theme Claymorphism, dark | radio | 328 × 72 |  | theme-picker, theme-picker-dark, theme-picker-tablet |
| Theme Darkmatter, dark, selected | radio | 328 × 72 |  | theme-picker, theme-picker-dark |
| Theme Win98, dark | radio | 328 × 72 |  | theme-picker, theme-picker-dark, theme-picker-tablet |
| Theme Sodium, dark | radio | 328 × 72 |  | theme-picker, theme-picker-dark, theme-picker-tablet |
| Theme Voltage, dark | radio | 328 × 72 |  | theme-picker, theme-picker-dark |
| Theme Phosphor, dark | radio | 328 × 72 |  | theme-picker, theme-picker-dark, theme-picker-tablet |
| Appearance: System | tab | 107 × 48 |  | theme-picker-dark, theme-picker-tablet |
| Appearance: Dark, selected | tab | 107 × 48 |  | theme-picker-dark, theme-picker-tablet |
| Theme Darkmatter, dark | radio | 348 × 72 |  | theme-picker-tablet |
| Theme Voltage, dark, selected | radio | 348 × 72 |  | theme-picker-tablet |
| Use Voltage for dark | button | 160 × 52 |  | theme-picker-tablet |
| Open Android settings | button | 170 × 48 |  | notifications-off |
| Notifications from studio-pc, off | switch | 328 × 64 | yes | notifications-off |
| Notifications from devbox, off | switch | 328 × 64 |  | notifications-off |

## How these were made

The SVGs are generated by a small Python script that measures text with the real font metrics, so nothing clips, and records each touch target for the table above. The script lives outside the repo in the local scratch folder (`.cache/scratch/mobile-design/gen.py` and one module per board). The previews were rendered with headless Chrome at 1:1.
