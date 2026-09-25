"use client";

import { loginUrl } from "@/lib/api-client";
import { formatCredits } from "@/lib/credits";
import type { Account } from "@/lib/use-account";

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
              <span className="account__credits" title="Credits reset daily at 00:00 UTC. 1 credit ≈ 0.1 s of compute." tabIndex={0}>
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
