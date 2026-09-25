import { DAILY_CREDITS, unitsToCredits } from "@/lib/credits";
import { discordAvatarUrl } from "@/lib/server/discord";
import { json } from "@/lib/server/http";
import { getCurrentUser } from "@/lib/server/session";
import { nextResetAt } from "@/lib/server/users";

export async function GET() {
  const user = await getCurrentUser();
  return json({
    user: user && {
      id: user.id,
      username: user.username,
      globalName: user.global_name,
      avatarUrl: discordAvatarUrl(user.id, user.avatar),
      credits: unitsToCredits(user.credit_units),
      dailyCredits: DAILY_CREDITS,
      resetsAt: nextResetAt(),
    },
  });
}
