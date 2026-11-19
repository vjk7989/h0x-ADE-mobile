// Lucide icons: ISC licence, https://lucide.dev. The path data below is
// Lucide's, as drawn on the design boards (design/screens/*.svg).
//
// Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as
// part of Feather (MIT). All other copyright (c) for Lucide are held by
// Lucide Contributors 2022.
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES.

import 'dart:ui';

import 'package:material_ui/material_ui.dart';

// Lucide icons (ISC licence, https://lucide.dev), as drawn on the design boards.
// 24 x 24 viewBox. Stroke paths: stroke 1.75 at 24 dp (scale with size), round caps and joins.
// Paths whose second field is true are small filled dots. kLucideDuo = the duotone fill layer
// (paint at 18 % of the icon colour under the line icon, tokens section 10).
const kLucide = <String, List<(String, bool)>>{
  'search': [(r'M3 11a8 8 0 1 0 16 0a8 8 0 1 0 -16 0', false), (r'm21 21-4.3-4.3', false)],
  'settings': [(r'M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z', false), (r'M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0', false)],
  'inbox': [(r'M22 12L16 12L14 15L10 15L8 12L2 12', false), (r'M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z', false)],
  'spaces': [(r'M4.5 3h4a1.5 1.5 0 0 1 1.5 1.5v15a1.5 1.5 0 0 1 -1.5 1.5h-4a1.5 1.5 0 0 1 -1.5 -1.5v-15a1.5 1.5 0 0 1 1.5 -1.5z', false), (r'M15.5 3h4a1.5 1.5 0 0 1 1.5 1.5v4a1.5 1.5 0 0 1 -1.5 1.5h-4a1.5 1.5 0 0 1 -1.5 -1.5v-4a1.5 1.5 0 0 1 1.5 -1.5z', false), (r'M15.5 14h4a1.5 1.5 0 0 1 1.5 1.5v4a1.5 1.5 0 0 1 -1.5 1.5h-4a1.5 1.5 0 0 1 -1.5 -1.5v-4a1.5 1.5 0 0 1 1.5 -1.5z', false)],
  'server': [(r'M4 2h16a2 2 0 0 1 2 2v4a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-4a2 2 0 0 1 2 -2z', false), (r'M4 14h16a2 2 0 0 1 2 2v4a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-4a2 2 0 0 1 2 -2z', false), (r'M6 6h.01', false), (r'M6 18h.01', false)],
  'monitor': [(r'M4 3h16a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-10a2 2 0 0 1 2 -2z', false), (r'M8 21h8', false), (r'M12 17v4', false)],
  'laptop': [(r'M20 16V7a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v9m16 0H4m16 0 1.28 2.55a1 1 0 0 1-.9 1.45H3.62a1 1 0 0 1-.9-1.45L4 16', false)],
  'machines': [(r'M4 3h16a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-10a2 2 0 0 1 2 -2z', false), (r'M8 21h8', false), (r'M12 17v4', false), (r'm7 8 2.5 2L7 12', false), (r'M11.5 12H15', false)],
  'wifi-off': [(r'M12 20h.01', false), (r'M8.5 16.429a5 5 0 0 1 7 0', false), (r'M5 12.859a10 10 0 0 1 5.17-2.69', false), (r'M19 12.859a10 10 0 0 0-2.007-1.523', false), (r'M2 8.82a15 15 0 0 1 4.177-2.643', false), (r'M22 8.82a15 15 0 0 0-11.288-3.764', false), (r'm2 2 20 20', false)],
  'cloud': [(r'M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z', false)],
  'key': [(r'M2.586 17.414A2 2 0 0 0 2 18.828V21a1 1 0 0 0 1 1h3a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h1a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h.172a2 2 0 0 0 1.414-.586l.814-.814a6.5 6.5 0 1 0-4-4z', false), (r'M15.9 7.5a0.6 0.6 0 1 0 1.2 0a0.6 0.6 0 1 0 -1.2 0', true)],
  'share': [(r'M15 5a3 3 0 1 0 6 0a3 3 0 1 0 -6 0', false), (r'M3 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0', false), (r'M15 19a3 3 0 1 0 6 0a3 3 0 1 0 -6 0', false), (r'm8.59 13.51 6.83 3.98', false), (r'm15.41 6.51-6.82 3.98', false)],
  'mail': [(r'M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2z', false), (r'm22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7', false)],
  'github': [(r'M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4', false), (r'M9 18c-4.51 2-5-2-7-2', false)],
  'shield-alert': [(r'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z', false), (r'M12 8v4', false), (r'M12 16h.01', false)],
  'shield-check': [(r'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z', false), (r'm9 12 2 2 4-4', false)],
  'fingerprint': [(r'M12 10a2 2 0 0 0-2 2c0 1.02-.1 2.51-.26 4', false), (r'M14 13.12c0 2.38 0 6.38-1 8.88', false), (r'M17.29 21.02c.12-.6.43-2.3.5-3.02', false), (r'M2 12a10 10 0 0 1 18-6', false), (r'M2 16h.01', false), (r'M21.8 16c.2-2 .131-5.354 0-6', false), (r'M5 19.5C5.5 18 6 15 6 12a6 6 0 0 1 .34-2', false), (r'M8.65 22c.21-.66.45-1.32.57-2', false), (r'M9 6.8a6 6 0 0 1 9 5.2v2', false)],
  'check-circle': [(r'M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0', false), (r'm9 12 2 2 4-4', false)],
  'alert': [(r'M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0', false), (r'M12 8v4', false), (r'M12 16h.01', false)],
  'triangle': [(r'm21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3', false), (r'M12 9v4', false), (r'M12 17h.01', false)],
  'link': [(r'M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71', false), (r'M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71', false)],
  'download': [(r'M12 15V3', false), (r'M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4', false), (r'm7 10 5 5 5-5', false)],
  'more': [(r'M11 12a1 1 0 1 0 2 0a1 1 0 1 0 -2 0', false), (r'M11 5a1 1 0 1 0 2 0a1 1 0 1 0 -2 0', false), (r'M11 19a1 1 0 1 0 2 0a1 1 0 1 0 -2 0', false)],
  'pencil': [(r'M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z', false)],
  'network': [(r'M17 16h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1z', false), (r'M3 16h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1z', false), (r'M10 2h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1z', false), (r'M5 16v-3a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v3', false), (r'M12 12V8', false)],
  'chevron-down': [(r'm6 9 6 6 6-6', false)],
  'chevron-right': [(r'm9 18 6-6-6-6', false)],
  'arrow-left': [(r'm12 19-7-7 7-7', false), (r'M19 12H5', false)],
  'plus': [(r'M5 12h14', false), (r'M12 5v14', false)],
  'x': [(r'M18 6 6 18', false), (r'm6 6 12 12', false)],
  'check': [(r'M20 6 9 17l-5-5', false)],
  'copy': [(r'M10 8h10a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-10a2 2 0 0 1 2 -2z', false), (r'M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2', false)],
  'terminal': [(r'M12 19h8', false), (r'm4 17 6-6-6-6', false)],
  'square-terminal': [(r'm7 11 2-2-2-2', false), (r'M11 13h4', false), (r'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2z', false)],
  'lock': [(r'M5 11h14a2 2 0 0 1 2 2v7a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-7a2 2 0 0 1 2 -2z', false), (r'M7 11V7a5 5 0 0 1 10 0v4', false)],
  'refresh': [(r'M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8', false), (r'M21 3v5h-5', false), (r'M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16', false), (r'M8 16H3v5', false)],
  'info': [(r'M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0', false), (r'M12 16v-4', false), (r'M12 8h.01', false)],
  'smartphone': [(r'M7 2h10a2 2 0 0 1 2 2v16a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-16a2 2 0 0 1 2 -2z', false), (r'M12 18h.01', false)],
  'globe': [(r'M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0', false), (r'M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20', false), (r'M2 12h20', false)],
  'trash': [(r'M10 11v6', false), (r'M14 11v6', false), (r'M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6', false), (r'M3 6h18', false), (r'M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2', false)],
  'external': [(r'M15 3h6v6', false), (r'M10 14 21 3', false), (r'M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6', false)],
  'bell': [(r'M10.268 21a2 2 0 0 0 3.464 0', false), (r'M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326', false)],
  'eye': [(r'M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0', false), (r'M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0', false)],
  'circle': [(r'M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0', false)],
  'pin': [(r'M12 17v5', false), (r'M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z', false)],
  'stop': [(r'M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0', false), (r'M10 9h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1z', false)],
  'paste': [(r'M11 14h10', false), (r'M16 4h2a2 2 0 0 1 2 2v1.344', false), (r'm17 18 4-4-4-4', false), (r'M8 4H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 1.793-1.113', false), (r'M9 2h6a1 1 0 0 1 1 1v2a1 1 0 0 1 -1 1h-6a1 1 0 0 1 -1 -1v-2a1 1 0 0 1 1 -1z', false)],
  'send': [(r'M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z', false), (r'm21.854 2.147-10.94 10.939', false)],
  'enter': [(r'M20 4v7a4 4 0 0 1-4 4H4', false), (r'm9 10-5 5 5 5', false)],
  'play': [(r'M6 4.5v15a1 1 0 0 0 1.5.86l12.5-7.5a1 1 0 0 0 0-1.72L7.5 3.64A1 1 0 0 0 6 4.5z', false)],
  'bell-off': [(r'M10.268 21a2 2 0 0 0 3.464 0', false), (r'M17 17H4a1 1 0 0 1-.74-1.673C4.59 13.956 6 12.499 6 8a6 6 0 0 1 .258-1.742', false), (r'm2 2 20 20', false), (r'M8.668 3.01A6 6 0 0 1 18 8c0 2.687.77 4.653 1.707 6.05', false)],
  'updown': [(r'm7 15 5 5 5-5', false), (r'm7 9 5-5 5 5', false)],
  'log-out': [(r'm16 17 5-5-5-5', false), (r'M21 12H9', false), (r'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4', false)],
  'user': [(r'M7 8a5 5 0 1 0 10 0a5 5 0 1 0 -10 0', false), (r'M20 21a8 8 0 0 0-16 0', false)],
  'palette': [(r'M12 22a1 1 0 0 1 0-20 10 9 0 0 1 10 9 5 5 0 0 1-5 5h-2.25a1.75 1.75 0 0 0-1.4 2.8l.3.4a1.75 1.75 0 0 1-1.4 2.8z', false), (r'M12.9 6.5a0.6 0.6 0 1 0 1.2 0a0.6 0.6 0 1 0 -1.2 0', true), (r'M16.9 10.5a0.6 0.6 0 1 0 1.2 0a0.6 0.6 0 1 0 -1.2 0', true), (r'M5.9 12.5a0.6 0.6 0 1 0 1.2 0a0.6 0.6 0 1 0 -1.2 0', true), (r'M7.9 7.5a0.6 0.6 0 1 0 1.2 0a0.6 0.6 0 1 0 -1.2 0', true)],
  'history': [(r'M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8', false), (r'M3 3v5h5', false), (r'M12 7v5l4 2', false)],
  'archive': [(r'M3 3h18a1 1 0 0 1 1 1v3a1 1 0 0 1 -1 1h-18a1 1 0 0 1 -1 -1v-3a1 1 0 0 1 1 -1z', false), (r'M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8', false), (r'M10 12h4', false)],
  'zoom': [(r'M3 11a8 8 0 1 0 16 0a8 8 0 1 0 -16 0', false), (r'm21 21-4.3-4.3', false), (r'M11 8v6', false), (r'M8 11h6', false)],
  'todo': [(r'M13 5h8', false), (r'M13 12h8', false), (r'M13 19h8', false), (r'm3 17 2 2 4-4', false), (r'm3 7 2 2 4-4', false)],
  'grip': [(r'M8 12a1 1 0 1 0 2 0a1 1 0 1 0 -2 0', false), (r'M8 5a1 1 0 1 0 2 0a1 1 0 1 0 -2 0', false), (r'M8 19a1 1 0 1 0 2 0a1 1 0 1 0 -2 0', false), (r'M14 12a1 1 0 1 0 2 0a1 1 0 1 0 -2 0', false), (r'M14 5a1 1 0 1 0 2 0a1 1 0 1 0 -2 0', false), (r'M14 19a1 1 0 1 0 2 0a1 1 0 1 0 -2 0', false)],
  'mic': [(r'M12 19v3', false), (r'M19 10v2a7 7 0 0 1-14 0v-2', false), (r'M12 2h0a3 3 0 0 1 3 3v7a3 3 0 0 1 -3 3h-0a3 3 0 0 1 -3 -3v-7a3 3 0 0 1 3 -3z', false)],
  'square-pen': [(r'M12 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7', false), (r'M18.375 2.625a1 1 0 0 1 3 3l-9.013 9.014a2 2 0 0 1-.853.505l-2.873.84a.5.5 0 0 1-.62-.62l.84-2.873a2 2 0 0 1 .506-.852z', false)],
  'undo': [(r'M9 14 4 9l5-5', false), (r'M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5H11', false)],
  'hash': [(r'M4 9h16', false), (r'M4 15h16', false), (r'M10 3 8 21', false), (r'M16 3l-2 18', false)],
};

const kLucideDuo = <String, List<String>>{
  'user': [r'M7 8a5 5 0 1 0 10 0a5 5 0 1 0 -10 0'],
  'palette': [r'M12 22a1 1 0 0 1 0-20 10 9 0 0 1 10 9 5 5 0 0 1-5 5h-2.25a1.75 1.75 0 0 0-1.4 2.8l.3.4a1.75 1.75 0 0 1-1.4 2.8z'],
  'stop': [r'M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0'],
  'spaces': [r'M4.5 3h4a1.5 1.5 0 0 1 1.5 1.5v15a1.5 1.5 0 0 1 -1.5 1.5h-4a1.5 1.5 0 0 1 -1.5 -1.5v-15a1.5 1.5 0 0 1 1.5 -1.5z'],
  'inbox': [r'M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z'],
  'machines': [r'M4 3h16a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-10a2 2 0 0 1 2 -2z'],
  'monitor': [r'M4 3h16a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-10a2 2 0 0 1 2 -2z'],
  'square-terminal': [r'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2z'],
  'lock': [r'M5 11h14a2 2 0 0 1 2 2v7a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-7a2 2 0 0 1 2 -2z'],
  'shield-check': [r'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z'],
  'shield-alert': [r'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z'],
  'cloud': [r'M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z'],
  'key': [r'M2.586 17.414A2 2 0 0 0 2 18.828V21a1 1 0 0 0 1 1h3a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h1a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h.172a2 2 0 0 0 1.414-.586l.814-.814a6.5 6.5 0 1 0-4-4z'],
  'bell': [r'M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326'],
  'server': [r'M4 2h16a2 2 0 0 1 2 2v4a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-4a2 2 0 0 1 2 -2z', r'M4 14h16a2 2 0 0 1 2 2v4a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-4a2 2 0 0 1 2 -2z'],
  'laptop': [r'M20 16V7a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v9z'],
  'smartphone': [r'M7 2h10a2 2 0 0 1 2 2v16a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-16a2 2 0 0 1 2 -2z'],
  'network': [r'M10 2h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1z', r'M17 16h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1z', r'M3 16h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1z'],
  'download': [r'M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4z'],
};

final _paths = <String, Path>{};

Path _parse(String key, String d) =>
    _paths.putIfAbsent('$key|$d', () => parseSvgPath(d));

/// A Lucide icon by name, painted in a 24 x 24 box scaled to [size]: round
/// caps and joins, stroke 1.75 at 24 dp (1.5 at 16 dp or less). With [duo],
/// a fill layer at 18 % of the colour sits under the line icon (tokens
/// section 10). Decorative: the control around it carries the label.
class HxIcon extends StatelessWidget {
  const HxIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.color,
    this.duo = false,
  });

  final String name;
  final double size;
  final Color? color;
  final bool duo;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFF000000);
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _IconPainter(name, c, duo)),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.name, this.color, this.duo);

  final String name;
  final Color color;
  final bool duo;

  @override
  void paint(Canvas canvas, Size size) {
    final strokes = kLucide[name];
    if (strokes == null) return;
    canvas.save();
    canvas.scale(size.width / 24);
    if (duo) {
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: color.a * 0.18);
      for (final d in kLucideDuo[name] ?? const <String>[]) {
        canvas.drawPath(_parse('duo:$name', d), fill);
      }
    }
    // The stroke is in the 24 box, so it scales with the icon.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width <= 16 ? 1.5 : 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final solid = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    for (final (d, filled) in strokes) {
      final p = _parse('line:$name', d);
      canvas.drawPath(p, stroke);
      if (filled) canvas.drawPath(p, solid);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.name != name || old.color != color || old.duo != duo;
}

final _number = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
final _letter = RegExp(r'[A-Za-z]');
final _numStart = RegExp(r'[-+.\d]');

/// SVG path data (M L H V C S Q T A Z, absolute and relative) as a [Path].
Path parseSvgPath(String d) {
  final path = Path();
  var i = 0;
  var cmd = '';
  var x = 0.0, y = 0.0; // the current point
  var sx = 0.0, sy = 0.0; // the start of the subpath
  var cx = 0.0, cy = 0.0; // the last control point, for S and T
  var last = '';

  void skipSep() {
    while (i < d.length &&
        (d[i] == ' ' || d[i] == ',' || d[i] == '\n' || d[i] == '\t')) {
      i++;
    }
  }

  double num() {
    skipSep();
    final m = _number.matchAsPrefix(d, i);
    if (m == null) throw FormatException('bad path data at $i: $d');
    i = m.end;
    return double.parse(m.group(0)!);
  }

  bool flag() {
    skipSep();
    final c = d[i++];
    if (c != '0' && c != '1') throw FormatException('bad arc flag at $i: $d');
    return c == '1';
  }

  while (true) {
    skipSep();
    if (i >= d.length) break;
    if (_letter.hasMatch(d[i])) {
      cmd = d[i++];
    } else if (cmd.isEmpty || !_numStart.hasMatch(d[i])) {
      throw FormatException('bad path data at $i: $d');
    }
    final rel = cmd == cmd.toLowerCase();
    final up = cmd.toUpperCase();
    switch (up) {
      case 'Z':
        path.close();
        x = sx;
        y = sy;
        cmd = '';
      case 'M':
        var nx = num(), ny = num();
        if (rel) {
          nx += x;
          ny += y;
        }
        path.moveTo(nx, ny);
        x = sx = nx;
        y = sy = ny;
        // More pairs after M are implicit L.
        cmd = rel ? 'l' : 'L';
      case 'L':
        var nx = num(), ny = num();
        if (rel) {
          nx += x;
          ny += y;
        }
        path.lineTo(nx, ny);
        x = nx;
        y = ny;
      case 'H':
        var nx = num();
        if (rel) nx += x;
        path.lineTo(nx, y);
        x = nx;
      case 'V':
        var ny = num();
        if (rel) ny += y;
        path.lineTo(x, ny);
        y = ny;
      case 'C':
        var x1 = num(), y1 = num(), x2 = num(), y2 = num();
        var nx = num(), ny = num();
        if (rel) {
          x1 += x;
          y1 += y;
          x2 += x;
          y2 += y;
          nx += x;
          ny += y;
        }
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        cx = x2;
        cy = y2;
        x = nx;
        y = ny;
      case 'S':
        var x2 = num(), y2 = num(), nx = num(), ny = num();
        if (rel) {
          x2 += x;
          y2 += y;
          nx += x;
          ny += y;
        }
        final smooth = last == 'C' || last == 'S';
        final x1 = smooth ? 2 * x - cx : x;
        final y1 = smooth ? 2 * y - cy : y;
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        cx = x2;
        cy = y2;
        x = nx;
        y = ny;
      case 'Q':
        var x1 = num(), y1 = num(), nx = num(), ny = num();
        if (rel) {
          x1 += x;
          y1 += y;
          nx += x;
          ny += y;
        }
        path.quadraticBezierTo(x1, y1, nx, ny);
        cx = x1;
        cy = y1;
        x = nx;
        y = ny;
      case 'T':
        var nx = num(), ny = num();
        if (rel) {
          nx += x;
          ny += y;
        }
        final smooth = last == 'Q' || last == 'T';
        final x1 = smooth ? 2 * x - cx : x;
        final y1 = smooth ? 2 * y - cy : y;
        path.quadraticBezierTo(x1, y1, nx, ny);
        cx = x1;
        cy = y1;
        x = nx;
        y = ny;
      case 'A':
        final rx = num(), ry = num(), rot = num();
        final large = flag();
        final sweep = flag();
        var nx = num(), ny = num();
        if (rel) {
          nx += x;
          ny += y;
        }
        if (rx == 0 || ry == 0) {
          path.lineTo(nx, ny);
        } else {
          path.arcToPoint(
            Offset(nx, ny),
            radius: Radius.elliptical(rx.abs(), ry.abs()),
            rotation: rot,
            largeArc: large,
            clockwise: sweep,
          );
        }
        x = nx;
        y = ny;
      default:
        throw FormatException('unsupported path command $cmd in $d');
    }
    last = up;
  }
  return path;
}
