import { DAILY_CREDITS, unitsToCredits } from "@/lib/jobs/credits";
import { discordAvatarUrl } from "@/lib/server/auth/discord";
import { getCurrentUser } from "@/lib/server/auth/session";
import { nextResetAt } from "@/lib/server/auth/users";
import { json } from "@/lib/server/http";

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
            resetsAt: nextResetAt()
        }
    });
}
