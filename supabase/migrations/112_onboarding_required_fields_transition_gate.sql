-- Intent: Require the 9 onboarding-critical user_profile fields (date_of_birth,
--   gender, height_cm, current_weight_kg, target_weight_kg, primary_goal,
--   fitness_experience, days_per_week, equipment_access) to be non-null at the
--   moment onboarding_completed_at transitions from NULL to a timestamp — closes
--   OI-46's third gap (previously enforced only by OnboardingNotifier's client-side
--   route sequence, no Postgres backstop).
-- Destructive?: no — a state-TRANSITION gate, not a blanket NOT NULL. Fires only
--   when onboarding_completed_at is being set for the first time (INSERT with it
--   already populated, or UPDATE where OLD.onboarding_completed_at IS NULL).
--   Already-completed rows being edited later (Edit Profile, syncs) are untouched:
--   onboarding_completed_at doesn't change on those, so OLD IS NOT NULL short-
--   circuits before any field is checked. Existing rows are never retroactively
--   validated — this only governs future transitions.
-- Rollback strategy: inline — DROP TRIGGER/FUNCTION block commented at end of file.
-- Linked diagnose-doc: docs/diagnoses/2026-07-29-oi46-daily-cap-toctou-<id>.md

CREATE OR REPLACE FUNCTION enforce_onboarding_required_fields()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.onboarding_completed_at IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.onboarding_completed_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.date_of_birth IS NULL OR NEW.gender IS NULL OR NEW.height_cm IS NULL
     OR NEW.current_weight_kg IS NULL OR NEW.target_weight_kg IS NULL
     OR NEW.primary_goal IS NULL OR NEW.fitness_experience IS NULL
     OR NEW.days_per_week IS NULL OR NEW.equipment_access IS NULL THEN
    RAISE EXCEPTION 'onboarding_completed_with_missing_fields (user_id=%)', NEW.user_id
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_onboarding_required_fields ON user_profile;

CREATE TRIGGER trg_onboarding_required_fields
  BEFORE INSERT OR UPDATE ON user_profile
  FOR EACH ROW EXECUTE FUNCTION enforce_onboarding_required_fields();

-- Rollback (inline):
-- DROP TRIGGER IF EXISTS trg_onboarding_required_fields ON user_profile;
-- DROP FUNCTION IF EXISTS enforce_onboarding_required_fields();
