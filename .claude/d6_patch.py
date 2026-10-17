"""Apply D-6 Train letterhead edits."""
import sys

path = 'lib/features/train/screens/train_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Eyebrow: literal Dart escape · (6 chars)
old1 = "'PHASE ${plan.phase} \\u00B7 ${plan.phaseName.toUpperCase()}'"
new1 = "'TRAIN \\u00B7 WK $selectedWeek OF ${plan.weeks.length}'"
if old1 not in content:
    print('OLD1 NOT FOUND', file=sys.stderr)
    sys.exit(1)
content = content.replace(old1, new1)

# RichText block — also has · literal
old2 = """          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: AppTypography.h2.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
              children: [
                TextSpan(text: 'Week $selectedWeek of ${plan.weeks.length}'),
                TextSpan(
                  text: '  \\u00B7  $completedDays/$totalWorkoutDays done',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          WardBar(
            pct: progress,
            height: 4,
            trailingLabel: '$progressPercent%',
            trailingColor: AppColors.accent,
          ),"""
if old2 not in content:
    print('OLD2 NOT FOUND', file=sys.stderr)
    # Find a tip
    idx = content.find("RichText(")
    if idx > 0:
        print(repr(content[idx-20:idx+400]), file=sys.stderr)
    sys.exit(1)

new2 = """          const SizedBox(height: 4),
          // D-6 (Plan D): Fraunces title is the phase name; week + done
          // count moved to a subtitle line below.
          Text(
            plan.phaseName,
            style: AppTypography.h2.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$completedDays of $totalWorkoutDays sessions complete',
            style: AppTypography.body.copyWith(
              fontSize: 13,
              color: AppColors.textDim,
            ),
          ),
          const SizedBox(height: 10),
          WardBar(
            pct: progress,
            height: 4,
            trailingLabel: '$progressPercent%',
            trailingColor: AppColors.accent,
          ),
          const SizedBox(height: 10),
          // D-6 status strip — streak + freeze always; no rank chip on Train
          // (roadmap is source of truth for rank info per spec).
          WardStatusStrip(
            streakDays: ref.watch(streakProvider),
            freezesAvailable: ref.watch(streakFreezeProvider),
          ),"""
content = content.replace(old2, new2)

with open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)
print('OK')
