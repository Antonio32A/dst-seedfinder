"use client";

import { loginUrl } from "@/lib/api-client";
import { creditsPerSecond, DAILY_CREDITS, formatCredits, MAX_DOLLARS_PER_HOUR, STARTING_FEE } from "@/lib/credits";
import type { Account } from "@/lib/use-account";

const CREDITS_HINT = `Credits are topped up to ${DAILY_CREDITS} daily at 00:00 UTC. A search costs ${STARTING_FEE} credits to start a server, then ${creditsPerSecond(MAX_DOLLARS_PER_HOUR)} credits a second on a $${MAX_DOLLARS_PER_HOUR}/h server, less on cheaper ones.`;

export default function SiteHeader({ account }: { account: Account }) {
  const { user, loading } = account;
  return (
    <header className="header">
      <div className="brand">
        <a href="https://antonio32a.com" className="logo">
          antonio32a.com
        </a>
        <a href="/" className="brand__site">
          seedfinder
        </a>
      </div>
      {!loading && (
        <nav className="account" aria-label="Account">
          {user ? (
            <>
              <span className="account__name">{user.globalName ?? user.username}</span>
              <span className="account__credits" title={CREDITS_HINT} tabIndex={0}>
                {formatCredits(user.credits)}/{formatCredits(user.dailyCredits)} credits
              </span>
              <button type="button" className="link-button" onClick={() => void account.logOut()}>
                log out
              </button>
            </>
          ) : (
            <a className="button" href={loginUrl()}>
              Log in with Discord
            </a>
          )}
        </nav>
      )}
    </header>
  );
}
