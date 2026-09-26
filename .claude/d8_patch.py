"""Apply D-8 AI Coach letterhead edits."""
import sys

path = 'lib/features/ai_coach/screens/ai_coach_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Eyebrow text
old1 = "'YOUR AI COACH \\u00B7 24/7'"
new1 = "'THE BRIDGE \\u00B7 24/7'"
if old1 not in content:
    print('OLD1 NOT FOUND', file=sys.stderr)
    sys.exit(1)
content = content.replace(old1, new1)

# 2. Replace the dynamic greeting Builder with static "Aye Captain" Text
old2 = """                Builder(builder: (_) {
                  final hour = DateTime.now().hour;
                  final tod = hour < 12
                      ? 'morning'
                      : hour < 17
                          ? 'afternoon'
                          : 'evening';
                  // AH.9 — pull the user's first name from the profile so
                  // the greeting reads "Good morning, Upendra." rather
                  // than the generic "Good morning.". Profile stores
                  // `full_name`; we use the first whitespace-separated
                  // token. Falls back silently when the name is missing
                  // or still the bootstrap 'User' placeholder.
                  final profile = ref.watch(userProfileProvider);
                  final fullName =
                      (profile['full_name'] as String? ?? '').trim();
                  final firstName = fullName.isEmpty || fullName == 'User'
                      ? null
                      : fullName.split(RegExp(r'\\s+')).first;
                  final greeting = firstName != null
                      ? 'Good $tod, $firstName.'
                      : 'Good $tod.';
                  return Text(
                    greeting,
                    style: AppTypography.h3.copyWith(
                      height: 1.0,
                      fontStyle: FontStyle.italic,
                    ),
                  );
                }),"""
new2 = """                // D-8 (Plan D): Title is the recruit's acknowledgement
                // to the Captain — short, on-brand, no "CAPTAIN" duplicate
                // with the eyebrow.
                Text(
                  'Aye Captain',
                  style: AppTypography.h3.copyWith(
                    height: 1.0,
                    fontStyle: FontStyle.italic,
                  ),
                ),"""
if old2 not in content:
    print('OLD2 NOT FOUND', file=sys.stderr)
    sys.exit(1)
content = content.replace(old2, new2)

# 3. Add WardStatusStrip after _buildCompactHeader(...) call
old3 = """                // ── Compact Header (avatar + title + mode tabs + menu) ──
                _buildCompactHeader(isPro, channel, telegramConnected),

                // ── Message count indicator ──"""
new3 = """                // ── Compact Header (avatar + title + mode tabs + menu) ──
                _buildCompactHeader(isPro, channel, telegramConnected),

                // D-8 status strip — streak + freeze always; no rank chip
                // on AI Coach (roadmap is source of truth per spec §6.3.3).
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
                  child: WardStatusStrip(
                    streakDays: ref.watch(streakProvider),
                    freezesAvailable: ref.watch(streakFreezeProvider),
                  ),
                ),

                // ── Message count indicator ──"""
if old3 not in content:
    print('OLD3 NOT FOUND', file=sys.stderr)
    sys.exit(1)
content = content.replace(old3, new3)

with open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)
print('OK')
