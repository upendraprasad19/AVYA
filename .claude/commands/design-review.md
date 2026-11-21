# /design-review — Audit widget against design system

Review the file specified in $ARGUMENTS against the ICANBEFITTER design system.

## Steps
1. Read `/CLAUDE.md` Section 9 (Design System) and `Knowledgebase/UI.txt`
2. Read the target file
3. Check every value against the design tokens

## Checklist

### Colors
- [ ] Background uses `AppColors.bg` (#07090e), NOT any other dark color
- [ ] Cards use `AppColors.card` (#0e1219)
- [ ] Inputs use `AppColors.input` (#161d28)
- [ ] Borders use `AppColors.border` (#1c2535)
- [ ] Accent is `AppColors.accent` (#00D4FF Electric Cyan) — NOT #00e5a0 (old green)
- [ ] PRO badge uses `AppColors.proGold` (#F59E0B) — NOT accent cyan
- [ ] No hardcoded hex values — all from AppColors

### Typography
- [ ] All text uses Switzer font (GoogleFonts.switzer)
- [ ] Font sizes match scale: Display (28-40), Title (15-22), Body (12-15), Label (10), Micro (9)
- [ ] Font weights correct: 900 for display, 800 for title, 700 for label, 400 for body

### Spacing
- [ ] Screen padding: 18px
- [ ] Card padding: 16px
- [ ] Section gap: 14px
- [ ] Grid gap: 9px

### Border Radius
- [ ] Buttons: 100px (pill)
- [ ] Cards: 16-22px
- [ ] Rows: 12px
- [ ] Badges: 100px

### Components
- [ ] Primary buttons: bg cyan, text black w900, radius 100
- [ ] Cards: bg card, border 1 border-color, radius 16, padding 16
- [ ] PRO locked: blur + dark overlay + gold badge + cyan CTA

## Output
Per-item PASS/FAIL with line number and specific fix.
