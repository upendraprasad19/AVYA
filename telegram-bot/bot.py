"""
@AVYACoachBot — Telegram AI fitness coach for ICANBEFITTER.

Connects Telegram users to their ICANBEFITTER account and provides
AI coaching via the same model stack as the in-app coach.

Architecture:
  User sends message on Telegram
  → Bot queries Supabase for user context (daily snapshot)
  → Bot calls Cerebras AI (free tier or PRO based on subscription)
  → Response sent back to Telegram
  → Interaction saved to Supabase ai_coach_interactions

Connection flow:
  1. User types /start in Telegram
  2. Bot asks for their ICANBEFITTER email
  3. Bot verifies email exists in Supabase users table
  4. Bot saves telegram_chat_id to telegram_connections table
  5. User can now chat with their AI coach on Telegram
"""

import os
import logging
from datetime import datetime, timedelta

import httpx
from dotenv import load_dotenv
from supabase import create_client, Client
from telegram import Update, BotCommand
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    ConversationHandler,
    ContextTypes,
    filters,
)

load_dotenv()

# ── Config ────────────────────────────────────────────────────────

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")
CEREBRAS_API_KEY = os.getenv("CEREBRAS_API_KEY", "")
CEREBRAS_FREE_API_KEY = os.getenv("CEREBRAS_FREE_API_KEY", "")

CEREBRAS_BASE_URL = "https://api.cerebras.ai/v1"
FREE_MODEL = "llama3.1-8b"
PRO_MODEL = "gpt-oss-120b"

FREE_TRIAL_DAYS = 30
FREE_MESSAGES_PER_DAY = 15

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

# ── Supabase Client ───────────────────────────────────────────────

supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

# ── Conversation States ──────────────────────────────────────────

WAITING_EMAIL = 0

# ── Helpers ──────────────────────────────────────────────────────


def get_user_by_email(email: str) -> dict | None:
    """Look up a user in Supabase by email."""
    result = supabase.table("users").select("*").eq("email", email).limit(1).execute()
    if result.data:
        return result.data[0]
    return None


def get_user_by_chat_id(chat_id: int) -> dict | None:
    """Look up a connected Telegram user by chat_id."""
    result = (
        supabase.table("telegram_connections")
        .select("*, users(*)")
        .eq("chat_id", str(chat_id))
        .eq("is_active", True)
        .limit(1)
        .execute()
    )
    if result.data:
        conn = result.data[0]
        user = conn.get("users")
        if user:
            user["_connection"] = conn
            return user
    return None


def get_user_context(user_id: str) -> dict:
    """Build AI context from Supabase (mirrors app's daily snapshot)."""
    context = {}

    # Profile
    profile_result = (
        supabase.table("user_profile")
        .select("*")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
    )
    if profile_result.data:
        context["profile"] = profile_result.data[0]

    # Progress
    progress_result = (
        supabase.table("user_progress")
        .select("*")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
    )
    if progress_result.data:
        context["progress"] = progress_result.data[0]

    # Latest daily snapshot (most recent)
    snapshot_result = (
        supabase.table("user_daily_snapshots")
        .select("snapshot_json")
        .eq("user_id", user_id)
        .order("snapshot_date", desc=True)
        .limit(1)
        .execute()
    )
    if snapshot_result.data:
        context["daily_snapshot"] = snapshot_result.data[0].get("snapshot_json", {})

    return context


def is_pro(user: dict) -> bool:
    """Check if user has active PRO subscription."""
    status = user.get("subscription_status", "free")
    expires = user.get("subscription_expires_at")
    if status != "pro":
        return False
    if expires:
        try:
            exp_dt = datetime.fromisoformat(expires.replace("Z", "+00:00"))
            if exp_dt < datetime.now(exp_dt.tzinfo):
                return False
        except (ValueError, TypeError):
            pass
    return True


def is_trial_active(user: dict) -> bool:
    """Check if user's 30-day free AI trial is still active."""
    started = user.get("ai_chat_started_at")
    if not started:
        return True  # Trial hasn't started yet — will start on first message
    try:
        start_dt = datetime.fromisoformat(started.replace("Z", "+00:00"))
        elapsed = (datetime.now(start_dt.tzinfo) - start_dt).days
        return elapsed < FREE_TRIAL_DAYS
    except (ValueError, TypeError):
        return False


def get_today_message_count(user_id: str) -> int:
    """Count user messages sent today via Telegram."""
    today = datetime.utcnow().strftime("%Y-%m-%d")
    result = (
        supabase.table("ai_coach_interactions")
        .select("id", count="exact")
        .eq("user_id", user_id)
        .eq("channel", "telegram")
        .gte("created_at", f"{today}T00:00:00")
        .execute()
    )
    return result.count or 0


async def call_cerebras(
    message: str, context: dict, model: str, api_key: str
) -> str:
    """Call Cerebras AI API with user context."""
    system_prompt = (
        "You are AVYA, an AI fitness coach for ICANBEFITTER. "
        "You help Indian young professionals (22-35) with workouts, nutrition, and motivation. "
        "Be encouraging, specific, and culturally aware (Indian foods, gym culture). "
        "Keep responses concise (2-3 paragraphs max) for Telegram readability.\n\n"
        f"User context: {context}"
    )

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            f"{CEREBRAS_BASE_URL}/chat/completions",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": model,
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": message},
                ],
                "max_tokens": 500,
                "temperature": 0.7,
            },
        )
        response.raise_for_status()
        data = response.json()
        return data["choices"][0]["message"]["content"]


async def save_interaction(
    user_id: str,
    user_message: str,
    ai_response: str,
    model_used: str,
) -> None:
    """Save the conversation to Supabase."""
    supabase.table("ai_coach_interactions").insert(
        {
            "user_id": user_id,
            "channel": "telegram",
            "user_message": user_message,
            "ai_response": ai_response,
            "model_used": model_used,
            "created_at": datetime.utcnow().isoformat(),
        }
    ).execute()


# ── Command Handlers ─────────────────────────────────────────────


async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle /start — begin connection flow."""
    chat_id = update.effective_chat.id

    # Check if already connected
    user = get_user_by_chat_id(chat_id)
    if user:
        name = user.get("full_name", "there")
        await update.message.reply_text(
            f"Welcome back, {name}! 💪\n\n"
            "You're already connected. Just type any message to chat with your AI coach.\n\n"
            "Commands:\n"
            "/status — Your current stats\n"
            "/disconnect — Unlink this account"
        )
        return ConversationHandler.END

    await update.message.reply_text(
        "Welcome to AVYA Coach! 🏋️\n\n"
        "I'm your AI fitness coach from ICANBEFITTER.\n\n"
        "To get started, please enter the email address you used to sign up in the app:"
    )
    return WAITING_EMAIL


async def receive_email(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    """Handle email input during connection flow."""
    email = update.message.text.strip().lower()
    chat_id = update.effective_chat.id

    # Validate email format
    if "@" not in email or "." not in email:
        await update.message.reply_text(
            "That doesn't look like a valid email. Please try again:"
        )
        return WAITING_EMAIL

    # Look up user in Supabase
    user = get_user_by_email(email)
    if not user:
        await update.message.reply_text(
            "No ICANBEFITTER account found with that email.\n\n"
            "Please sign up in the app first, then come back here.\n"
            "Download: https://icanbefitter.com"
        )
        return ConversationHandler.END

    # Save connection
    user_id = user["id"]
    supabase.table("telegram_connections").upsert(
        {
            "user_id": user_id,
            "chat_id": str(chat_id),
            "connected_at": datetime.utcnow().isoformat(),
            "is_active": True,
        }
    ).execute()

    # Also update users table
    supabase.table("users").update(
        {
            "telegram_chat_id": str(chat_id),
            "telegram_connected": True,
        }
    ).eq("id", user_id).execute()

    name = user.get("full_name", "Champion")
    pro_status = "PRO" if is_pro(user) else "FREE"

    await update.message.reply_text(
        f"Connected! Welcome, {name}! 🎉\n\n"
        f"Account: {email}\n"
        f"Plan: {pro_status}\n\n"
        "You can now chat with your AI coach right here on Telegram.\n"
        "Try: \"What should I eat today?\" or \"How's my progress?\""
    )
    return ConversationHandler.END


async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle /status — show user stats."""
    chat_id = update.effective_chat.id
    user = get_user_by_chat_id(chat_id)

    if not user:
        await update.message.reply_text(
            "You're not connected yet. Use /start to link your ICANBEFITTER account."
        )
        return

    user_context = get_user_context(user["id"])
    profile = user_context.get("profile", {})
    progress = user_context.get("progress", {})

    name = profile.get("full_name", user.get("full_name", "User"))
    goal = profile.get("primary_goal", "general_fitness").replace("_", " ").title()
    phase = progress.get("current_phase", 1)
    week = progress.get("current_week", 1)
    workouts = progress.get("total_workouts_done", 0)
    streak = progress.get("current_streak_weeks", 0)
    pro = "PRO ⭐" if is_pro(user) else "FREE"

    await update.message.reply_text(
        f"📊 *{name}'s Stats*\n\n"
        f"🎯 Goal: {goal}\n"
        f"📅 Phase {phase}, Week {week}\n"
        f"🏋️ {workouts} workouts completed\n"
        f"🔥 {streak} week streak\n"
        f"💳 Plan: {pro}",
        parse_mode="Markdown",
    )


async def disconnect_command(
    update: Update, context: ContextTypes.DEFAULT_TYPE
) -> None:
    """Handle /disconnect — unlink Telegram account."""
    chat_id = update.effective_chat.id
    user = get_user_by_chat_id(chat_id)

    if not user:
        await update.message.reply_text("You're not connected to any account.")
        return

    # Deactivate connection
    supabase.table("telegram_connections").update({"is_active": False}).eq(
        "chat_id", str(chat_id)
    ).execute()

    supabase.table("users").update(
        {"telegram_connected": False}
    ).eq("id", user["id"]).execute()

    await update.message.reply_text(
        "Disconnected. Use /start to reconnect anytime."
    )


async def handle_message(
    update: Update, context: ContextTypes.DEFAULT_TYPE
) -> None:
    """Handle regular text messages — AI coaching."""
    chat_id = update.effective_chat.id
    user_message = update.message.text

    # Check connection
    user = get_user_by_chat_id(chat_id)
    if not user:
        await update.message.reply_text(
            "You're not connected yet. Use /start to link your ICANBEFITTER account."
        )
        return

    user_id = user["id"]
    user_is_pro = is_pro(user)

    # Check trial/limits for free users
    if not user_is_pro:
        if not is_trial_active(user):
            await update.message.reply_text(
                "Your 30-day AI trial has expired. 😔\n\n"
                "Upgrade to PRO for unlimited AI coaching:\n"
                "₹349/month or ₹2,999/year\n\n"
                "Open the ICANBEFITTER app to upgrade."
            )
            return

        today_count = get_today_message_count(user_id)
        if today_count >= FREE_MESSAGES_PER_DAY:
            await update.message.reply_text(
                f"You've used all {FREE_MESSAGES_PER_DAY} messages today.\n\n"
                "Upgrade to PRO for unlimited messages, or come back tomorrow!"
            )
            return

    # Get user context from Supabase
    user_context = get_user_context(user_id)

    # Show typing indicator
    await update.effective_chat.send_action("typing")

    # Call AI
    try:
        model = PRO_MODEL if user_is_pro else FREE_MODEL
        api_key = CEREBRAS_API_KEY if user_is_pro else CEREBRAS_FREE_API_KEY

        response = await call_cerebras(user_message, user_context, model, api_key)

        # Save interaction
        await save_interaction(user_id, user_message, response, model)

        # Start trial timer on first message if not started
        if not user.get("ai_chat_started_at"):
            supabase.table("users").update(
                {"ai_chat_started_at": datetime.utcnow().isoformat()}
            ).eq("id", user_id).execute()

        await update.message.reply_text(response)

    except httpx.HTTPStatusError as e:
        logger.error(f"AI API error: {e.response.status_code} - {e.response.text}")
        await update.message.reply_text(
            "I'm having trouble thinking right now. Please try again in a moment. 🤔"
        )
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        await update.message.reply_text(
            "Something went wrong. Please try again."
        )


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle /help."""
    await update.message.reply_text(
        "🏋️ *AVYA Coach Bot*\n\n"
        "I'm your AI fitness coach from ICANBEFITTER.\n\n"
        "*Commands:*\n"
        "/start — Connect your account\n"
        "/status — View your stats\n"
        "/disconnect — Unlink account\n"
        "/help — Show this message\n\n"
        "*Just chat:*\n"
        "\"What should I eat today?\"\n"
        "\"How's my progress?\"\n"
        "\"Give me a workout tip\"\n"
        "\"Am I eating enough protein?\"",
        parse_mode="Markdown",
    )


# ── Main ─────────────────────────────────────────────────────────


def main() -> None:
    """Start the bot."""
    if not TELEGRAM_BOT_TOKEN:
        logger.error("TELEGRAM_BOT_TOKEN not set in .env")
        return

    app = Application.builder().token(TELEGRAM_BOT_TOKEN).build()

    # Set bot commands for Telegram menu
    commands = [
        BotCommand("start", "Connect your ICANBEFITTER account"),
        BotCommand("status", "View your fitness stats"),
        BotCommand("help", "Show help and commands"),
        BotCommand("disconnect", "Unlink your account"),
    ]

    # Connection conversation handler
    connection_handler = ConversationHandler(
        entry_points=[CommandHandler("start", start_command)],
        states={
            WAITING_EMAIL: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, receive_email)
            ],
        },
        fallbacks=[CommandHandler("start", start_command)],
    )

    app.add_handler(connection_handler)
    app.add_handler(CommandHandler("status", status_command))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(CommandHandler("disconnect", disconnect_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    logger.info("@AVYACoachBot starting...")
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
